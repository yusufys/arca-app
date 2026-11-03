"""Exercise cold launch and real two-device sync using a disposable Forge account."""
import argparse
import json
import os
import secrets
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BASE = 'https://arca-api.on-forge.com'
BUNDLE = 'app.arca.personalrecords'

def run(*args, env=None):
    return subprocess.check_output(args, text=True, env=env).strip()

def delete_fixture(email, password):
    # curl uses the same public ingress as the app. Send credentials via stdin only.
    def api(path, method, body=None, token=None):
        cfg = 'header = "Accept: application/json"\nheader = "Content-Type: application/json"\n'
        if token:
            cfg += f'header = "Authorization: Bearer {token}"\n'
        if body:
            cfg += 'data = '+json.dumps(json.dumps(body))+'\n'
        for _ in range(3):
            response = subprocess.run(['curl','-sS','--max-time','20','--config','-','-X',method,'-w','\n%{http_code}',BASE+'/api/v1/'+path],
                                     input=cfg,capture_output=True,text=True,check=True)
            payload, status = response.stdout.rsplit('\n',1)
            if status == '429':
                time.sleep(62)
                continue
            return int(status),json.loads(payload)
        raise RuntimeError('Rate limit prevented cleanup')
    status, response = api('auth/login','POST',dict(email=email,password=password))
    if status == 401: return
    assert status == 200, status
    status, receipt = api('account','DELETE',token=response['api_token'])
    assert status == 200 and receipt['verifiedZeroRemainingRecords']
    print('PASS disposable Forge account deleted', flush=True)

def simulator_build(work):
    project = work / 'source'
    project.mkdir()
    for name in ['Sources','Arca.xcodeproj','iOSApp']:
        shutil.copytree(REPO / name, project / name)
    shutil.copy(REPO / 'Package.swift', project)
    shutil.copytree(REPO / 'Tests', project / 'Tests')
    # Instrument a disposable copy of the app; no test controls are shipped.
    entry = project / 'iOSApp/ArcaiOSApp.swift'
    original = entry.read_text()
    hook = 'await viewModel.bootstrapIfNeeded()'
    assert original.count(hook) == 1
    entry.write_text(original.replace(hook, hook + """
                    if let stage = ProcessInfo.processInfo.environment["ARCA_TEST_STAGE"] {
                        await SyncAcceptance.writeResult(viewModel, mode: stage,
                            to: FileManager.default.temporaryDirectory.appendingPathComponent("acceptance.json"))
                    }""") + '\n' + (REPO / 'ci/SyncAcceptance.swift').read_text())
    subprocess.run(['xcodebuild','-project',str(project/'Arca.xcodeproj'),'-scheme','Arca',
                    '-configuration','Debug','-destination','generic/platform=iOS Simulator','-derivedDataPath',str(work/'build'),
                    'CODE_SIGNING_ALLOWED=YES','build'], check=True)
    return work / 'build/Build/Products/Debug-iphonesimulator/Arca.app'

def simulator_devices(app, ids):
    choices = json.loads(run('xcrun','simctl','list','devices','available','-j'))['devices']
    for runtime in sorted((k for k in choices if 'iOS-' in k), reverse=True):
        iphones = [x for x in choices[runtime] if x['name'].startswith('iPhone')]
        if iphones: break
    else: raise RuntimeError('No iPhone simulator runtime')
    for name in ['Arca A','Arca B']:
        udid = run('xcrun','simctl','create',name,iphones[0]['deviceTypeIdentifier'],runtime)
        ids.append(udid)
        run('xcrun','simctl','boot',udid)
        run('xcrun','simctl','bootstatus',udid,'-b')
        run('xcrun','simctl','install',udid,str(app))

def stage(name, index, ids, executable, work, environment):
    child = None
    if executable:
        result = work / ('result-'+name+'.json')
        env = dict(os.environ, **environment, ARCA_TEST_ROOT=str(work/str(index)), ARCA_TEST_STAGE=name,
                   ARCA_TEST_RESULT=str(result), ARCA_API_BASE_URL=BASE)
        child = subprocess.Popen([executable], env=env)
    else:
        udid = ids[index]
        data = run('xcrun','simctl','get_app_container',udid,BUNDLE,'data')
        result = Path(data) / 'tmp/acceptance.json'
        result.unlink(missing_ok=True)
        env = dict(os.environ, **{'SIMCTL_CHILD_'+k:v for k,v in environment.items()},
                   SIMCTL_CHILD_ARCA_TEST_STAGE=name)
        launch = run('xcrun','simctl','launch',udid,BUNDLE,env=env)
        pid = int(launch.rsplit(':',1)[1])
    try:
        for _ in range(900):
            if result.exists(): break
            if child and child.poll() is not None: break
            time.sleep(.2)
        if not result.exists(): raise RuntimeError('No result for '+name)
        value = json.loads(result.read_text())
        result.unlink()
        if value.get('status') != 'ok': raise RuntimeError(f'{name}: {value.get("error")}')
        print(f'PASS client {index+1} {name}', flush=True)
        return value
    finally:
        if child and child.poll() is None:
            child.kill()
            child.wait()
        elif not executable:
            # Simulator applications are host processes; SIGKILL bypasses graceful termination.
            try: os.kill(pid, signal.SIGKILL)
            except ProcessLookupError: pass
            time.sleep(.5)

def main():
    args = argparse.ArgumentParser()
    args.add_argument('--mac-executable')
    executable = args.parse_args().mac_executable
    ids = []
    credentials = {'ARCA_TEST_EMAIL': 'acceptance-'+secrets.token_hex(12)+'@example.com',
                   'ARCA_TEST_PASSWORD': secrets.token_urlsafe(32)}
    with tempfile.TemporaryDirectory(prefix='arca-sync-test-') as directory:
        work = Path(directory)
        account_attempted = False
        try:
            if not executable: simulator_devices(simulator_build(work), ids)
            seed = stage('seed',0,ids,executable,work,{})
            stage('resume',0,ids,executable,work,{})
            account_attempted = True
            source = stage('register',0,ids,executable,work,credentials)
            info = dict(credentials, ARCA_TEST_RECORD=seed['record'], ARCA_TEST_PHRASE=source['phrase'])
            stage('join',1,ids,executable,work,info)
            stage('verify',0,ids,executable,work,{'ARCA_TEST_RECORD':seed['record']})
        finally:
            try:
                if account_attempted: delete_fixture(credentials['ARCA_TEST_EMAIL'], credentials['ARCA_TEST_PASSWORD'])
            finally:
                for udid in ids:
                    subprocess.run(['xcrun','simctl','delete',udid], check=True)

if __name__ == '__main__': main()
