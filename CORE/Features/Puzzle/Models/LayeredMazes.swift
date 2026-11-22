enum LayeredMazes {
    static let levels: [Level] = [
        "Soot Gallery", "Three Embers", "Glass Chasm", "Ember Circuit", "Ash Meridian", "The Crucible",
        "Broken Compass", "Stone Current", "False Horizon", "Obsidian Run",
        "Rift Relay", "The Divide", "Quiet Caldera", "Black Ridge", "Magnetic Pass", "Caldera Gate",
        "Falling Meridian", "Gravity Lock", "Blind Terrace", "Molten Switch",
        "Twin Rifts", "The Long Drop", "Fault Chamber", "Burning Orbit", "The Descent", "Apex Gate",
        "Stillpoint", "Parallel Landing", "Counterflow", "Pivot Hall", "Twin Descent", "Staggered Heights",
        "Twin Horizons", "The Quiet Tower", "Signal Court", "Reality Rejoined"
    ].enumerated().map { $0.offset + 25 >= 40 ? ForkedMazes.foldedLevel($0.offset + 25, name: $0.element) : make($0.offset + 25, name: $0.element) }

    private struct Branch {
        let origin: Cell
        let cells: [Cell]
        let directions: [Direction]
        let startHeight: Int
        let climbIndex: Int?

        func height(at index: Int) -> Int {
            if let climbIndex, index >= climbIndex { return startHeight - (climbIndex - 1) / 3 }
            return startHeight - 1 - index / 3
        }
    }

    private static func make(_ id: Int, name: String) -> Level {
        let compact = (30...40).contains(id)
        let width = compact ? 4 + id % 2 : 5 + id % 3
        let depth = (compact ? 2 : 3) + id % 2
        let finishWidth = compact ? width - id % 2 : width + (id % 4 < 2 ? 0 : 1)
        var segments: [(Direction, Int)] = [
            (.east, width), (.south, depth), (.west, width - (id >= 41 ? id % 2 : 0)),
            (.south, compact ? 2 : 3), (.east, id >= 41 ? finishWidth - 1 : finishWidth)
        ]
        if id >= 41 {
            segments += [(.south, 3 + id % 2), (.west, finishWidth - 1)]
            if id >= 51 && id.isMultiple(of: 2) { segments += [(.south, 2), (.east, 2)] }
        }

        let route = segments.flatMap { Array(repeating: $0.0, count: $0.1) }
        var cells = [Cell(x: 0, y: 0)]
        for direction in route { cells.append(cells.last!.neighbor(direction)) }
        var occupied = Set(cells)
        func height(_ index: Int) -> Int { 7 - index * 6 / route.count }

        var branches: [Branch] = []
        func addBranch(from origin: Cell, exit side: Direction, height: Int, seed: Int, long: Bool) {
            let bend = side.rotated(by: seed.isMultiple(of: 2) ? 1 : -1)
            let inward = [side, side, bend, bend, side.opposite, bend]
            let outward = [side, side, bend.opposite, bend.opposite, side, bend]
            let short = [[side, side, bend], [side, side, bend.opposite], [side, side, side], [side, side]]
            let compactBends = [[side, bend, bend], [side, bend.opposite, bend.opposite]]
            let patterns = long ? [inward, outward, Array(inward.prefix(4)), Array(outward.prefix(4))] + short
                : (compact ? compactBends + short : short)
            for directions in patterns {
                var cell = origin
                let path = directions.map { direction in
                    cell = cell.neighbor(direction)
                    return cell
                }
                guard path.allSatisfy({ !occupied.contains($0) }) else { continue }
                occupied.formUnion(path)
                branches.append(Branch(origin: origin, cells: path, directions: directions,
                                       startHeight: height, climbIndex: seed.isMultiple(of: 3) ? path.count - 1 : nil))
                break
            }
        }

        let bends = route.indices.dropFirst().filter { route[$0 - 1] != route[$0] }
        let candidates = id >= 30 ? Array(bends) : bends.enumerated().filter { $0.offset != 1 }.map(\.element)
        func approach(_ fork: Int) -> [Cell] {
            let side = route[fork].opposite
            let first = cells[fork].neighbor(side)
            return [first, first.neighbor(side)]
        }
        if id >= 40 { occupied.formUnion(candidates.flatMap(approach)) }
        for fork in candidates {
            if id >= 40 { occupied.subtract(approach(fork)) }
            // The same two-port elbow can keep its entry and select either opposite exit.
            addBranch(from: cells[fork], exit: route[fork].opposite, height: height(fork),
                      seed: id + fork + branches.count, long: id >= 41)
        }

        if id >= 30 {
            let primaries = branches
            for (branchIndex, branch) in primaries.enumerated() {
                let bends = branch.directions.indices.dropFirst().filter {
                    branch.directions[$0 - 1] != branch.directions[$0]
                }
                for fork in bends.filter({ fork in id < 40 || fork <= (branch.climbIndex ?? Int.max) }).prefix(id >= 40 ? 2 : 1) {
                    addBranch(from: branch.cells[fork - 1], exit: branch.directions[fork].opposite,
                              height: branch.height(at: fork - 1), seed: id + branchIndex + fork, long: id >= 51)
                }
            }
        }

        let branchOrigins = Set(branches.map(\.origin))
        let rotation = (id - 25) % 4
        let mirrored = (id / 4).isMultiple(of: 2)
        func transform(_ cell: Cell) -> Cell {
            let x = mirrored ? -cell.x : cell.x
            switch rotation {
            case 1: return Cell(x: -cell.y, y: x)
            case 2: return Cell(x: -x, y: -cell.y)
            case 3: return Cell(x: cell.y, y: -x)
            default: return Cell(x: x, y: cell.y)
            }
        }
        func facing(_ direction: Direction) -> Direction {
            let flipped = mirrored && (direction == .east || direction == .west) ? direction.opposite : direction
            return flipped.rotated(by: rotation)
        }
        let transformed = occupied.map(transform)
        let minX = transformed.map(\.x).min() ?? 0
        let minY = transformed.map(\.y).min() ?? 0
        func point(_ cell: Cell) -> Cell {
            let value = transform(cell)
            return Cell(x: value.x - minX, y: value.y - minY)
        }
        var tiles: [Tile] = []
        var bridges: Set<Bridge> = []
        for index in cells.indices {
            let cell = point(cells[index])
            let incoming = index == 0 ? nil : route[index - 1].opposite
            let forward = index == route.count ? nil : route[index]
            let roads = [incoming, forward].compactMap { $0 }
            let role: Tile.Role = index == 0 ? .start : (index == route.count ? .goal : .platform)
            let isFork = branchOrigins.contains(cells[index])
            let turns = role == .platform && index > 2 && (id + index).isMultiple(of: 3) ? 1 : 0
            tiles.append(Tile(id: cell, role: role, roads: roads.map(facing), initialTurns: turns,
                              elevation: height(index), isFork: isFork))
            if index > 0 { bridges.insert(Bridge(point(cells[index - 1]), cell)) }
        }

        for branch in branches {
            var previous = point(branch.origin)
            for (index, position) in branch.cells.enumerated() {
                let cell = point(position)
                let incoming = branch.directions[index].opposite
                let forward = index + 1 < branch.directions.count ? branch.directions[index + 1] : nil
                let roads = [incoming, forward].compactMap { $0 }
                let isFork = branchOrigins.contains(position)
                let role: Tile.Role = index == 0 || isFork ? .platform : .fixture
                let turns = role == .platform ? (id + position.x + position.y) % 2 : 0
                tiles.append(Tile(id: cell, role: role, roads: roads.map(facing),
                                  initialTurns: turns, elevation: branch.height(at: index), isFork: isFork))
                bridges.insert(Bridge(previous, cell))
                previous = cell
            }
        }

        precondition(branches.count >= 2 && Set(tiles.map(\.id)).count == tiles.count)
        return Level(id: id, name: name, tiles: tiles, reactionTime: .milliseconds(1920),
                     bridges: bridges, showsOpeningRoute: true)
    }
}
