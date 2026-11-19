#!/usr/bin/env python3
"""Structural verification for the SwishArcade (native ARCADE) project.

There is no Xcode / Swift toolchain on this VM, so this checks everything
that can be checked statically, in the PDF Viewer checker pattern:

  1. Info.plist + PrivacyInfo.xcprivacy parse and carry the expected keys.
  2. Asset catalogs parse; the app icon is exactly 1024x1024, RGB, no
     alpha, and byte-identical to the current shipping ARCADE icon.
  3. project.pbxproj: every object ID referenced is defined; every file
     reference resolves to a file on disk; Swift files on disk ==
     referenced == Sources phase; Resources phase complete; bundle ID,
     deployment target, version/build in both configurations.
  4. The shared scheme points at the project's target.
  5. Swift sources: balanced delimiters, no TODO/FIXME, NO WebKit /
     WKWebView anywhere (the native-only guarantee), no emoji art.
  6. The "ad made real" spec is actually in the code: drag placement,
     camera layer, combo/Rush constants, DOUBLE WORD SCORE doubling,
     pick-back-up, CPU thinking beat, mascot moods, confetti, haptics.
  7. words.json: the full 846-entry bank, well-formed.

Exit code 0 = all checks passed.
"""
import hashlib
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent
SRC_DIR = APP_DIR / "SwishArcade"
PBXPROJ = APP_DIR / "SwishArcade.xcodeproj" / "project.pbxproj"
SCHEME = APP_DIR / "SwishArcade.xcodeproj" / "xcshareddata" / "xcschemes" / "SwishArcade.xcscheme"

failures = []
passes = 0


def check(ok, label, detail=""):
    global passes
    if ok:
        passes += 1
        print(f"  PASS  {label}")
    else:
        failures.append(label)
        print(f"  FAIL  {label}  {detail}")


print("== Plists ==")
with open(SRC_DIR / "Info.plist", "rb") as f:
    info = plistlib.load(f)
check(info.get("CFBundleDisplayName") == "S.W.I.S.H - Crossword Battle ARCADE", "Info.plist display name")
check(info.get("CFBundleShortVersionString") == "1.1", "version is 1.1")
check(info.get("CFBundleVersion") == "8", "build is 8")
check("UILaunchScreen" in info, "UILaunchScreen present (no letterbox mode)")
check(info.get("CADisableMinimumFrameDurationOnPhone") is True,
      "120Hz ProMotion enabled")
check(info.get("ITSAppUsesNonExemptEncryption") is False, "ITSAppUsesNonExemptEncryption = false")
check(info.get("UISupportedInterfaceOrientations") == ["UIInterfaceOrientationPortrait"],
      "portrait only (the ad's frame)")

with open(SRC_DIR / "PrivacyInfo.xcprivacy", "rb") as f:
    privacy = plistlib.load(f)
check(isinstance(privacy, dict) and "NSPrivacyAccessedAPITypes" in privacy,
      "PrivacyInfo.xcprivacy parses with accessed-API section")

print("== Asset catalogs & icon ==")
for rel in ["Assets.xcassets/Contents.json",
            "Assets.xcassets/AppIcon.appiconset/Contents.json",
            "Assets.xcassets/AccentColor.colorset/Contents.json"]:
    try:
        json.loads((SRC_DIR / rel).read_text())
        check(True, f"{rel} is valid JSON")
    except Exception as exc:  # noqa: BLE001
        check(False, f"{rel} is valid JSON", str(exc))

from PIL import Image  # noqa: E402

icon_path = SRC_DIR / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
icon = Image.open(icon_path)
check(icon.size == (1024, 1024), "icon is 1024x1024", f"got {icon.size}")
check(icon.mode == "RGB", "icon is RGB with no alpha", f"mode={icon.mode}")
icon_md5 = hashlib.md5(icon_path.read_bytes()).hexdigest()
check(icon_md5 == "bd81ed87045c4fd8511d66c7eb99bce8",
      "icon is byte-identical to the current shipping ARCADE icon", f"md5={icon_md5}")

