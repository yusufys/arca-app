from pathlib import Path
import plistlib
import shutil
import sys
repo = Path(__file__).resolve().parents[2]
source = Path(__file__).resolve().parent
root=Path(sys.argv[1]).resolve()
root.mkdir(parents=True,exist_ok=True)
revenuecat=Path(sys.argv[2]).resolve()
assert (revenuecat/'Package.swift').is_file(), 'Pass a purchases-ios-spm checkout as argument 2'
for name in ['ArcaUXFlows.swift','UXFlowsTests.swift','UXFlows.entitlements']:
 shutil.copyfile(source/name,root/name)
project=root/'ArcaUXFlows.xcodeproj';(project/'xcshareddata/xcschemes').mkdir(parents=True,exist_ok=True)
objects={}
seq=0
def add(isa,**kw):
 global seq
 seq+=1;key=f'D611202611050000{seq:08X}';objects[key]={'isa':isa,**kw};return key
def configs(settings):
 ids=[add('XCBuildConfiguration',name=n,buildSettings=settings.copy()) for n in ['Debug','Release']]
 return add('XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
def file(name,kind):return add('PBXFileReference',lastKnownFileType=kind,path=name,sourceTree='<group>')
def sourcephase(ids):return add('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=i) for i in ids],runOnlyForDeploymentPostprocessing=0)
def frameworkphase(ids=[]):return add('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=ids,runOnlyForDeploymentPostprocessing=0)
mainfile=file('ArcaUXFlows.swift','sourcecode.swift');testfile=file('UXFlowsTests.swift','sourcecode.swift')
pkg=add('XCLocalSwiftPackageReference',relativePath=str(repo))
ui=add('XCSwiftPackageProductDependency',package=pkg,productName='ArcaUI')
ui_link=add('PBXBuildFile',productRef=ui)
base={'SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_IDENTITY':'-','CODE_SIGN_ENTITLEMENTS':'UXFlows.entitlements','CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','ENABLE_TESTABILITY':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone','ONLY_ACTIVE_ARCH':'YES','SWIFT_EMIT_LOC_STRINGS':'NO','PRODUCT_NAME':'$(TARGET_NAME)','SUPPORTED_PLATFORMS':'iphonesimulator','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
def app(name,bundle,srcs,frameworks=[],products=[]):
 ref=add('PBXFileReference',explicitFileType='wrapper.application',path=name+'.app',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
 settings=base|{'PRODUCT_BUNDLE_IDENTIFIER':bundle,'INFOPLIST_KEY_CFBundleDisplayName':name}
 target=add('PBXNativeTarget',name=name,productName=name,productReference=ref,productType='com.apple.product-type.application',buildConfigurationList=configs(settings),buildPhases=[sourcephase(srcs),frameworkphase(frameworks)],buildRules=[],dependencies=[],packageProductDependencies=products)
 return target,ref
main,mainref=app('ArcaUXFlows','app.arca.acceptance.uxflows20261105',[mainfile],[ui_link],[ui])
testref=add('PBXFileReference',explicitFileType='wrapper.cfbundle',path='UXFlowsTests.xctest',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
deps=[add('PBXTargetDependency',target=t) for t in [main]]
test=add('PBXNativeTarget',name='UXFlowsTests',productName='UXFlowsTests',productReference=testref,productType='com.apple.product-type.bundle.ui-testing',buildConfigurationList=configs(base|{'PRODUCT_BUNDLE_IDENTIFIER':'app.arca.acceptance.uxflows20261105.uitests','TEST_TARGET_NAME':'ArcaUXFlows'}),buildPhases=[sourcephase([testfile]),frameworkphase()],buildRules=[],dependencies=deps)
products=add('PBXGroup',name='Products',sourceTree='<group>',children=[mainref,testref])
group=add('PBXGroup',sourceTree='<group>',children=[mainfile,testfile,products])
proj=add('PBXProject',attributes={'LastUpgradeCheck':'2720','TargetAttributes':{main:{'CreatedOnToolsVersion':'27.2'},test:{'CreatedOnToolsVersion':'27.2','TestTargetID':main}}},buildConfigurationList=configs({'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','ONLY_ACTIVE_ARCH':'YES'}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','ar','tr'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[main,test],packageReferences=[pkg])
rcpkg=add('XCLocalSwiftPackageReference',relativePath=str(revenuecat))
objects[proj]['packageReferences'].append(rcpkg)
rcfile=file(str(repo/'iOSApp/ArcaPurchases.swift'),'sourcecode.swift')
objects[group]['children'].append(rcfile)
objects[objects[main]['buildPhases'][0]]['files'].append(add('PBXBuildFile',fileRef=rcfile))
for name in ['RevenueCat','RevenueCatUI']:
 product=add('XCSwiftPackageProductDependency',package=rcpkg,productName=name)
 objects[main]['packageProductDependencies'].append(product)
 objects[objects[main]['buildPhases'][1]]['files'].append(add('PBXBuildFile',productRef=product))
(project/'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':proj},sort_keys=False))
def ref(t,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{t}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:ArcaUXFlows.xcodeproj"/>'
entries=''.join(f'<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{ref(t,n)}</BuildActionEntry>' for t,n in [(main,'ArcaUXFlows.app'),(test,'UXFlowsTests.xctest')])
scheme=f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2720" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>{entries}</BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test,'UXFlowsTests.xctest')}</TestableReference></Testables></TestAction></Scheme>'''
(project/'xcshareddata/xcschemes/UXFlows.xcscheme').write_text(scheme)
(root/'target-ids.txt').write_text(f'main={main}\ntest={test}\n')
print('Prepared an isolated screenshot app and UI test target. No production app or simulator data was changed.')
