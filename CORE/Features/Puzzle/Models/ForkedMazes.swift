enum ForkedMazes {
    static let levels: [Level] = [
        make(11, "Red Horizon", [.init(3, 1, 1, .north, 2)]),
        make(12, "Dustfall", [.init(3, 1, 1, .south, 3), .init(2, 1, 1, .north, 2)]),
        make(13, "Ares Pass", [.init(3, 2, 1, .south, 2), .init(3, 1, 2, .south, 3)]),
        make(14, "Phobos Run", [.init(3, 1, 2, .north, 4), .init(3, 2, 1, .south, 2)]),
        make(15, "Valles Rift", [.init(4, 2, 1, .south, 3), .init(3, 2, 2, .north, 5)]),
        make(16, "Rust Belt", [.init(3, 2, 1, .north, 2), .init(4, 1, 2, .north, 5)]),
        make(17, "Red Labyrinth", [.init(3, 1, 1, .south, 3), .init(2, 1, 2, .north, 2), .init(3, 2, 1, .south, 4)]),
        make(18, "Escape Velocity", [.init(2, 2, 1, .north, 2), .init(3, 1, 2, .south, 3), .init(3, 1, 1, .north, 3)]),
        make(19, "Solar Flare", [.init(3, 1, 2, .south, 3), .init(3, 2, 2, .south, 5), .init(3, 2, 1, .north, 3)]),
        make(20, "Ignition Gate", [.init(3, 2, 2, .north, 5), .init(4, 2, 1, .south, 4), .init(3, 1, 2, .north, 5)]),
        make(21, "Furnace Orbit", [.init(4, 2, 1, .south, 4), .init(3, 2, 2, .north, 5), .init(4, 1, 2, .south, 3)]),
        make(22, "Reconstruct Reality", [.init(4, 2, 2, .north, 5), .init(4, 1, 2, .north, 5), .init(4, 2, 1, .south, 5)]),
        make(23, "Basalt Crossing", [.init(3, 2, 1, .south, 3), .init(2, 1, 1, .north, 2)]),
        make(24, "Cinder Vein", [.init(3, 1, 2, .north, 4), .init(4, 2, 1, .south, 3)])
    ]

    private struct Fork {
        let span: Int
        let northDepth: Int
        let southDepth: Int
        let safeSide: Direction
        let climbStep: Int

        init(_ span: Int, _ northDepth: Int, _ southDepth: Int, _ safeSide: Direction, _ climbStep: Int) {
            self.span = span
            self.northDepth = northDepth
            self.southDepth = southDepth
            self.safeSide = safeSide
            self.climbStep = climbStep
        }

        func lane(toward side: Direction) -> [Direction] {
            let depth = side == .north ? northDepth : southDepth
            return Array(repeating: side, count: depth)
                + Array(repeating: .east, count: span)
                + Array(repeating: side.opposite, count: depth)
        }

        func elevation(at step: Int, on side: Direction, length: Int, from height: Int, folded: Bool) -> Int {
            if folded {
                // Both profiles have ramps at the same relative landmarks. Only the grade changes.
                let middle = min(climbStep, length - 2)
                if step == length - 1 { return height - 3 }
                if step < middle { return height - (side == safeSide ? 1 : 2) }
                return height - (side == safeSide ? 2 : 1)
            }
            if step == length - 1 { return height - 3 }
            if side != safeSide {
                if step == climbStep { return height }
                return height - 1
            }
            return height - (step < length / 2 ? 1 : 2)
        }
    }

    static func foldedLevel(_ id: Int, name: String) -> Level {
        var seed = UInt64(id)
        func draw(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(limit))
        }
        let count = 4 + (id - 40) / 8
        let forks = (0..<count).map { _ in
            let span = 2 + draw(2)
            let north = 1 + draw(2)
            let south = 1 + draw(2)
            let side: Direction = draw(2) == 0 ? .north : .south
            let unsafeLength = span + 2 * (side == .north ? south : north)
            return Fork(span, north, south, side, 2 + draw(unsafeLength - 3))
        }
        return make(id, name, forks, folded: true)
    }

    private static func make(_ id: Int, _ name: String, _ forks: [Fork], folded: Bool = false) -> Level {
        let centerRow = 2
        let start = Cell(x: 0, y: centerRow)
        var height = forks.count * 3
        var tiles = [Tile(id: start, role: .start, roads: [.east], initialTurns: 0, elevation: height)]
        var bridges = Set<Bridge>()
        var previous = start
        var heading = Direction.east

        if folded {
            previous = start.neighbor(heading)
            bridges.insert(Bridge(start, previous))
            tiles.append(Tile(id: previous, role: .platform, roads: [.west, .east], initialTurns: 0, elevation: height))
        }
        for (index, fork) in forks.enumerated() {
            let split = previous.neighbor(heading)
            let join = (0..<fork.span).reduce(split) { cell, _ in cell.neighbor(heading) }
            func facing(_ local: Direction) -> Direction { local.rotated(by: heading.rawValue - Direction.east.rawValue) }
            bridges.insert(Bridge(previous, split))
            tiles.append(Tile(id: split, role: .platform, roads: [heading.opposite, facing(.north)], initialTurns: 2, elevation: height, isFork: true))
            for side in [Direction.north, .south] {
                let lane = fork.lane(toward: side).map(facing)
                precondition(fork.climbStep < fork.lane(toward: fork.safeSide.opposite).count - 1)
                var cell = split
                for step in 1..<lane.count {
                    let incoming = lane[step - 1]
                    let outgoing = lane[step]
                    let next = cell.neighbor(incoming)
                    bridges.insert(Bridge(cell, next))
                    let bend = incoming != outgoing
                    let pattern = step + id + index + (side == .north ? 0 : 1)
                    let rotations = bend ? pattern % 2 : (pattern.isMultiple(of: 3) ? 1 : 0)
                    tiles.append(Tile(id: next, role: .platform, roads: [incoming.opposite, outgoing],
                                      initialTurns: rotations,
                                      elevation: fork.elevation(at: step, on: side, length: lane.count, from: height, folded: folded)))
                    cell = next
                }
                bridges.insert(Bridge(cell, join))
            }
            height -= 3
            tiles.append(Tile(id: join, role: .platform, roads: [facing(.north), heading], initialTurns: 2, elevation: height))
            previous = join
            var connectorSteps = [heading]
            if folded && index % 2 == 1 && index + 1 < forks.count {
                connectorSteps += Array(repeating: .south, count: 5)
                heading = heading.opposite
                connectorSteps.append(heading)
            }
            for (step, direction) in connectorSteps.enumerated() {
                let connector = previous.neighbor(direction)
                let outgoing = step + 1 < connectorSteps.count ? connectorSteps[step + 1] : heading
                bridges.insert(Bridge(previous, connector))
                tiles.append(Tile(id: connector, role: .platform, roads: [direction.opposite, outgoing],
                                  initialTurns: index == forks.count - 1 ? 0 : 1, elevation: height))
                previous = connector
            }
        }
        let goal = previous.neighbor(heading)
        bridges.insert(Bridge(previous, goal))
        tiles.append(Tile(id: goal, role: .goal, roads: [heading.opposite], initialTurns: 0, elevation: height))
        precondition(Set(tiles.map(\.id)).count == tiles.count)
        return Level(id: id, name: name, tiles: tiles, reactionTime: .milliseconds(id < 15 ? 2100 : 1850), bridges: bridges, showsOpeningRoute: folded)
    }
}
