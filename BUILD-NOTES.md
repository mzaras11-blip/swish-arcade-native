# SWISH ARCADE — native rebuild notes (2026-11-19)

App: **S.W.I.S.H - Crossword Battle ARCADE** · Bundle ID `com.swishgame.arcade` ·
Version 1.1, build 8 · **Native Swift/SwiftUI from the ground up — no web core,
no WKWebView.** Ordered by Michael 2026-11-19: "the ad made real."
Plan + juice spec: `~/workspace/goals/swish-arcade-standalone-game/files/arcade-native-ad-rebuild-plan-2026-11-19.md`

## Build 8 — the build 7 fix pass (2026-11-19, main chat coding, Claude auditing)

Build 7 compiled first try and passed the structural checker 127/0, then
FAILED on Michael's phone: the whole game rendered inside a tiny
letterboxed window with black bars, the board thumbnail-sized, the mascot
parked on the HINT button, the rack spilling off the right edge. Michael's
verdict: "wasn't remotely the same app." His standing recipe from that
moment: **copy the existing web app's screens and layout exactly, rebuild
native underneath, then add the animations and enhance.** Build 8 is that
recipe. Full grade of build 7:
`~/workspace/goals/swish-arcade-standalone-game/files/arcade-native-phase1-grade-2026-11-19.md`
(read its ERRATA too — its Section B was measured against the wrong web
file; the shipped web core is `app/SWISH/Resources/web/index.html`).

What was wrong and what changed:

- **B-2 (the root cause) — no launch screen.** The manual Info.plist had
  no `UILaunchScreen`, so iOS ran the app in legacy letterbox mode on a
  ~320×480 canvas. Fixed: `UILaunchScreen` added, plus
  `CADisableMinimumFrameDurationOnPhone` (120Hz, Spec 2 decision 7).
  ⚠️ iOS caches the letterbox decision per install — verification on
  device requires **delete + reinstall** of the TestFlight build.
