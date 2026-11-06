#!/usr/bin/env python3
"""Create a private PostgreSQL dump and optionally rehearse restoration in a NEW database.

Run on the backend host. Credentials are read in memory from Laravel, never printed.
This does not configure off-server storage, retention, or a backup schedule.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import uuid


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if result.returncode:
        # Database tools can include connection details in errors. Do not echo them.
        raise RuntimeError(f"{Path(args[0]).name} failed (exit {result.returncode}); check tool availability and database permissions")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--laravel-root', required=True, type=Path)
    parser.add_argument('--output-directory', required=True, type=Path)
    parser.add_argument('--verify-restore', action='store_true', help='Requires permission to create and drop a new temporary database')
    args = parser.parse_args()
    os.umask(0o077)
    root = args.laravel_root.resolve(strict=True)
    destination = args.output_directory.resolve()
    if destination == root or root in destination.parents:
        parser.error('Backup output must be outside the Laravel application directory')
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    if destination.stat().st_mode & 0o077:
        parser.error('Backup directory must be private (mode 700)')
    config = json.loads(run(['php', '-r', '''require "vendor/autoload.php";
        $app = require "bootstrap/app.php";
        $app->make(Illuminate\\Contracts\\Console\\Kernel::class)->bootstrap();
        echo json_encode(config("database.connections.".config("database.default")));'''], cwd=root))
    if config.get('driver') != 'pgsql' or config.get('url'):
        parser.error('This helper requires explicit PostgreSQL connection settings; DATABASE_URL needs separate configuration')
    env = dict(os.environ, PGHOST=str(config['host']), PGPORT=str(config.get('port', 5432)),
               PGDATABASE=config['database'], PGUSER=config['username'], PGPASSWORD=config['password'],
               PGCONNECT_TIMEOUT='15', PGSSLMODE=config.get('sslmode', 'prefer'))
    started = time.monotonic()
    basename = 'arca-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + uuid.uuid4().hex[:8]
    archive = destination / (basename + '.dump')
    partial = destination / (basename + '.partial')
    try:
        run(['pg_dump', '--no-password', '--format=custom', '--no-owner', '--no-acl', '--file', str(partial)], env=env)
        inventory = run(['pg_restore', '--list', str(partial)], env=env)
        if 'TABLE DATA public encrypted_attachments' not in inventory:
            raise RuntimeError('Dump is missing the encrypted image table')
        partial.rename(archive)
    finally:
        partial.unlink(missing_ok=True)
    with archive.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    report = {'archive': archive.name, 'bytes': archive.stat().st_size,
              'sha256': digest,
              'created_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'dump_verified_readable': True, 'restore_verified': False,
              'off_server_copy_verified': False}
    manifest = archive.with_suffix('.json')
    manifest.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS private dump created and readable:', archive)
    if args.verify_restore:
        # A fresh UUID name prevents touching an existing/production database.
        temporary_database = 'arca_restore_' + uuid.uuid4().hex
        restore_env = dict(env, PGDATABASE='postgres')
        run(['createdb', '--no-password', temporary_database], env=restore_env)
        try:
            run(['pg_restore', '--no-password', '--exit-on-error', '--no-owner', '--no-acl',
                 '--dbname', temporary_database, str(archive)], env=restore_env)
            restored_env = dict(restore_env, PGDATABASE=temporary_database)
            result = run(['psql', '--no-password', '-XAt', '-v', 'ON_ERROR_STOP=1', '-c',
                          "SELECT count(*) FROM information_schema.columns WHERE table_schema='public' "
                          "AND table_name='encrypted_attachments' AND column_name='encrypted_blob';"], env=restored_env)
            if result.strip() != '1':
                raise RuntimeError('Restored schema is missing encrypted image storage')
            counts = run(['psql', '--no-password', '-XAt', '-v', 'ON_ERROR_STOP=1', '-c',
                          'SELECT count(*) FROM encrypted_attachments;'], env=restored_env)
            report.update(restore_verified=True, restored_image_rows=int(counts.strip()),
                          elapsed_seconds=round(time.monotonic() - started, 2))
        finally:
            run(['dropdb', '--no-password', temporary_database], env=restore_env)
        manifest.write_text(json.dumps(report, indent=2) + '\n')
        print('PASS isolated restore and encrypted-image schema verified; temporary database removed')
    else:
        print('PENDING isolated restore, off-server copy and scheduled recovery')


if __name__ == '__main__':
    try:
        main()
    except RuntimeError as error:
        raise SystemExit(str(error))
