#!/usr/bin/env python3
"""Generate the small Xcode project using only Python's standard library.

Source folders use Xcode's synchronized groups, so new Swift files are picked up
without regenerating. Run this only when changing project-level configuration.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = []

def oid(name):
    import hashlib
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(name, body):
    objects.append(f'{oid(name)} /* {name} */ = {{ {body} }};')

def ref(name):
    return oid(name)

def array(names):
    return '(' + ', '.join(ref(n) for n in names) + (',' if names else '') + ')'

add('Google package', 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/google/GoogleSignIn-iOS"; requirement = { kind = exactVersion; version = 10.0.0; };')
for product in ['GoogleSignIn', 'GoogleSignInSwift']:
    add(product + ' dependency', f'isa = XCSwiftPackageProductDependency; package = {ref("Google package")}; productName = {product};')
    add(product + ' framework', f'isa = PBXBuildFile; productRef = {ref(product + " dependency")};')
add('Auth settings', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Configuration/Auth.xcconfig; sourceTree = "<group>";')

apps = [('ClimbingApp' , 'app', 'com.frozenpop.ClimbingApp'),
        ('ClimbingAppTests', 'test', 'com.frozenpop.ClimbingAppTests'),
        ('ClimbingAppUITests', 'ui-test', 'com.frozenpop.ClimbingAppUITests')]
for name, kind, bundle in apps:
    ext = 'app' if kind == 'app' else 'xctest'
    add(name + ' product', f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if kind == "app" else "wrapper.cfbundle"}; includeInIndex = 0; path = {name}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;')
    if kind == 'app':
        add('App exclusions', f'isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (Info.plist, ClimbingApp.entitlements); target = {ref(name + " target")};')
    add(name + ' folder', f'isa = PBXFileSystemSynchronizedRootGroup; exceptions = {array(["App exclusions"]) if kind == "app" else "()"}; path = {name}; sourceTree = "<group>";')
    for phase, isa in [('Sources', 'PBXSourcesBuildPhase'), ('Frameworks', 'PBXFrameworksBuildPhase'), ('Resources', 'PBXResourcesBuildPhase')]:
        add(name + phase, f'isa = {isa}; buildActionMask = 2147483647; files = {array(["GoogleSignIn framework", "GoogleSignInSwift framework"]) if kind == "app" and phase == "Frameworks" else "()"}; runOnlyForDeploymentPostprocessing = 0;')
    dependencies = []
    if kind != 'app':
        add(name + ' proxy', f'isa = PBXContainerItemProxy; containerPortal = {ref("Project")}; proxyType = 1; remoteGlobalIDString = {ref("ClimbingApp target")}; remoteInfo = ClimbingApp;')
        add(name + ' dependency', f'isa = PBXTargetDependency; target = {ref("ClimbingApp target")}; targetProxy = {ref(name + " proxy")};')
        dependencies = [name + ' dependency']
    for config in ['Debug', 'Release']:
        settings = f'CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = {"NO" if kind == "app" else "YES"}; MARKETING_VERSION = 0.1.0; PRODUCT_BUNDLE_IDENTIFIER = {bundle}; PRODUCT_NAME = "$(TARGET_NAME)"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = 1;'
        if kind == 'app':
            settings += ' CODE_SIGN_ENTITLEMENTS = ClimbingApp/ClimbingApp.entitlements; INFOPLIST_FILE = ClimbingApp/Info.plist; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; INFOPLIST_KEY_CFBundleDisplayName = "Sendr"; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports"; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";'
        if kind == 'test':
            settings += ' BUNDLE_LOADER = "$(TEST_HOST)"; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/ClimbingApp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ClimbingApp";'
        if kind == 'ui-test':
            settings += ' TEST_TARGET_NAME = ClimbingApp;'
        add(name + config, f'isa = XCBuildConfiguration; baseConfigurationReference = {ref("Auth settings")}; buildSettings = {{ {settings} }}; name = {config};')
    add(name + ' config', f'isa = XCConfigurationList; buildConfigurations = {array([name + "Debug", name + "Release"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    product = 'com.apple.product-type.application' if kind == 'app' else ('com.apple.product-type.bundle.unit-test' if kind == 'test' else 'com.apple.product-type.bundle.ui-testing')
    add(name + ' target', f'isa = PBXNativeTarget; buildConfigurationList = {ref(name + " config")}; buildPhases = {array([name + "Sources", name + "Frameworks", name + "Resources"])}; buildRules = (); dependencies = {array(dependencies)}; fileSystemSynchronizedGroups = {array([name + " folder"])}; name = {name}; packageProductDependencies = {array(["GoogleSignIn dependency", "GoogleSignInSwift dependency"]) if kind == "app" else "()"}; productName = {name}; productReference = {ref(name + " product")}; productType = "{product}";')

add('Products', f'isa = PBXGroup; children = {array([name + " product" for name, _, _ in apps])}; name = Products; sourceTree = "<group>";')
add('Root', f'isa = PBXGroup; children = {array([name + " folder" for name, _, _ in apps] + ["Products", "Auth settings"])}; sourceTree = "<group>";')
for config in ['Debug', 'Release']:
    settings = 'ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; CLANG_WARN_DOCUMENTATION_COMMENTS = YES; CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES; GCC_C_LANGUAGE_STANDARD = gnu17; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; SWIFT_EMIT_LOC_STRINGS = YES;'
    settings += ' DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)"); ONLY_ACTIVE_ARCH = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"; SWIFT_OPTIMIZATION_LEVEL = "-Onone";' if config == 'Debug' else ' DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule; VALIDATE_PRODUCT = YES;'
    add('Project' + config, f'isa = XCBuildConfiguration; baseConfigurationReference = {ref("Auth settings")}; buildSettings = {{ {settings} }}; name = {config};')
add('Project config', f'isa = XCConfigurationList; buildConfigurations = {array(["ProjectDebug", "ProjectRelease"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('Project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2710; LastUpgradeCheck = 2710; }}; buildConfigurationList = {ref("Project config")}; compatibilityVersion = "Xcode 16.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {ref("Root")}; minimizedProjectReferenceProxies = 1; packageReferences = {array(["Google package"])}; preferredProjectObjectVersion = 77; productRefGroup = {ref("Products")}; projectDirPath = ""; projectRoot = ""; targets = {array([name + " target" for name, _, _ in apps])};')
project = '// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 77;\nobjects = {\n' + '\n'.join(objects) + '\n};\nrootObject = ' + ref('Project') + ';\n}\n'
(ROOT / 'ClimbingApp.xcodeproj/project.pbxproj').write_text(project)

def buildable(name):
    suffix = 'app' if name == 'ClimbingApp' else 'xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(name + " target")}" BuildableName="{name}.{suffix}" BlueprintName="{name}" ReferencedContainer="container:ClimbingApp.xcodeproj"/>'

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable('ClimbingApp')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
<TestableReference skipped="NO" parallelizable="NO">{buildable('ClimbingAppTests')}</TestableReference>
<TestableReference skipped="NO" parallelizable="NO">{buildable('ClimbingAppUITests')}</TestableReference>
</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('ClimbingApp')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('ClimbingApp')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(ROOT / 'ClimbingApp.xcodeproj/xcshareddata/xcschemes/ClimbingApp.xcscheme').write_text(scheme)
