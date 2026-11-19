#!/usr/bin/env python3
"""Generate SwishArcade.xcodeproj/project.pbxproj (+ shared scheme) with
deterministic UUIDs. Same pattern as the S.W.I.S.H / PDF Viewer projects:
md5-derived 24-hex object IDs registered by (kind, name), so regeneration
is stable and the checker can verify referential integrity."""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_NAME = "SwishArcade"
BUNDLE_ID = "com.swishgame.arcade"
SWIFT_FILES = ["SwishArcadeApp.swift", "WordBank.swift", "PuzzleGenerator.swift",
               "MatchEngine.swift", "GameViewModel.swift", "SoundFX.swift",
               "Haptics.swift", "Tiles.swift", "BoardView.swift",
               "MascotView.swift", "EffectsView.swift", "GameScreen.swift"]
RESOURCE_FILES = ["Assets.xcassets", "words.json", "PrivacyInfo.xcprivacy"]

P = {}


def uid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def reg(kind, name):
    key = f"{kind}:{name}"
    if key not in P:
        P[key] = uid(key)
    return P[key]


lines = []
A = lines.append

A("// !$*UTF8*$!")
A("{")
A("\tarchiveVersion = 1;")
A("\tclasses = {")
A("\t};")
A("\tobjectVersion = 56;")
A("\tobjects = {")

# ---------- PBXBuildFile ----------
for f in SWIFT_FILES:
    A(f"\t\t{reg('build', f)} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {reg('file', f)} /* {f} */; }};")
for f in RESOURCE_FILES:
    A(f"\t\t{reg('build', f)} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {reg('file', f)} /* {f} */; }};")