print("== project.pbxproj ==")
pbx = PBXPROJ.read_text()
id_re = re.compile(r"\b[0-9A-F]{24}\b")
defined = set(re.findall(r"^\t\t([0-9A-F]{24}) /\* [^*]+ \*/ = \{", pbx, flags=re.M))
referenced = set(id_re.findall(pbx))
check(referenced <= defined, "every referenced object ID is defined",
      f"missing: {sorted(referenced - defined)}")
root = re.search(r"rootObject = ([0-9A-F]{24})", pbx)
check(bool(root) and root.group(1) in defined, "rootObject resolves")

fileref_re = re.compile(
    r"([0-9A-F]{24}) /\* ([^*]+) \*/ = \{isa = PBXFileReference; [^}]*?"
    r"path = (\"[^\"]+\"|[^;]+); sourceTree = (\"[^\"]+\"|[^;]+); \};")
missing_files = []
ref_paths = {}
for fid, _name, raw_path, raw_tree in fileref_re.findall(pbx):
    path = raw_path.strip().strip('"')
    tree = raw_tree.strip().strip('"')
    ref_paths[fid] = path
    if tree == "BUILT_PRODUCTS_DIR":
        continue
    resolved = SRC_DIR / path
    if not resolved.exists():
        missing_files.append(f"{path} -> {resolved}")
check(not missing_files, "every file reference exists on disk", "; ".join(missing_files))

swift_on_disk = sorted(p.name for p in SRC_DIR.glob("*.swift"))
swift_referenced = sorted(p for p in ref_paths.values() if p.endswith(".swift"))
check(swift_on_disk == swift_referenced, "Swift files on disk == Swift files referenced",
      f"disk={swift_on_disk} refs={swift_referenced}")

sources_block = re.search(r"isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);", pbx, flags=re.S)
buildfile_to_ref = dict(re.findall(
    r"([0-9A-F]{24}) /\* [^*]+ in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})", pbx))
in_sources = sorted(ref_paths[buildfile_to_ref[bid]]
                    for bid in re.findall(r"([0-9A-F]{24}) /\*", sources_block.group(1))
                    if bid in buildfile_to_ref)
check(in_sources == swift_on_disk, "Sources phase contains exactly the Swift files on disk",
      f"sources={in_sources}")

resources_block = re.search(r"isa = PBXResourcesBuildPhase;.*?files = \((.*?)\);", pbx, flags=re.S)
res_to_ref = dict(re.findall(
    r"([0-9A-F]{24}) /\* [^*]+ in Resources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})", pbx))
in_resources = sorted(ref_paths[res_to_ref[bid]]
                      for bid in re.findall(r"([0-9A-F]{24}) /\*", resources_block.group(1))
                      if bid in res_to_ref)
check(in_resources == ["Assets.xcassets", "PrivacyInfo.xcprivacy", "Resources/words.json"],
      "Resources phase = asset catalog + privacy + words.json", f"resources={in_resources}")

check(pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.swishgame.arcade;") == 2,
      "bundle ID com.swishgame.arcade in Debug+Release")
check(pbx.count("IPHONEOS_DEPLOYMENT_TARGET = 17.0;") == 2,
      "deployment target 17.0 in Debug+Release")
check(pbx.count("INFOPLIST_FILE = SwishArcade/Info.plist;") == 2,
      "INFOPLIST_FILE path in Debug+Release")
check(pbx.count("CURRENT_PROJECT_VERSION = 8;") == 2,
      "CURRENT_PROJECT_VERSION = 8 in Debug+Release")
check(pbx.count("MARKETING_VERSION = 1.1;") == 2,
      "MARKETING_VERSION = 1.1 in Debug+Release")