- **B-1 — board sizing.** Build 7 had three competing size answers
  (GeometryReader inside an aspect-fit inside an aspect-fit slot) and the
  only flexible row absorbed the whole shortfall. Fixed: one source —
  `GameLayout` in GameScreen computes the cell from the real screen size
  (the smaller of the web's width-driven size and the height the copied
  chrome leaves; a native screen cannot scroll mid-drag) and hands it to
  `BoardView(cell:)`, which never measures itself. The grid is the web's:
  8×12, 3pt gaps, no inner padding, so the drawn board, its frame and
  `boardRect` are the same rectangle (also closes P-A15's grid overflow).
- **Layout — copied, not composed.** GameScreen now follows the shipped
  web app's `#gameScreen` skeleton in order: hud-top (puzzle title +
  chip) → scoreboard (panel | timerbox | panel) → timerbar → status line
  → board → rack (56pt tiles in the ad's gold tray) → tool row
  (HINT / BOMB / SHUFFLE — all three exist in the shipped Rush engine,
  counts 3/2/3). Every row's height comes from the web CSS. The mascot
  lives in a fixed in-layout slot in the combo row — he can no longer
  cover a control or leave the screen (build 7 floated him over HINT at
  96pt from the bottom, exactly where the power row sits, and MascotView
  draws ~1.24× its frame, unclipped). HUD names are the shipped app's:
  YOU / CPU (avatars + crown remain, from the ad).
- **B-3 — right-edge overflow.** The rack's fixed 52pt tiles couldn't
  shrink (min width 312pt > the letterboxed ~292pt offered) and the root
  GeometryReader's proxy was discarded, so the stack sized itself to its
  widest child and spilled right. Fixed by the GameLayout column (screen
  width − 24, max 460, every row a fixed web height) and by the HUD score
  bar filling a fraction of its real track width instead of a hard-coded
  92pt cap.
- **B-5 — hit-testing through the camera.** Touches are inverse-mapped
  through the camera transform before grid math; effect spawn points are
  forward-mapped, so floaters land on the board the player sees. Two
  audit catches by Claude, fixed by main: the drag-focus anchor was being
  computed in visual space (`cellCenter`) instead of unscaled space
  (`cellCenterUnscaled`) — under the post-placement zoom that slid the
  board over a cell on the one drag engagement; and `cellSize` disagreed
  with hit-test geometry by the gap total (now returns `cellExtent`).
  Accepted residual (Spec 2 decision 4's own terms): hit-testing uses the
  camera's model values, so during a ~0.35s spring the mapping is
  sub-cell off and converges at rest.
- **B-6 — camera discipline.** The drag zoom engages ONCE per drag (first
  droppable hover cell), instantly rather than sprung — while a spring
  runs, hit-testing maps through the target transform but the board is
  drawn mid-flight, off by up to 0.3 × distance-from-anchor (Claude
  audit catch); an instant set anchored on the hovered cell keeps that
  cell exactly under the finger. Build 7 re-anchored on every hover
  change. `cameraWordFocus`/`cameraPunch` refuse to move the camera while
  a drag is active; drags are source-scoped in the views and taps are
  inert mid-drag, so a second finger can neither move, drop, nor
  tap-place around the lifted tile; `beginDrag` refuses re-entry except
  for a provably stale drag.
- **B-7 — gesture cancellation.** `cancelDrag()` was called nowhere in
  build 7. GameScreen now cancels the drag whenever the scene leaves
  `.active` (call, Control Center, app switch).
- Banner clear task is generation-keyed (a stale task can no longer
  clear a newer banner with the same text).
- Checker: **129 passed, 0 failed** — now also pins build 8 in all three
  places (plist, both pbxproj configs) and asserts `UILaunchScreen` and
  the 120Hz key so B-2/P-A13 cannot silently return.
- Claude audit rounds: `claude-fix-round-1-2026-11-19.md` and
  `claude-fix-round-2-2026-11-19.md` in the goal files folder.

Known deltas from the web app, deliberate: the native board is
height-capped (on an iPhone 16 Pro ≈305pt wide vs the web's ≈378pt)
because the web page may scroll and a native drag screen may not; the
camera zoom during drags restores the effective cell size. The 27 polish
gaps from the grade (drop handoff pop, floater flight to the HUD,
particles as SwiftUI views, per-frame invalidation) are phase 1.5 work,
not this pass.

## What phase 1 contains (unchanged from build 7)
- `PuzzleGenerator.swift` — faithful port of Michael's crossword generator
  (greedy fill + iterated local search + quality gates), 8×12 board, 3 blue
  bonus squares. Word bank: the same 846 word/clue pairs as `Resources/words.json`.
- `MatchEngine.swift` — faithful port of the shipped ARCADE Rush engine:
  180 s race vs CPU on a shared board, letter 10 × combo, word bonus
  5 × length × combo, combo window 5 s / cap ×5, wrong letter breaks combo,
  dead-rack guarantee, HINT ×3 / BOMB ×2 / SHUFFLE ×3, CPU pace+accuracy
  difficulties (the pace IS the "CPU is thinking" beat — instant CPU turns
  stay rejected); a word covering a bonus square doubles its word bonus
  (the DOUBLE WORD SCORE moment); pick-back-up of your just-set tile
  inside a 2.5 s grace window while it is the newest placement.
- Juice (the ad, implemented): finger-drag placement as the PRIMARY input
  (lift + grow + shadow, spring-lag follow, target highlight, live word
  readout, snap-in pop + haptic on set, spring-back on reject, pick back
  up); cinematic camera (drag focus, word focus, punch-in on scoring
  moments and banners, win pose — transform-only, springs, interruptible);
  score floaters; combo bar with surge; particle bursts; win confetti
  rain with coins/stars; DOUBLE WORD SCORE banner; shape-drawn mascot
  with idle/celebrate/big-play/ouch/thinking moods; versus HUD with
  avatars, leader crown, score bars; synthesized SFX; haptics.
- Icon: the current shipping ARCADE icon, byte-identical (md5 bd81ed87…).
- `tools/gen_pbxproj.py` regenerates the project deterministically;
  `tools/check_project.py` is the structural gate (PDF Viewer pattern).

## NOT done (later phases, per plan)
- AdMob + Remove Ads IAP parity (ARCADE's real IDs are on file).
- Turn-based Battle mode; online / friends / split-screen (Firebase) port.
- Nothing in App Store Connect touched by the build itself; the web
  line's 1.0 build 5 in review is undisturbed.

## Verification
- `tools/check_project.py`: 129 passed, 0 failed (build 8 tree).
- Compilation: Codemagic is the first compile check (no Xcode on the VM).
- On-screen rendering: Michael's TestFlight play is the visual gate —
  and per the B-2 note, he must delete + reinstall for the letterbox
  fix to take effect.
- Michael's fallback ruling (2026-11-19): if build 8 doesn't work out on
  his play test, native development stops and ARCADE continues on the
  web-core line.
