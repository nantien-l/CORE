import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum PuzzlePalette {
    static let background = Color(red: 0.043, green: 0.048, blue: 0.050)
    static let panel = Color(red: 0.067, green: 0.074, blue: 0.075)
    static let stone = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let muted = Color(red: 0.65, green: 0.67, blue: 0.64)
    static let accent = Color(red: 0.77, green: 0.91, blue: 0.68)
    static let warning = Color(red: 1, green: 0.64, blue: 0.47)
    static let start = Color(red: 0.64, green: 0.88, blue: 1)
    static let goal = Color(red: 1, green: 0.79, blue: 0.39)
    static let stair = Color(red: 0.70, green: 0.62, blue: 0.98)
    static let border = Color.white.opacity(0.11)
}

struct PuzzleView: View {
    private let levels = LevelCatalog.levels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("core.highestClearedLevel") private var highestCleared = 0
    @State private var restored = false
    @State private var earnedForm: CoreForm?
    @State private var levelIndex = 0
    @State private var engine = PuzzleEngine(level: LevelCatalog.levels[0])
    @State private var run = 0
    @State private var cameraReset = 0
    @State private var expanded = false
    @State private var showMap = false
    @State private var pausedAt: ContinuousClock.Instant?
    @State private var mapSelection: Int?

    private var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private var fallen: Bool { engine.status == .fallen }
    private var warned: Bool { engine.status == .danger }
    private var won: Bool { engine.status == .won }
    private var form: CoreForm { .unlocked(after: highestCleared) }
    private var lastLevel: Bool { levelIndex == levels.count - 1 }