# ---------- PBXFileReference ----------
A(f"\t\t{reg('file', APP_NAME + '.app')} /* {APP_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for f in SWIFT_FILES:
    A(f"\t\t{reg('file', f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};")
A(f"\t\t{reg('file', 'Info.plist')} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
A(f"\t\t{reg('file', 'Assets.xcassets')} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
A(f"\t\t{reg('file', 'words.json')} /* words.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = Resources/words.json; sourceTree = \"<group>\"; }};")
A(f"\t\t{reg('file', 'PrivacyInfo.xcprivacy')} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = PrivacyInfo.xcprivacy; sourceTree = \"<group>\"; }};")

# ---------- PBXFrameworksBuildPhase ----------
A(f"\t\t{reg('phase', 'frameworks')} /* Frameworks */ = {{")
A("\t\t\tisa = PBXFrameworksBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")

# ---------- PBXGroup ----------
A(f"\t\t{reg('group', 'main')} /* Main group */ = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
A(f"\t\t\t\t{reg('group', APP_NAME)} /* {APP_NAME} */,")
A(f"\t\t\t\t{reg('group', 'Products')} /* Products */,")
A("\t\t\t);")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")
A(f"\t\t{reg('group', 'Products')} /* Products */ = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
A(f"\t\t\t\t{reg('file', APP_NAME + '.app')} /* {APP_NAME}.app */,")
A("\t\t\t);")
A(f"\t\t\tname = Products;")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")
A(f"\t\t{reg('group', APP_NAME)} /* {APP_NAME} */ = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
for f in SWIFT_FILES:
    A(f"\t\t\t\t{reg('file', f)} /* {f} */,")
A(f"\t\t\t\t{reg('file', 'Assets.xcassets')} /* Assets.xcassets */,")
A(f"\t\t\t\t{reg('file', 'words.json')} /* words.json */,")
A(f"\t\t\t\t{reg('file', 'PrivacyInfo.xcprivacy')} /* PrivacyInfo.xcprivacy */,")
A(f"\t\t\t\t{reg('file', 'Info.plist')} /* Info.plist */,")
A("\t\t\t);")
A(f"\t\t\tpath = {APP_NAME};")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")

# ---------- PBXNativeTarget ----------
A(f"\t\t{reg('target', APP_NAME)} /* {APP_NAME} */ = {{")
A("\t\t\tisa = PBXNativeTarget;")
A(f"\t\t\tbuildConfigurationList = {reg('list', 'target')} /* Build configuration list for PBXNativeTarget \"{APP_NAME}\" */;")
A("\t\t\tbuildPhases = (")
A(f"\t\t\t\t{reg('phase', 'sources')} /* Sources */,")
A(f"\t\t\t\t{reg('phase', 'frameworks')} /* Frameworks */,")
A(f"\t\t\t\t{reg('phase', 'resources')} /* Resources */,")
A("\t\t\t);")
A("\t\t\tbuildRules = (")
A("\t\t\t);")
A("\t\t\tdependencies = (")
A("\t\t\t);")
A(f"\t\t\tname = {APP_NAME};")
A(f"\t\t\tproductName = {APP_NAME};")
A(f"\t\t\tproductReference = {reg('file', APP_NAME + '.app')} /* {APP_NAME}.app */;")
A("\t\t\tproductType = \"com.apple.product-type.application\";")
A("\t\t};")

# ---------- PBXProject ----------
A(f"\t\t{reg('project', 'root')} /* Project object */ = {{")
A("\t\t\tisa = PBXProject;")
A("\t\t\tattributes = {")
A("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
A("\t\t\t\tLastSwiftUpdateCheck = 1600;")
A("\t\t\t\tLastUpgradeCheck = 1600;")
A("\t\t\t};")
A(f"\t\t\tbuildConfigurationList = {reg('list', 'project')} /* Build configuration list for PBXProject */;")
A("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
A("\t\t\tdevelopmentRegion = en;")
A("\t\t\thasScannedForEncodings = 0;")
A("\t\t\tknownRegions = (en);")
A(f"\t\t\tmainGroup = {reg('group', 'main')};")
A(f"\t\t\tproductRefGroup = {reg('group', 'Products')} /* Products */;")
A("\t\t\tprojectDirPath = \"\";")
A("\t\t\tprojectRoot = \"\";")
A("\t\t\ttargets = (")
A(f"\t\t\t\t{reg('target', APP_NAME)} /* {APP_NAME} */,")
A("\t\t\t);")
A("\t\t};")

# ---------- PBXResourcesBuildPhase ----------
A(f"\t\t{reg('phase', 'resources')} /* Resources */ = {{")
A("\t\t\tisa = PBXResourcesBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
for f in RESOURCE_FILES:
    A(f"\t\t\t\t{reg('build', f)} /* {f} in Resources */,")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")

# ---------- PBXSourcesBuildPhase ----------
A(f"\t\t{reg('phase', 'sources')} /* Sources */ = {{")
A("\t\t\tisa = PBXSourcesBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
for f in SWIFT_FILES:
    A(f"\t\t\t\t{reg('build', f)} /* {f} in Sources */,")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")

# ---------- XCBuildConfiguration ----------
PROJECT_SETTINGS = {
    "Debug": [("ALWAYS_SEARCH_USER_PATHS", "NO"), ("CLANG_ANALYZER_NONNULL", "YES"),
              ("CLANG_CXX_LANGUAGE_STANDARD", "\"gnu++20\""), ("COPY_PHASE_STRIP", "NO"),
              ("DEBUG_INFORMATION_FORMAT", "dwarf"), ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
              ("GCC_C_LANGUAGE_STANDARD", "gnu17"), ("MTL_ENABLE_DEBUG_INFO", "INCLUDE_SOURCE"),
              ("MTL_FAST_MATH", "YES"), ("ONLY_ACTIVE_ARCH", "YES"), ("SDKROOT", "iphoneos")],
    "Release": [("ALWAYS_SEARCH_USER_PATHS", "NO"), ("CLANG_ANALYZER_NONNULL", "YES"),
                ("CLANG_CXX_LANGUAGE_STANDARD", "\"gnu++20\""), ("COPY_PHASE_STRIP", "NO"),
                ("DEBUG_INFORMATION_FORMAT", "\"dwarf-with-dsym\""), ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
                ("GCC_C_LANGUAGE_STANDARD", "gnu17"), ("MTL_FAST_MATH", "YES"),
                ("SDKROOT", "iphoneos"), ("VALIDATE_PRODUCT", "YES")],
}
TARGET_SETTINGS = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "8"),
    ("DEVELOPMENT_TEAM", "\"\""),
    ("INFOPLIST_FILE", f"{APP_NAME}/Info.plist"),
    ("INFOPLIST_KEY_UIApplicationSceneManifest_Generation", "YES"),
    ("INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents", "YES"),
    ("INFOPLIST_KEY_UILaunchScreen_Generation", "YES"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "17.0"),
    ("LD_RUNPATH_SEARCH_PATHS", "\"$(inherited) @executable_path/Frameworks\""),
    ("MARKETING_VERSION", "1.1"),
    ("PRODUCT_BUNDLE_IDENTIFIER", BUNDLE_ID),
    ("PRODUCT_NAME", "\"$(TARGET_NAME)\""),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
    ("SWIFT_VERSION", "5.0"),
    ("TARGETED_DEVICE_FAMILY", "\"1\""),
]


def config_block(cid, name, settings):
    A(f"\t\t{cid} /* {name} */ = {{")
    A("\t\t\tisa = XCBuildConfiguration;")
    A("\t\t\tbuildSettings = {")
    for k, v in settings:
        A(f"\t\t\t\t{k} = {v};")
    A("\t\t\t};")
    A(f"\t\t\tname = {name};")
    A("\t\t};")


config_block(reg("config", "project-Debug"), "Debug", PROJECT_SETTINGS["Debug"])
config_block(reg("config", "project-Release"), "Release", PROJECT_SETTINGS["Release"])
config_block(reg("config", "target-Debug"), "Debug", TARGET_SETTINGS)
config_block(reg("config", "target-Release"), "Release", TARGET_SETTINGS)

# ---------- XCConfigurationList ----------
for lst, cfgs in [("project", ["project-Debug", "project-Release"]),
                  ("target", ["target-Debug", "target-Release"])]:
    owner = "PBXProject" if lst == "project" else f"PBXNativeTarget \"{APP_NAME}\""
    A(f"\t\t{reg('list', lst)} /* Build configuration list for {owner} */ = {{")
    A("\t\t\tisa = XCConfigurationList;")
    A("\t\t\tbuildConfigurations = (")
    for c in cfgs:
        A(f"\t\t\t\t{reg('config', c)} /* {'Debug' if c.endswith('Debug') else 'Release'} */,")
    A("\t\t\t);")
    A("\t\t\tdefaultConfigurationIsVisible = 0;")
    A("\t\t\tdefaultConfigurationName = Release;")
    A("\t\t};")

A("\t};")
A(f"\trootObject = {reg('project', 'root')} /* Project object */;")
A("}")

proj_dir = os.path.join(ROOT, f"{APP_NAME}.xcodeproj")
os.makedirs(os.path.join(proj_dir, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as fh:
    fh.write("\n".join(lines) + "\n")

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{reg('target', APP_NAME)}"
               BuildableName = "{APP_NAME}.app"
               BlueprintName = "{APP_NAME}"
               ReferencedContainer = "container:{APP_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{reg('target', APP_NAME)}"
            BuildableName = "{APP_NAME}.app"
            BlueprintName = "{APP_NAME}"
            ReferencedContainer = "container:{APP_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{reg('target', APP_NAME)}"
            BuildableName = "{APP_NAME}.app"
            BlueprintName = "{APP_NAME}"
            ReferencedContainer = "container:{APP_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
with open(os.path.join(proj_dir, "xcshareddata", "xcschemes", f"{APP_NAME}.xcscheme"), "w") as fh:
    fh.write(scheme)

print(f"wrote {APP_NAME}.xcodeproj/project.pbxproj + {APP_NAME}.xcscheme")
print(f"target id: {reg('target', APP_NAME)}")
