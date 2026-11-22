import SwiftUI

struct IsometricBoard: View {
    let engine: PuzzleEngine
    let form: CoreForm
    let locked: Bool
    let onRotate: (Cell) -> Void

    var body: some View {
        GeometryReader { geometry in
            let layout = BoardLayout(tiles: engine.level.tiles, size: geometry.size)
            ZStack(alignment: .topLeading) {
                BoardGrid(unit: layout.unit, origin: layout.origin)
                ForEach(engine.level.tiles.sorted(by: { BoardLayout.isBehind($0, $1) })) { tile in
                    let center = layout.center(tile.id)
                    StoneTile(tile: tile, turns: Double(engine.turns[tile.id, default: 0]), unit: layout.unit,
                              lit: engine.hasThroughTrack(tile.id))
                        .frame(width: layout.unit * 2.7, height: layout.unit * 2.4)
                        .position(center)
                        .allowsHitTesting(false)
                }
                ForEach(engine.level.tiles.filter { $0.isRotatable }) { tile in
                    Button { onRotate(tile.id) } label: {
                        Diamond()
                            .fill(.clear)
                            .frame(width: layout.unit * 1.68, height: layout.unit * 0.97)
                            .contentShape(Diamond())
                    }
                    .buttonStyle(.plain)
                    .position(layout.center(tile.id))
                    .accessibilityLabel("Platform, column \(tile.id.x + 1), row \(tile.id.y + 1)")
                    .accessibilityValue(roadDescription(for: tile))
                    .accessibilityHint("Rotates clockwise by 90 degrees")
                }
                ForEach([engine.level.start, engine.level.goal]) { tile in
                    let center = layout.center(tile.id)
                    Text(tile.role == .start ? "START" : "GOAL")
                        .font(.system(size: max(8, min(11, layout.unit * 0.23)), weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(tile.role == .goal ? PuzzlePalette.goal : PuzzlePalette.start)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                        .position(x: center.x, y: center.y - max(21, layout.unit * 0.65))
                        .allowsHitTesting(false)
                }
                pawn(unit: layout.unit)
                    .position(pawnCenter(in: layout))
                    .opacity(engine.status == .fallen ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .disabled(locked)
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Puzzle board")
    }

    private func roadDescription(for tile: Tile) -> String {
        let directions = tile.exits(turns: engine.turns[tile.id, default: 0]).map { direction in
            switch direction {
            case .north: "upper right"
            case .east: "lower right"
            case .south: "lower left"
            case .west: "upper left"
            }
        }
        return directions.joined(separator: ", ")
    }

    private func pawnCenter(in layout: BoardLayout) -> CGPoint {
        let center = layout.center(engine.position)
        guard let edge = engine.edge else { return center }
        let fell = engine.status == .fallen
        let distance = layout.unit * (fell ? 0.95 : 0.38)
        let vector = BoardLayout.project(CGFloat(edge.dx), CGFloat(edge.dy))
        return CGPoint(x: center.x + vector.x * distance,
                       y: center.y + vector.y * distance + (fell ? layout.unit * 0.85 : 0))
    }

    private func pawn(unit: CGFloat) -> some View {
        let diameter = max(9, min(23, unit * 0.43))
        return ZStack {
            Ellipse()
                .fill(.black.opacity(0.6))
                .frame(width: diameter * 1.25, height: diameter * 0.42)
                .blur(radius: 2)
            Circle()
                .fill(RadialGradient(colors: [.white, form.tint, form.tint.opacity(0.45)], center: .topLeading, startRadius: 0, endRadius: diameter))
                .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.7) }
                .frame(width: diameter, height: diameter)
                .shadow(color: form.tint.opacity(0.75), radius: diameter * 0.65)
                .scaleEffect(engine.status == .won ? 1.3 : 1)
                .offset(y: -diameter * 0.55)
        }
    }
}

private struct BoardLayout {
    let origin: CGPoint
    let unit: CGFloat

    init(tiles: [Tile], size: CGSize) {
        let points = tiles.map { Self.project(CGFloat($0.id.x), CGFloat($0.id.y)) }
        let left = points.map(\.x).min() ?? 0
        let right = points.map(\.x).max() ?? 0
        let top = points.map(\.y).min() ?? 0
        let bottom = points.map(\.y).max() ?? 0
        unit = max(1, min(105, size.width / (right - left + 2.4), size.height / (bottom - top + 2.55)))
        origin = CGPoint(
            x: size.width / 2 - (left + right) * unit / 2,
            y: size.height / 2 - (top + bottom) * unit / 2
        )
    }

    func center(_ cell: Cell) -> CGPoint {
        let p = Self.project(CGFloat(cell.x), CGFloat(cell.y))
        return CGPoint(x: origin.x + p.x * unit, y: origin.y + p.y * unit)
    }

    static func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: (x - y) * 0.8660254, y: (x + y) * 0.5)
    }

    static func isBehind(_ lhs: Tile, _ rhs: Tile) -> Bool {
        let lhsDepth = lhs.id.x + lhs.id.y
        let rhsDepth = rhs.id.x + rhs.id.y
        if lhsDepth == rhsDepth {
            return lhs.id.x < rhs.id.x
        } else {
            return lhsDepth < rhsDepth
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        polygon([
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY)
        ])
    }
}

private struct BoardGrid: View {
    let unit: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { context, size in
            let radius = Int((size.width + size.height) / max(unit, 16)) + 2
            func point(_ x: Int, _ y: Int) -> CGPoint {
                let position = BoardLayout.project(CGFloat(x), CGFloat(y))
                return CGPoint(x: origin.x + position.x * unit, y: origin.y + position.y * unit + unit * 0.32)
            }
            var grid = Path()
            for line in -radius...radius {
                grid.move(to: point(line, -radius))
                grid.addLine(to: point(line, radius))
                grid.move(to: point(-radius, line))
                grid.addLine(to: point(radius, line))
            }
            context.stroke(grid, with: .color(.white.opacity(0.054)), lineWidth: 0.5)
        }
        .mask(RadialGradient(colors: [.white, .white.opacity(0.7), .clear], center: .center, startRadius: 16, endRadius: 360))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StoneTile: View, Animatable {
    let tile: Tile
    var turns: Double
    let unit: CGFloat
    let lit: Bool

    var animatableData: Double {
        get { turns }
        set { turns = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let angle = turns.remainder(dividingBy: 4) * .pi / 2
            func point(_ x: CGFloat, _ y: CGFloat, depth: CGFloat = 0) -> CGPoint {
                let rotatedX = x * cos(angle) - y * sin(angle)
                let rotatedY = x * sin(angle) + y * cos(angle)
                let p = BoardLayout.project(rotatedX, rotatedY)
                return CGPoint(x: center.x + p.x * unit, y: center.y + (p.y + depth) * unit)
            }
            let corners: [(CGFloat, CGFloat)] = [(-0.48, -0.48), (0.48, -0.48), (0.48, 0.48), (-0.48, 0.48)]
            let top = corners.map { point($0.0, $0.1) }
            let bottom = corners.map { point($0.0, $0.1, depth: 0.25) }

            var shadow = context
            shadow.addFilter(.blur(radius: max(2, unit * 0.11)))
            shadow.fill(polygon(bottom.map { CGPoint(x: $0.x + unit * 0.07, y: $0.y + unit * 0.10) }), with: .color(.black.opacity(0.85)))

            for index in corners.indices {
                let next = (index + 1) % corners.count
                if top[index].x > top[next].x {
                    let face = polygon([top[index], top[next], bottom[next], bottom[index]])
                    let light = top[index].y > top[next].y
                    let color = light ? Color(white: 0.47) : Color(white: 0.30)
                    context.fill(face, with: .linearGradient(Gradient(colors: [color, Color(white: 0.12)]),
                        startPoint: center, endPoint: CGPoint(x: center.x, y: center.y + unit * 0.72)))
                    var rim = Path()
                    rim.move(to: CGPoint(x: top[index].x, y: top[index].y + unit * 0.065))
                    rim.addLine(to: CGPoint(x: top[next].x, y: top[next].y + unit * 0.065))
                    context.stroke(rim, with: .color(.white.opacity(0.25)), lineWidth: max(0.5, unit * 0.018))
                }
            }

            let surface = polygon(top)
            let stone = tile.stair == nil ? PuzzlePalette.stone : PuzzlePalette.stair
            context.fill(surface, with: .linearGradient(Gradient(colors: [stone, Color(red: 0.64, green: 0.61, blue: 0.55)]),
                startPoint: CGPoint(x: center.x - unit * 0.45, y: center.y - unit * 0.52),
                endPoint: CGPoint(x: center.x + unit * 0.25, y: center.y + unit * 0.5)))
            context.stroke(surface, with: .color(.white.opacity(0.60)), lineWidth: max(0.5, unit * 0.014))
            let inset = polygon(corners.map { point($0.0 * 0.86, $0.1 * 0.86) })
            context.stroke(inset, with: .color(.black.opacity(0.24)), lineWidth: max(0.5, unit * 0.012))

            let points = TrackLine.points(for: tile.roads, edge: 0.48).map {
                point(CGFloat($0.x), CGFloat($0.y))
            }
            let road = Path { $0.addLines(points) }
            context.stroke(road, with: .color(Color(red: 0.17, green: 0.16, blue: 0.14)),
                style: StrokeStyle(lineWidth: unit * 0.14, lineCap: .round, lineJoin: .round))
            if lit {
                context.stroke(road, with: .color(PuzzlePalette.accent),
                    style: StrokeStyle(lineWidth: max(1, unit * 0.085), lineCap: .round, lineJoin: .round))
            }
            if tile.role == .start || tile.role == .goal {
                let marker = polygon([point(0, -0.19), point(0.19, 0), point(0, 0.19), point(-0.19, 0)])
                context.fill(marker, with: .color(Color(white: 0.16)))
                context.stroke(marker, with: .color(tile.role == .goal ? PuzzlePalette.goal : PuzzlePalette.start), lineWidth: max(1, unit * 0.026))
            }
        }
        .accessibilityHidden(true)
    }
}

private func polygon(_ points: [CGPoint]) -> Path {
    Path { path in
        path.addLines(points)
        path.closeSubpath()
    }
}
