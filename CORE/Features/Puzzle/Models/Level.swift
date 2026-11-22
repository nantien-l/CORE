import Foundation

enum Direction: Int, CaseIterable, Hashable {
    case north, east, south, west

    var dx: Int {
        switch self {
        case .east: 1
        case .west: -1
        default: 0
        }
    }

    var dy: Int {
        switch self {
        case .south: 1
        case .north: -1
        default: 0
        }
    }

    var opposite: Self { rotated(by: 2) }

    func rotated(by turns: Int) -> Self {
        Self(rawValue: (rawValue + turns % 4 + 4) % 4)!
    }
}

struct Cell: Hashable {
    let x: Int
    let y: Int

    func neighbor(_ direction: Direction) -> Self {
        Self(x: x + direction.dx, y: y + direction.dy)
    }
}

struct StairTiming {
    static let swingDuration: Duration = .milliseconds(240)
    let interval: Duration
    let delay: Duration
}

struct Tile: Identifiable {
    enum Role: Equatable { case start, platform, fixture, goal }

    let id: Cell
    let role: Role
    let roads: [Direction]
    let initialTurns: Int
    let elevation: Int
    var stair: StairTiming? = nil
    var isFork = false

    var isRotatable: Bool { role != .fixture && stair == nil }

    func exits(turns: Int) -> [Direction] {
        roads.map { $0.rotated(by: turns) }
    }
}

struct Bridge: Hashable {
    private let first: Cell
    private let second: Cell

    init(_ a: Cell, _ b: Cell) {
        if a.x < b.x || (a.x == b.x && a.y < b.y) {
            first = a
            second = b
        } else {
            first = b
            second = a
        }
    }
}

struct Level: Identifiable {
    let id: Int
    let name: String
    let tiles: [Tile]
    let reactionTime: Duration
    var bridges: Set<Bridge>? = nil
    var showsOpeningRoute = false

    func hasBridge(_ cell: Cell, toward direction: Direction) -> Bool {
        bridges?.contains(Bridge(cell, cell.neighbor(direction))) ?? true
    }

    var start: Tile { tiles[0] }
    var goal: Tile { tiles.first { $0.role == .goal }! }
}