    var body: some View {
        GeometryReader { geometry in
            let tabletLayout = isPad && geometry.size.width >= 700 && !typeSize.isAccessibilitySize
            let wide = geometry.size.width >= 650 && !typeSize.isAccessibilitySize
                && (geometry.size.height < 580 || (tabletLayout && geometry.size.width > geometry.size.height))
            let boardHeight = expanded ? geometry.size.height : (
                wide ? max(240, geometry.size.height - 40) : (
                    tabletLayout ? max(460, geometry.size.height - (engine.isFinished ? 370 : 310)) : min(560, max(268, geometry.size.height * 0.51))
                )
            )
            ScrollView {
                PuzzleBoardLayout(wide: wide, expanded: expanded, boardHeight: boardHeight,
                                  spacing: wide ? 24 : (tabletLayout ? 16 : 22)) {
                    header.opacity(expanded ? 0 : 1).accessibilityHidden(expanded)
                    levelHeading.opacity(expanded ? 0 : 1).accessibilityHidden(expanded)
                    controls.opacity(expanded ? 0 : 1).accessibilityHidden(expanded)
                    board
                }
                .frame(maxWidth: expanded || tabletLayout ? .infinity : 880)
                .padding(.horizontal, expanded ? 0 : (wide ? 28 : 20))
                .padding(.vertical, expanded ? 0 : 20)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(expanded || (tabletLayout && (
                (wide && geometry.size.height >= 540)
                    || (!wide && geometry.size.height >= 780 && typeSize <= .large)
            )))
        }
        .background {
            RadialGradient(colors: [PuzzlePalette.panel, PuzzlePalette.background], center: .top, startRadius: 5, endRadius: 650)
                .ignoresSafeArea()
        }
        .foregroundStyle(PuzzlePalette.stone)
        #if os(iOS)
        .statusBarHidden(expanded)
        #endif
        .onAppear {
            guard !restored else { return }
            restored = true
            if highestCleared > 0 {
                load(min(highestCleared, levels.count - 1))
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showMap, onDismiss: closeMap) { campaignMap }
        #else
        .sheet(isPresented: $showMap, onDismiss: closeMap) { campaignMap }
        #endif
        .task(id: engine.needsUpdates && pausedAt == nil ? run : nil) {
            await advancePawn()
        }
    }

    private var campaignMap: some View {
        CampaignMap(levels: levels, current: engine.level.id, cleared: highestCleared) { index in
            mapSelection = index
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center) {
                HStack(spacing: 9) {
                    Image(systemName: "cube")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(PuzzlePalette.accent)
                        .accessibilityHidden(true)
                    Text("CORE")
                        .font(.system(.largeTitle, design: .default, weight: .medium))
                        .tracking(7)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                Label(form.title, systemImage: form.symbol)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(form.tint)
                    .lineLimit(1)
            }
            Text(form.next.map { "Reconstruct Reality · \($0.title) unlocks after level \($0.rawValue)" } ?? "Reconstruct Reality")
                .font(.subheadline)
                .foregroundStyle(PuzzlePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(PuzzlePalette.border)
                .frame(height: 1)
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
    }

    private var levelHeading: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LEVEL \(engine.level.id.formatted(.number.precision(.integerLength(2)))) / \(levels.count.formatted(.number.precision(.integerLength(2))))")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(PuzzlePalette.accent)
                Text(engine.level.name)
                    .font(.system(.title2, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 4)
            boardButton("Map", icon: "map", showTitle: true, action: openMap)
            VStack(alignment: .trailing, spacing: 4) {
                Text("TURNS")
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(PuzzlePalette.muted)
                Text(engine.moves.formatted(.number.precision(.integerLength(2))))
                    .font(.system(.headline, design: .monospaced).monospacedDigit())
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var board: some View {
        boardContent
            .padding(.vertical, expanded ? 0 : 17)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: expanded ? 0 : 21)
                    .fill(RadialGradient(colors: [PuzzlePalette.panel, PuzzlePalette.background], center: .center, startRadius: 5, endRadius: 350))
            }
            .overlay(alignment: .topLeading) {
                if !warned { boardStatus.padding(14).allowsHitTesting(false) }
            }
            .overlay(alignment: .top) {
                if let deadline = engine.fallDeadline {
                    EdgeCountdown(deadline: deadline, window: engine.dangerWindow, waitingForStair: engine.waitingForStair, atStart: engine.position == engine.level.start.id, pausedAt: pausedAt)
                        .padding(.horizontal, 15)
                        .padding(.trailing, expanded ? 54 : 0)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    if expanded { boardButton("Map", icon: "map", action: openMap) }
                    #if os(iOS)
                    boardButton("Reset view", icon: "arrow.counterclockwise", showTitle: !expanded) {
                        cameraReset += 1
                    }
                    #endif
                    boardButton(expanded ? "Exit full screen" : "Enter full screen",
                                icon: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                        expanded.toggle()
                    }
                }
                .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                if engine.isRunning {
                    Button(action: brake) {
                        Label(engine.brakeAvailable ? "Brake" : "Brake used", systemImage: "hand.raised.fill")
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PuzzleButtonStyle(primary: warned && engine.brakeAvailable))
                    .disabled(!engine.brakeAvailable)
                    .accessibilityHint("One use per pass. Slows the core or gives you more time at an edge.")
                    .padding(10)
                }
            }
            .overlay(alignment: .bottom) {
                if expanded && engine.isFinished {
                    outcome
                        .frame(maxWidth: 480)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 66)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    if engine.isRunning && !warned { momentumGauge.allowsHitTesting(false) }
                    if expanded && !engine.isFinished {
                        boardButton("Replay level", icon: "arrow.counterclockwise") { load(levelIndex) }
                    }
                }
                .padding(expanded ? 10 : 14)
            }
            .overlay {
                RoundedRectangle(cornerRadius: expanded ? 0 : 21)
                    .strokeBorder(warned || fallen ? PuzzlePalette.warning.opacity(0.62) : (won ? PuzzlePalette.accent.opacity(0.56) : PuzzlePalette.border))
                    .allowsHitTesting(false)
            }
    }

    private func boardButton(_ title: String, icon: String, showTitle: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if showTitle {
                    Label(title, systemImage: icon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                } else {
                    Image(systemName: icon).frame(width: 44, height: 44)
                }
            }
                .background(PuzzlePalette.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(PuzzlePalette.border) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder private var boardContent: some View {
        #if os(iOS)
        SpatialBoard(engine: engine, form: form, cameraReset: cameraReset, reduceMotion: reduceMotion, paused: pausedAt != nil, onRotate: rotate)
            .id(engine.level.id)
            .accessibilityRepresentation {
                VStack {
                    ForEach(engine.level.tiles.filter { $0.isRotatable || $0.stair != nil }) { tile in
                        if tile.stair != nil {
                            Text(accessibilityTitle(for: tile))
                                .accessibilityValue(engine.swingingStairs.contains(tile.id) ? "Swinging" : roadDirections(for: tile))
                        } else {
                            Button {
                                rotate(tile.id)
                            } label: {
                                Text(accessibilityTitle(for: tile))
                            }
                            .accessibilityValue(roadDirections(for: tile))
                            .disabled(engine.isFinished)
                        }
                    }
                }
            }
        #else
        IsometricBoard(engine: engine, form: form, locked: engine.isFinished, onRotate: rotate)
            .id(run)
        #endif
    }

    private func accessibilityTitle(for tile: Tile) -> String {
        let role = tile.stair != nil ? "Moving stair" : (tile.role == .start ? "Start" : (tile.role == .goal ? "Goal" : "Platform"))
        return "\(role), column \(tile.id.x + 1), row \(tile.id.y + 1), elevation \(tile.elevation)"
    }

    private func roadDirections(for tile: Tile) -> String {
        tile.exits(turns: engine.turns[tile.id, default: 0]).map { "\($0)" }.joined(separator: ", ")
    }

    private var momentumGauge: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
            ForEach(1...3, id: \.self) { tick in
                Capsule()
                    .fill(tick <= engine.momentum ? PuzzlePalette.warning : PuzzlePalette.border)
                    .frame(width: 9, height: 4)
            }
        }
        .foregroundStyle(engine.momentum > 0 ? PuzzlePalette.warning : PuzzlePalette.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Momentum")
        .accessibilityValue("\(engine.momentum) of 3")
    }

    private var boardStatus: some View {
        Label(statusTitle, systemImage: fallen ? "exclamationmark.triangle" : (won ? "checkmark.circle.fill" : "circle.dotted"))
            .foregroundStyle(fallen ? PuzzlePalette.warning : (won ? PuzzlePalette.goal : PuzzlePalette.muted))
            .tracking(1.1)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
    }

    private var statusTitle: String {
        switch engine.status {
        case .ready: "TAP A TILE TO START"
        case .traveling: "IN MOTION"
        case .danger: "CONNECT THE ROAD"
        case .fallen: engine.failure == .uphill ? "UPHILL BLOCKED" : "CORE LOST"
        case .won: "PATH COMPLETE"
        }
    }

    @ViewBuilder private var controls: some View {
        if engine.isFinished {
            outcome
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Rotate before the core falls", systemImage: "arrow.trianglehead.clockwise")
                    .font(.subheadline.weight(.semibold))
                Text(runInstructions)
                    .font(.footnote)
                    .foregroundStyle(PuzzlePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                runButton("Replay level", icon: "arrow.counterclockwise", primary: false) { load(levelIndex) }
            }
        }
    }

    private var runInstructions: String {
        if engine.level.showsOpeningRoute {
            return "Your first turn starts the core. Rotate an elbow to connect one route at a time."
        } else if engine.hasMovingStairs {
            return "Violet stairs swing on their own. Align the road they connect to, then time your crossing."
        } else if engine.level.bridges != nil {
            return "Trace each branch before turning. Both routes rejoin, but any uphill ramp ends the run."
        } else {
            return "Tap a tile to rotate. Drag to orbit, pinch to zoom, or drag with two fingers to pan."
        }
    }

    private var outcome: some View {
        let tint = earnedForm?.tint ?? (won ? PuzzlePalette.goal : PuzzlePalette.warning)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: earnedForm?.symbol ?? (won ? "flag.checkered" : "arrow.uturn.backward.circle"))
                    .font(.system(size: earnedForm == nil ? 20 : 26, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: earnedForm == nil ? 42 : 52, height: earnedForm == nil ? 42 : 52)
                    .background(tint.opacity(0.13), in: Circle())
                    .overlay { Circle().strokeBorder(tint.opacity(0.30)) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(won ? (earnedForm.map { "\($0.title) unlocked" } ?? (lastLevel ? "Reality reconstructed" : "Level cleared")) : "Run lost")
                        .font(earnedForm == nil ? .headline : .title3.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(outcomeDetail)
                        .font(.footnote)
                        .foregroundStyle(PuzzlePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if won {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { winActions(tint) }
                    VStack(spacing: 8) { winActions(tint) }
                }
            } else {
                runButton("Replay level", icon: "arrow.counterclockwise", primary: true, tint: tint) { load(levelIndex) }
            }
        }
        .padding(14)
        .background(PuzzlePalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.4)) }
    }

    @ViewBuilder private func winActions(_ tint: Color) -> some View {
        runButton("Replay level", icon: "arrow.counterclockwise", primary: false) { load(levelIndex) }
        runButton(lastLevel ? "Replay campaign" : "Continue to level \(engine.level.id + 1)", icon: "arrow.right", primary: true, tint: tint) {
            load(lastLevel ? 0 : levelIndex + 1)
        }
    }

    private var outcomeDetail: String {
        if won {
            if let earnedForm {
                return "Level \(engine.level.id) cleared. Your core evolved into \(earnedForm.title)."
            } else {
                return "Level \(engine.level.id) · \(engine.moves) turns"
            }
        } else if engine.failure == .uphill {
            return "That ramp climbed uphill. Check the whole branch before taking it."
        } else {
            return "The road stayed open at the edge. Use your brake for a second chance."
        }
    }

    private func runButton(_ title: String, icon: String, primary: Bool, tint: Color = PuzzlePalette.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(PuzzleButtonStyle(primary: primary, tint: tint))
    }

    private func rotate(_ cell: Cell) {
        guard pausedAt == nil else { return }
        let now = ContinuousClock.now
        var rotated = engine
        guard rotated.rotate(cell, at: now) else { return }

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.20)) {
            engine = rotated
        }
        updateEngine(at: now)

        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    private func brake() {
        guard pausedAt == nil, engine.brake(at: .now) else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    private func openMap() {
        pausedAt = .now
        mapSelection = nil
        showMap = true
    }

    private func closeMap() {
        if let index = mapSelection, index != levelIndex, levels.indices.contains(index), index <= highestCleared {
            load(index)
        } else if let pausedAt {
            engine.resume(after: ContinuousClock.now - pausedAt)
        }
        mapSelection = nil
        pausedAt = nil
    }

    private func load(_ index: Int) {
        let previousLevel = levelIndex
        levelIndex = index
        earnedForm = nil
        engine = PuzzleEngine(level: levels[index])
        if index != previousLevel { cameraReset = 0 }
        run += 1
    }

    private func advancePawn() async {
        let currentRun = run
        while !Task.isCancelled && currentRun == run && engine.needsUpdates && pausedAt == nil {
            updateEngine(at: .now)
            try? await Task.sleep(for: .milliseconds(24))
        }
    }

    private func updateEngine(at now: ContinuousClock.Instant) {
        var next = engine
        guard next.update(at: now) else { return }
        let fell = next.status == .fallen
        let startedCountdown = next.status == .danger && engine.status != .danger
        let previousForm = form
        let duration = fell ? 0.50 : 0.33
        withAnimation(reduceMotion ? nil : .easeIn(duration: duration)) {
            engine = next
            if next.status == .won {
                let cleared = max(highestCleared, next.level.id)
                let newForm = CoreForm.unlocked(after: cleared)
                highestCleared = cleared
                if newForm != previousForm { earnedForm = newForm }
            }
        }
        #if canImport(UIKit)
        if startedCountdown {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let atStart = next.position == next.level.start.id
            let message = next.waitingForStair ? "Wait for the stair" : (atStart ? "Reconnect Start" : "Connect the road")
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        if next.isFinished {
            UINotificationFeedbackGenerator().notificationOccurred(fell ? .error : .success)
        }
        #endif
    }
}

private struct PuzzleButtonStyle: ButtonStyle {
    var primary: Bool
    var tint: Color = PuzzlePalette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = primary && isEnabled
        let shape = RoundedRectangle(cornerRadius: 10)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 11)
            .foregroundStyle(highlighted ? PuzzlePalette.background : (isEnabled ? PuzzlePalette.stone : PuzzlePalette.muted))
            .background(highlighted ? tint : PuzzlePalette.panel, in: shape)
            .overlay { shape.strokeBorder(PuzzlePalette.border) }
            .opacity(configuration.isPressed ? 0.72 : (isEnabled ? 1 : 0.63))
    }
}
