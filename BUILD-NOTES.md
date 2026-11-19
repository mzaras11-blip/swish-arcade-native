# SWISH ARCADE — native rebuild notes (2026-11-19)

App: **S.W.I.S.H - Crossword Battle ARCADE** · Bundle ID `com.swishgame.arcade` ·
Version 1.1, build 7 · **Native Swift/SwiftUI from the ground up — no web core,
no WKWebView.** Ordered by Michael 2026-11-19: "the ad made real."
Plan + juice spec: `~/workspace/goals/swish-arcade-standalone-game/files/arcade-native-ad-rebuild-plan-2026-11-19.md`

## What phase 1 contains
- `PuzzleGenerator.swift` — faithful port of Michael's crossword generator
  (greedy fill + iterated local search + quality gates), 8×12 board, 3 blue
  bonus squares. Word bank: the same 846 word/clue pairs as `Resources/words.json`.
- `MatchEngine.swift` — faithful port of the shipped ARCADE Rush engine:
  180 s race vs CPU on a shared board, letter 10 × combo, word bonus
  5 × length × combo, combo window 5 s / cap ×5, wrong letter breaks combo,
  dead-rack guarantee, HINT ×3 / BOMB ×2, CPU pace+accuracy difficulties
  (the pace IS the "CPU is thinking" beat — instant CPU turns stay rejected).
  Native additions: SHUFFLE ×3; a word covering a bonus square doubles its
  word bonus (the DOUBLE WORD SCORE moment); pick-back-up of your just-set
  tile inside a 2.5 s grace window while it is the newest placement.
- Juice (the ad, implemented): finger-drag placement as the PRIMARY input
  (lift + grow + shadow, spring-lag follow, target highlight, live word
  readout, snap-in pop + haptic on set, spring-back on reject, pick back up);
  cinematic camera (drag focus, word focus, punch-in on scoring moments and
  banners, win pose — transform-only, springs, interruptible); score floaters
  flying to the HUD with count-up scores; combo bar with surge; particle
  bursts; win confetti rain with coins/stars; DOUBLE WORD SCORE banner;
  shape-drawn mascot with idle/celebrate/big-play/ouch/thinking moods;
  versus HUD with avatars, leader crown, score bars, "CPU is thinking…";
  synthesized SFX (no audio assets); haptics.
- Icon: the current shipping ARCADE icon, byte-identical (md5 bd81ed87…).
- `tools/gen_pbxproj.py` regenerates the project deterministically;
  `tools/check_project.py` is the structural gate (PDF Viewer pattern).

## NOT done (later phases, per plan)
- GitHub push + Codemagic wiring (stopped on purpose — main chat wires it).
- AdMob + Remove Ads IAP parity (ARCADE's real IDs are on file).
- Turn-based Battle mode; online / friends / split-screen (Firebase) port.
- Nothing in App Store Connect touched; web build 5 In Review undisturbed.

## Verification
- `tools/check_project.py`: see the run in the phase-1 report.
- NOT verified: native compilation (no Xcode on this VM — the Codemagic
  unsigned workflow is the first compile check) and on-screen rendering
  (Michael's TestFlight play is the visual gate).
