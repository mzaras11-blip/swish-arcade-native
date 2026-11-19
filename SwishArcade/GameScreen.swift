import SwiftUI

/// The whole game screen, composed like the ad frames: versus HUD on top,
/// gold-framed board in the middle under the cinematic camera, combo bar
/// and power-ups, chunky rack at the bottom, mascot living on screen.
struct GameScreen: View {
    @EnvironmentObject var vm: GameViewModel
    private let tickTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { _ in
            ZStack {
                EnergyBackground()
                VStack(spacing: 8) {
                    VersusHUD()
                    clueStrip
                    boardSlot
                    ComboBar()
                    powerRow
                    rack
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 10)

                MascotView(mood: vm.phase == .playing && vm.cpuThinking && vm.mascotMood == .idle
                               ? .thinking : vm.mascotMood,
                           size: 74)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 2)
                    .padding(.bottom, 96)
                    .allowsHitTesting(false)

                EffectsLayer()

                if let banner = vm.bannerText {
                    BannerView(text: banner, bolt: vm.bannerBolt)
                }
                if vm.phase == .menu {
                    MenuOverlay()
                } else if vm.phase == .over {
                    GameOverOverlay()
                }
            }
            .coordinateSpace(name: "game")
        }
        .onReceive(tickTimer) { _ in vm.tick() }
    }

    // MARK: Board under the camera

    private var boardSlot: some View {
        Color.clear
            .aspectRatio(CGFloat(PuzzleGenerator.cols) / CGFloat(PuzzleGenerator.rows), contentMode: .fit)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { vm.boardRect = proxy.frame(in: .named("game")) }
                    .onChange(of: proxy.size) { _, _ in vm.boardRect = proxy.frame(in: .named("game")) }
            })
            .overlay {
                BoardView()
                    .scaleEffect(vm.cameraScale, anchor: vm.cameraAnchor)
            }
    }

    // MARK: Clue / live-word strip

    private var clueStrip: some View {
        Group {
            if let live = vm.liveWord {
                HStack(spacing: 8) {
                    Text(live.text)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(TilePalette.bolt)
                    Text(live.clue)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            } else {
                Text(vm.phase == .playing ? "Drag a tile onto the board — chain combos to ×5"
                                          : vm.puzzle.title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(height: 20)
    }

    // MARK: Power-ups

    private var powerRow: some View {
        HStack(spacing: 10) {
            PowerButton(label: "HINT", count: vm.hintsLeft, armed: false) { vm.useHint() }
            PowerButton(label: "BOMB", count: vm.bombsLeft, armed: vm.bombArmed) { vm.armBomb() }
            PowerButton(label: "SHUFFLE", count: vm.shufflesLeft, armed: false) { vm.useShuffle() }
        }
    }

    // MARK: Rack

    private var rack: some View {
        HStack(spacing: 8) {
            ForEach(0..<MatchEngine.rackSize, id: \.self) { slot in
                rackTile(slot: slot)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.72, blue: 0.25),
                                              Color(red: 0.85, green: 0.52, blue: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        )
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { vm.rackRect = proxy.frame(in: .named("game")) }
                .onChange(of: proxy.size) { _, _ in vm.rackRect = proxy.frame(in: .named("game")) }
        })
    }

    @ViewBuilder
    private func rackTile(slot: Int) -> some View {
        let letter = slot < vm.rack.count ? vm.rack[slot] : nil
        let isDragging = vm.drag != nil && vm.drag?.source == .rack(slot)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.18))
            if let letter {
                TileView(letter: letter, size: 52, ghost: isDragging)
                    .scaleEffect(vm.selectedSlot == slot ? 1.1 : 1)
                    .offset(y: vm.selectedSlot == slot ? -6 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .contentShape(Rectangle())
        .onTapGesture { vm.tapRackSlot(slot) }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("game"))
                .onChanged { value in
                    if vm.drag == nil { vm.beginDrag(source: .rack(slot), at: value.location) }
                    else { vm.updateDrag(at: value.location) }
                }
                .onEnded { _ in vm.endDrag() }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: vm.selectedSlot)
    }
}

// MARK: - Versus HUD

struct VersusHUD: View {
    @EnvironmentObject var vm: GameViewModel

    private var leader: Side? {
        let y = vm.scores[.you] ?? 0, c = vm.scores[.cpu] ?? 0
        return y == c ? nil : (y > c ? .you : .cpu)
    }

    var body: some View {
        HStack(spacing: 8) {
            panel(side: .you, name: "PLAYER 1", score: vm.displayedScores[.you] ?? 0,
                  color: TilePalette.brandBlue)
            centerPill
            panel(side: .cpu, name: "PLAYER 2", score: vm.displayedScores[.cpu] ?? 0,
                  color: Color(red: 0.62, green: 0.14, blue: 0.24))
        }
    }

