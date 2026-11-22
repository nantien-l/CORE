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

        func elevation(at step: Int, on side: Direction, length: Int, from height: Int) -> Int {
            if step == length - 1 { return height - 3 }
            if side != safeSide {
                if step == climbStep { return height }
                return height - 1
            }
            return height - (step < length / 2 ? 1 : 2)
        }
    }

    private static func make(_ id: Int, _ name: String, _ forks: [Fork]) -> Level {
        let centerRow = 2
        let start = Cell(x: 0, y: centerRow)
        var height = forks.count * 3
        var tiles = [Tile(id: start, role: .start, roads: [.east], initialTurns: 0, elevation: height)]
        var bridges = Set<Bridge>()
        var previous = start
        var x = 1

        for (index, fork) in forks.enumerated() {
            let split = Cell(x: x, y: centerRow)
            let join = Cell(x: x + fork.span, y: centerRow)
            bridges.insert(Bridge(previous, split))
            tiles.append(Tile(id: split, role: .platform, roads: [.west, .north], initialTurns: 2, elevation: height, isFork: true))
            for side in [Direction.north, .south] {
                let lane = fork.lane(toward: side)
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
                                      elevation: fork.elevation(at: step, on: side, length: lane.count, from: height)))
                    cell = next
                }
                bridges.insert(Bridge(cell, join))
            }
            height -= 3
            tiles.append(Tile(id: join, role: .platform, roads: [.north, .east], initialTurns: 2, elevation: height))
            previous = join
            x = join.x + 2
            let connector = join.neighbor(.east)
            bridges.insert(Bridge(previous, connector))
            tiles.append(Tile(id: connector, role: .platform, roads: [.west, .east],
                              initialTurns: index == forks.count - 1 ? 0 : 1, elevation: height))
            previous = connector
        }
        let goal = previous.neighbor(.east)
        bridges.insert(Bridge(previous, goal))
        tiles.append(Tile(id: goal, role: .goal, roads: [.west], initialTurns: 0, elevation: height))
        precondition(Set(tiles.map(\.id)).count == tiles.count)
        return Level(id: id, name: name, tiles: tiles, reactionTime: .milliseconds(id < 15 ? 2100 : 1850), bridges: bridges)
    }
}
