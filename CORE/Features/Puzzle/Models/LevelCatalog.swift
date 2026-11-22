enum LevelCatalog {
    static let levels: [Level] = [
        make(1, 3400, "First Descent", route: [.east, .east],
             scramble: [1], drops: [1], branches: []),
        make(2, 2800, "False Ascent", route: route([(.east, 2), (.south, 2), (.east, 1)]),
             scramble: [1, 3, 0, 2], drops: [2, 4], branches: [2]),
        make(3, 2300, "Switchback", route: route([(.east, 3), (.south, 2), (.west, 3)]),
             scramble: [1, 0, 2, 0, 1, 0, 1], drops: [2, 5, 7], branches: [3, 5]),
        make(4, 2200, "Inner Orbit", route: route([(.east, 3), (.south, 3), (.west, 3), (.north, 2), (.east, 1)]),
             scramble: [1, 1, 0, 1, 0, 2, 0, 1, 1, 0, 1], drops: [2, 3, 4, 8], branches: [3, 6]),
        make(5, 2000, "The Core", route: route([(.east, 4), (.south, 3), (.west, 4), (.north, 2), (.east, 2)]),
             scramble: [1, 0, 1, 3, 1, 0, 2, 1, 0, 1, 3, 1, 2, 0], drops: [2, 3, 4, 7, 8, 12], branches: [4, 11]),
        make(6, 1850, "Gravity Well", route: route([(.east, 4), (.south, 4), (.west, 4), (.north, 2), (.east, 3), (.south, 1)]),
             drops: [2, 3, 4, 6, 7, 8, 13, 14, 16], branches: [4, 8, 14]),
        make(7, 1700, "Fault Lines", route: route([(.east, 5), (.south, 4), (.west, 5), (.north, 2), (.east, 3), (.south, 1), (.east, 1)]),
             drops: [2, 3, 4, 5, 7, 8, 9, 12, 13, 14, 17, 18, 19], branches: [5, 9, 14]),
        make(8, 1830, "Echo Chamber", route: route([(.east, 6), (.south, 4), (.west, 6), (.north, 2), (.east, 3), (.south, 1)]),
             scramble: [1, 0, 0, 0, 1, 1, 0, 0, 0, 2, 1, 0, 0, 0, 1, 2, 0, 1, 0, 1, 1], drops: [1, 2, 7, 8, 9, 14, 15, 16, 21, 22], branches: [6, 10, 18]),
        make(9, 1807, "Pressure Drop", route: route([(.east, 6), (.south, 4), (.west, 6), (.north, 2), (.east, 4), (.south, 1), (.west, 1)]),
             scramble: [1, 0, 0, 1, 1, 2, 0, 0, 1, 3, 0, 0, 0, 1, 1, 3, 0, 2, 1, 1, 0, 3, 1], drops: [1, 6, 7, 8, 13, 14, 15, 20, 21, 22], branches: [6, 10, 18]),
        make(10, 1784, "Crystalline Gate", route: route([(.east, 6), (.south, 5), (.west, 6), (.north, 3), (.east, 3), (.south, 1)]),
             scramble: [1, 0, 1, 1, 0, 3, 0, 1, 1, 0, 2, 0, 1, 1, 0, 0, 2, 1, 1, 2, 0, 0, 2], drops: [5, 6, 7, 12, 13, 14, 19, 20, 21], branches: [6, 11, 20])
    ] + ForkedMazes.levels + LayeredMazes.levels

    private static func route(_ segments: [(Direction, Int)]) -> [Direction] {
        segments.flatMap { Array(repeating: $0.0, count: $0.1) }
    }

    private static func make(
        _ id: Int, _ reactionMilliseconds: Int, _ name: String, route: [Direction],
        scramble: [Int]? = nil, drops: Set<Int>, branches: [Int]
    ) -> Level {
        var cells = [Cell(x: 0, y: 0)]
        for direction in route {
            cells.append(cells.last!.neighbor(direction))
        }
        precondition(Set(cells).count == cells.count)
        precondition(scramble == nil || scramble?.count == route.count - 1)

        var height = drops.count
        var tiles = [Tile]()
        for index in cells.indices {
            if drops.contains(index) { height -= 1 }
            let cell = cells[index]
            if index == 0 {
                tiles.append(Tile(id: cell, role: .start, roads: [route[0]], initialTurns: 0, elevation: height))
            } else if index == route.count {
                tiles.append(Tile(id: cell, role: .goal, roads: [route[index - 1].opposite], initialTurns: 0, elevation: height))
            } else {
                let turns = scramble?[index - 1] ?? (index % 3 == 0 ? 2 : 1)
                tiles.append(Tile(id: cell, role: .platform, roads: [route[index - 1].opposite, route[index]], initialTurns: turns, elevation: height, isFork: branches.contains(index)))
            }
        }

        var occupied = Set(cells)
        for (offset, index) in branches.enumerated() {
            let source = tiles[index]
            let direction = route[index].opposite
            let first = source.id.neighbor(direction)
            let second = first.neighbor(direction)
            precondition(!occupied.contains(first) && !occupied.contains(second))
            occupied.formUnion([first, second])
            let uphillTrap = offset.isMultiple(of: 2)
            tiles.append(Tile(id: first, role: .fixture, roads: [direction.opposite, direction], initialTurns: 0, elevation: source.elevation - 1))
            tiles.append(Tile(id: second, role: .fixture, roads: [direction.opposite], initialTurns: 0, elevation: source.elevation + (uphillTrap ? 1 : -1)))
        }

        return Level(id: id, name: name, tiles: tiles, reactionTime: .milliseconds(reactionMilliseconds))
    }
}