    private func panel(side: Side, name: String, score: Int, color: Color) -> some View {
        let total = max(1, (vm.scores[.you] ?? 0) + (vm.scores[.cpu] ?? 0))
        let frac = Double(vm.scores[side] ?? 0) / Double(total)
        return VStack(spacing: 3) {
            HStack(spacing: 6) {
                AvatarView(isCPU: side == .cpu, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 10.5, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        if leader == side {
                            CrownShape().fill(TilePalette.bolt)
                                .frame(width: 14, height: 11)
                        }
                    }
                    Text("\(score)")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundStyle(TilePalette.bolt)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            Capsule().fill(Color.white.opacity(0.18))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: CGFloat(max(6, 92 * frac)), height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: frac)
                }
            if side == .cpu {
                Text(vm.cpuThinking && vm.phase == .playing ? "CPU is thinking…" : " ")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(height: 11, alignment: .leading)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(color.opacity(0.28))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(color.opacity(0.9), lineWidth: 1.6))
        )
    }

    private var centerPill: some View {
        let secs = Int(ceil(vm.timeLeftMs / 1000))
        let urgent = secs <= 15 && vm.phase == .playing
        return VStack(spacing: 2) {
            Text("VS")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
            Text(String(format: "%d:%02d", secs / 60, secs % 60))
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(urgent ? Color(red: 1, green: 0.4, blue: 0.4) : .white)
            Capsule().fill(Color.white.opacity(0.2))
                .frame(width: 44, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(urgent ? Color(red: 1, green: 0.4, blue: 0.4) : TilePalette.bolt)
                        .frame(width: 44 * CGFloat(vm.timeLeftMs / (MatchEngine.matchSeconds * 1000)), height: 4)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.35)))
        .scaleEffect(urgent ? 1.07 : 1)
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: urgent)
    }
}

// MARK: - Combo bar

struct ComboBar: View {
    @EnvironmentObject var vm: GameViewModel
    @State private var surgeScale = 1.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.35))
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.15),
                                                  Color(red: 1.0, green: 0.25, blue: 0.55),
                                                  Color(red: 0.6, green: 0.3, blue: 1.0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(vm.comboMult > 1 ? vm.comboFrac : 0))
            }
            VStack(spacing: 0) {
                Text("COMBO ×\(vm.comboMult)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(vm.comboMult >= 4 ? Color(red: 1, green: 0.93, blue: 0.55) : .white)
                Text(vm.comboTier)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(1.4)
            }
        }
        .frame(height: 46)
        .scaleEffect(surgeScale)
        .onChange(of: vm.comboSurge) { _, _ in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { surgeScale = 1.06 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.12)) { surgeScale = 1.0 }
        }
    }
}

// MARK: - Power-up button

struct PowerButton: View {
    let label: String
    let count: Int
    let armed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if label == "BOMB" { BoltShape().fill(TilePalette.bolt).frame(width: 11, height: 15) }
                Text(label)
                    .font(.system(size: 14.5, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(count)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.black.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(TilePalette.bolt))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: armed
                        ? [Color(red: 1.0, green: 0.35, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]
                        : [Color(red: 0.30, green: 0.22, blue: 0.62), Color(red: 0.19, green: 0.12, blue: 0.42)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2.5)
            )
            .opacity(count > 0 ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(count <= 0)
    }
}

// MARK: - Banner (DOUBLE WORD SCORE and friends)

struct BannerView: View {
    let text: String
    let bolt: Bool
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            if bolt { BoltShape().fill(TilePalette.bolt).frame(width: 20, height: 28) }
            Text(text)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 2)
            if bolt { BoltShape().fill(TilePalette.bolt).frame(width: 20, height: 28) }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.52, blue: 0.10),
                                              Color(red: 1.0, green: 0.20, blue: 0.42)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TilePalette.bolt, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 5)
        )
        .scaleEffect(shown ? 1 : 0.4)
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) { shown = true }
        }
    }
}

// MARK: - Menu + game over

struct MenuOverlay: View {
    @EnvironmentObject var vm: GameViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text("S.W.I.S.H")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.75, blue: 0.3),
                                                                 Color(red: 1, green: 0.42, blue: 0.25)],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 3)
                    Text("CROSSWORD BATTLE")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(2)
                    Text("ARCADE")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .background(Capsule().fill(TilePalette.bolt))
                        .padding(.top, 6)
                }
                MascotView(mood: .celebrate, size: 118)
                Text("The ad, made real: drag tiles onto the board, chain combos to ×5, and out-race the CPU before the clock runs out.")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Picker("Difficulty", selection: $vm.difficulty) {
                    Text("EASY").tag("easy")
                    Text("NORMAL").tag("normal")
                    Text("HARD").tag("hard")
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button {
                    vm.startMatch()
                } label: {
                    Text("PLAY RUSH")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.52, blue: 0.1),
                                                          Color(red: 1.0, green: 0.22, blue: 0.4)],
                                                 startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }
}

struct GameOverOverlay: View {
    @EnvironmentObject var vm: GameViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(vm.winner == .you ? "YOU WIN!" : vm.winner == .cpu ? "CPU WINS" : "TIE GAME")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(vm.winner == .you ? TilePalette.bolt : .white)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 3)
                MascotView(mood: vm.winner == .you ? .celebrate : .ouch, size: 92)
                HStack(spacing: 26) {
                    finalScore("YOU", vm.scores[.you] ?? 0)
                    finalScore("CPU", vm.scores[.cpu] ?? 0)
                }
                Button { vm.startMatch() } label: {
                    Text("PLAY AGAIN")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 34).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.52, blue: 0.1),
                                                          Color(red: 1.0, green: 0.22, blue: 0.4)],
                                                 startPoint: .top, endPoint: .bottom)))
                }
                .buttonStyle(.plain)
                Button { vm.phase = .menu } label: {
                    Text("MENU")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.13, green: 0.07, blue: 0.30).opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.2)))
            .padding(.horizontal, 30)
        }
    }

    private func finalScore(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Text("\(value)")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