print("== Scheme ==")
scheme_root = ET.parse(SCHEME).getroot()
refs = scheme_root.findall(".//BuildableReference")
target_match = re.search(r"([0-9A-F]{24}) /\* SwishArcade \*/ = \{\s*isa = PBXNativeTarget;", pbx)
check(len(refs) >= 1 and all(r.get("BlueprintIdentifier") == target_match.group(1) for r in refs),
      "scheme BlueprintIdentifier == PBXNativeTarget id")
check(all(r.get("BuildableName") == "SwishArcade.app" for r in refs), "scheme builds SwishArcade.app")

print("== Swift sources ==")


def strip_comments_and_strings(text: str) -> str:
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j == -1 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j == -1 else j + 2
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            i = n if j == -1 else j + 3
            out.append('""')
        elif text[i] == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            i = j + 1
            out.append('""')
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


EMOJI_RANGES = [(0x1F000, 0x1FAFF), (0x2600, 0x27BF), (0x2B00, 0x2BFF), (0x1F1E6, 0x1F1FF)]

swift_texts = {}
for name in swift_on_disk:
    raw = (SRC_DIR / name).read_text()
    swift_texts[name] = raw
    stripped = strip_comments_and_strings(raw)
    balance_ok = all(stripped.count(a) == stripped.count(b)
                     for a, b in [("(", ")"), ("{", "}"), ("[", "]")])
    check(balance_ok, f"{name}: balanced delimiters")
    check("TODO" not in raw and "FIXME" not in raw, f"{name}: no TODO/FIXME leftovers")
    check("WebKit" not in raw and "WKWebView" not in raw and "webView" not in raw,
          f"{name}: no web view (native-only guarantee)")
    emoji_hits = [ch for ch in raw if any(lo <= ord(ch) <= hi for lo, hi in EMOJI_RANGES)]
    check(not emoji_hits, f"{name}: no emoji art", f"found {emoji_hits[:5]}")

# Cross-file type references.
definitions = {
    "GameViewModel": "GameViewModel.swift",
    "MatchEngine": "MatchEngine.swift",
    "PuzzleGenerator": "PuzzleGenerator.swift",
    "WordBank": "WordBank.swift",
    "SoundFX": "SoundFX.swift",
    "MascotView": "MascotView.swift",
    "TileView": "Tiles.swift",
    "BoardView": "BoardView.swift",
    "GameScreen": "GameScreen.swift",
    "EffectsLayer": "EffectsView.swift",
}
for type_name, defining_file in definitions.items():
    pattern = rf"(?:final class|class|struct|enum)\s+{type_name}\b"
    check(re.search(pattern, swift_texts[defining_file]) is not None,
          f"{type_name} is defined in {defining_file}")

uses = [
    ("GameViewModel", "SwishArcadeApp.swift"), ("GameViewModel", "GameScreen.swift"),
    ("GameScreen", "SwishArcadeApp.swift"),
    ("MatchEngine", "GameViewModel.swift"), ("PuzzleGenerator", "GameViewModel.swift"),
    ("PuzzleGenerator", "BoardView.swift"), ("PuzzleGenerator", "MatchEngine.swift"),
    ("WordBank", "PuzzleGenerator.swift"), ("WordBank", "MatchEngine.swift"),
    ("TileView", "BoardView.swift"), ("TileView", "GameScreen.swift"), ("TileView", "EffectsView.swift"),
    ("MascotView", "GameScreen.swift"), ("EffectsLayer", "GameScreen.swift"),
    ("SoundFX", "GameViewModel.swift"), ("Haptics", "GameViewModel.swift"),
    ("BoardView", "GameScreen.swift"),
]
for type_name, using_file in uses:
    check(re.search(rf"\b{type_name}\b", swift_texts[using_file]) is not None,
          f"{type_name} is referenced in {using_file}")

check("@main" in swift_texts["SwishArcadeApp.swift"], "SwishArcadeApp carries @main")

print("== The ad, implemented (spec checks) ==")
eng = swift_texts["MatchEngine.swift"]
vm = swift_texts["GameViewModel.swift"]
screen = swift_texts["GameScreen.swift"]
board = swift_texts["BoardView.swift"]

check("matchSeconds = 180" in eng, "Rush is a 180-second race")
check("comboMax = 5" in eng and "comboWindowMs = 5000" in eng, "combo cap ×5, 5s chain window")
check("letterPoints = 10" in eng and "wordBonusPerLetter = 5" in eng, "Rush scoring constants (10/letter, 5/letter word bonus)")
check("bonus *= 2" in eng and "isBonus" in eng, "bonus square doubles the word bonus")
check("func pickupLastPlacement" in eng and "pickupLastPlacement" in vm, "pick-back-up implemented in engine + view model")
check("func useHint" in eng and "func useBomb" in eng and "func useShuffle" in eng,
      "HINT / BOMB / SHUFFLE all in the engine")
check("cpuIsThinking" in eng and "CPU is thinking" in screen, "CPU thinking beat present (paced CPU + HUD label)")
check("paceMin: 3000" in eng and "paceMin: 1600" in eng, "CPU difficulty pace table ported")
check("ensurePlayable" in eng, "dead-rack guarantee ported")

check("DragGesture" in screen and "DragGesture" in board, "drag gestures on rack + board (pickup)")
check("func beginDrag" in vm and "func endDrag" in vm and "ReturningTile" in vm,
      "drag lifecycle + spring-back returning tile")
check("liveWord" in vm and "liveWordCells" in board, "live word readout + board glow while dragging")
check("cameraScale" in vm and "cameraPunch" in vm and "cameraDragFocus" in vm
      and "cameraWordFocus" in vm, "camera director: drag focus, word focus, punch")
check("scaleEffect(vm.cameraScale, anchor: vm.cameraAnchor)" in screen,
      "board sits under the camera transform")
check("DOUBLE WORD SCORE" in vm, "DOUBLE WORD SCORE banner wired")
check("COMBO MASTER" in vm and "comboSurge" in vm, "combo surge + ×5 banner")
check("ConfettiRainView" in swift_texts["EffectsView.swift"] and "confettiRain" in vm,
      "win confetti rain")
check("ScoreFloater" in vm and "ParticleBurst" in vm, "score floaters + particle bursts")
check("enum MascotMood" in vm and "case bigPlay" in vm and "MascotMood" in swift_texts["MascotView.swift"],
      "mascot moods incl. big-play")
check("func tileSet" in swift_texts["Haptics.swift"] and "Haptics.tileSet()" in vm,
      "set-tile haptic pulse wired")
check("class SoundFX" in swift_texts["SoundFX.swift"] and "AVAudioEngine" in swift_texts["SoundFX.swift"],
      "synthesized SFX (no audio assets)")
check("0.12, green: 0.61" in swift_texts["Tiles.swift"] or "0.12, green: 0.61" in swift_texts["MascotView.swift"],
      "brand blue #1E9BFF in the palette/mascot")
check("247.0 / 255, green: 195.0 / 255" in swift_texts["Tiles.swift"], "bolt color (247,195,22) exact")

print("== Word bank ==")
words = json.loads((SRC_DIR / "Resources" / "words.json").read_text())
check(len(words) == 846, "words.json carries the full 846-entry bank", f"got {len(words)}")
check(all(set(e.keys()) == {"w", "c"} and e["w"].isalpha() and e["w"].isupper() and e["c"]
          for e in words), "every entry is {w: UPPER WORD, c: clue}")
lengths = {n: sum(1 for e in words if len(e["w"]) == n) for n in range(3, 9)}
check(all(lengths[n] > 20 for n in range(3, 9)), "all lengths 3-8 well stocked for the generator",
      f"{lengths}")

print()
print(f"{passes} passed, {len(failures)} failed")
if failures:
    print("FAILURES:")
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)
print("ALL CHECKS PASSED")
