struct PuzzleEngine {
    enum Status: Equatable { case ready, traveling, danger, fallen, won }

    enum Failure { case drop, uphill }

    struct ForkPreview: Equatable {
        let cell: Cell
        let preferred: Direction?
    }

    let level: Level
    private struct StairSchedule {
        var nextTurn: ContinuousClock.Instant
        var settlesAt: ContinuousClock.Instant?
    }

    private let tiles: [Cell: Tile]
    private let stairs: [Cell: StairTiming]
    private var schedules: [Cell: StairSchedule] = [:]
    private(set) var swingingStairs: Set<Cell> = []
    private var nextStepAt: ContinuousClock.Instant?
    private(set) var turns: [Cell: Int]
    private(set) var position: Cell
    private(set) var entry: Direction?
    private(set) var moves = 0
    private(set) var status: Status = .ready
    private(set) var fallDeadline: ContinuousClock.Instant?
    private(set) var edge: Direction?
    private(set) var failure: Failure?
    private(set) var momentum = 0
    private(set) var brakeAvailable = true
    private(set) var dangerWindow: Duration = .zero
    private(set) var travelTime: Duration = .milliseconds(660)

    var waitingForStair: Bool {
        guard status == .danger, let edge, let source = tiles[position] else { return false }
        let roads = source.exits(turns: turns[position, default: 0])
        return roads.contains(edge) && (entry.map { roads.contains($0) } ?? true)
            && level.hasBridge(position, toward: edge) && stairs[position.neighbor(edge)] != nil
    }

    var hasMovingStairs: Bool { !stairs.isEmpty }
    var needsUpdates: Bool { isRunning || (hasMovingStairs && !isFinished) }
    var isRunning: Bool { status == .traveling || status == .danger }
    var isFinished: Bool { status == .won || status == .fallen }

    init(level: Level) {
        self.level = level
        tiles = Dictionary(uniqueKeysWithValues: level.tiles.map { ($0.id, $0) })
        stairs = level.tiles.reduce(into: [:]) { $0[$1.id] = $1.stair }
        turns = level.tiles.reduce(into: [:]) { $0[$1.id] = $1.initialTurns }
        position = level.start.id
    }

    @discardableResult
    mutating func rotate(_ cell: Cell, at now: ContinuousClock.Instant) -> Bool {
        if isFinished || tiles[cell]?.isRotatable != true {
            return false
        } else if let fallDeadline, now >= fallDeadline {
            return false
        } else {
            turns[cell, default: 0] += 1
            moves += 1
            if status == .ready {
                status = .traveling
                nextStepAt = now
            }
            return true
        }
    }

    private var edgeTimeAllowance: Duration {
        max(.seconds(4), level.reactionTime * 2 + .milliseconds(1400 - momentum * 120))
    }

    mutating func brake(at now: ContinuousClock.Instant) -> Bool {
        guard isRunning, brakeAvailable, let nextStepAt else { return false }
        if let fallDeadline, now >= fallDeadline { return false }

        brakeAvailable = false
        momentum = 0
        if status == .danger {
            dangerWindow = edgeTimeAllowance + .seconds(1)
            fallDeadline = now + dangerWindow
        } else {
            self.nextStepAt = max(nextStepAt, now) + .milliseconds(700)
        }
        return true
    }

    func connects(_ cell: Cell, toward direction: Direction) -> Bool {
        let neighbor = cell.neighbor(direction)
        if level.hasBridge(cell, toward: direction), isDocked(cell), isDocked(neighbor),
           let source = tiles[cell], let destination = tiles[neighbor] {
            return source.exits(turns: turns[cell, default: 0]).contains(direction)
                && destination.exits(turns: turns[neighbor, default: 0]).contains(direction.opposite)
        } else {
            return false
        }
    }

    func hasThroughTrack(_ cell: Cell) -> Bool {
        guard let tile = tiles[cell] else { return false }
        let exits = tile.exits(turns: turns[cell, default: 0])
        return !exits.isEmpty && exits.allSatisfy { connects(cell, toward: $0) }
    }

    var openingRoute: Bridge? {
        guard status == .ready, level.showsOpeningRoute,
              let direction = connectedExit(from: position, enteredFrom: nil) else { return nil }
        return Bridge(position, position.neighbor(direction))
    }

    var upcomingFork: ForkPreview? {
        guard isRunning else { return nil }
        if let preview = previewFork(at: position, enteredFrom: entry) {
            return preview
        }
        guard let nextDirection = connectedExit(from: position, enteredFrom: entry) else { return nil }
        let next = position.neighbor(nextDirection)
        guard let source = tiles[position], let destination = tiles[next], destination.elevation <= source.elevation else { return nil }
        return previewFork(at: next, enteredFrom: nextDirection.opposite)
    }

    private func previewFork(at cell: Cell, enteredFrom entry: Direction?) -> ForkPreview? {
        guard tiles[cell]?.isFork == true else { return nil }
        return ForkPreview(cell: cell, preferred: connectedExit(from: cell, enteredFrom: entry))
    }

    private func connectedExit(from cell: Cell, enteredFrom entry: Direction?) -> Direction? {
        guard let tile = tiles[cell] else { return nil }
        let roads = tile.exits(turns: turns[cell, default: 0])
        guard entry.map({ roads.contains($0) }) ?? true,
              let exit = roads.first(where: { $0 != entry }),
              connects(cell, toward: exit) else { return nil }
        return exit
    }

    mutating func resume(after pause: Duration) {
        guard pause > .zero else { return }
        nextStepAt = nextStepAt.map { $0 + pause }
        fallDeadline = fallDeadline.map { $0 + pause }
        for cell in Array(schedules.keys) {
            if var schedule = schedules[cell] {
                schedule.nextTurn += pause
                schedule.settlesAt = schedule.settlesAt.map { $0 + pause }
                schedules[cell] = schedule
            }
        }
    }

    private func isDocked(_ cell: Cell) -> Bool {
        stairs[cell] == nil || (turns[cell, default: 0] == 0 && !swingingStairs.contains(cell))
    }

    @discardableResult
    mutating func update(at now: ContinuousClock.Instant) -> Bool {
        guard needsUpdates else { return false }
        let stairsChanged = updateStairs(at: now)
        guard isRunning, let nextStepAt, now >= nextStepAt else { return stairsChanged }

        let roads = tiles[position]?.exits(turns: turns[position, default: 0]) ?? []
        let alignedWithEntry = entry.map { roads.contains($0) } ?? true

        if let fallDeadline, now >= fallDeadline {
            status = .fallen
            failure = .drop
            self.fallDeadline = nil
        } else if position == level.goal.id {
            status = .won
        } else if let exit = connectedExit(from: position, enteredFrom: entry) {
            let destination = position.neighbor(exit)
            let difference = tiles[destination]!.elevation - tiles[position]!.elevation
            fallDeadline = nil
            if difference > 0 {
                status = .fallen
                failure = .uphill
                edge = exit
            } else {
                position = destination
                entry = exit.opposite
                status = .traveling
                edge = nil
                if difference < 0 {
                    momentum = min(momentum + 1, 3)
                } else {
                    momentum = max(momentum - 1, 0)
                }
                travelTime = .milliseconds(660 - momentum * 110 - (difference < 0 ? 65 : 0))
                self.nextStepAt = now + travelTime
            }
        } else if status != .danger {
            status = .danger
            let blockedExit = roads.first { $0 != entry }
            edge = alignedWithEntry ? (blockedExit ?? entry?.opposite) : entry?.opposite
            dangerWindow = edgeTimeAllowance
            fallDeadline = now + dangerWindow
        } else {
            return stairsChanged
        }
        return true
    }

    private mutating func updateStairs(at now: ContinuousClock.Instant) -> Bool {
        var changed = false
        for (cell, timing) in stairs {
            guard var schedule = schedules[cell] else {
                schedules[cell] = StairSchedule(nextTurn: now + timing.delay)
                changed = true
                continue
            }
            var advanced = false
            if let settled = schedule.settlesAt, now >= settled {
                schedule.settlesAt = nil
                swingingStairs.remove(cell)
                advanced = true
            }
            // Keep the landing in place while the core is on it.
            if now >= schedule.nextTurn, position != cell {
                turns[cell] = turns[cell, default: 0] == 0 ? 1 : 0
                schedule.settlesAt = now + StairTiming.swingDuration
                schedule.nextTurn = now + timing.interval
                swingingStairs.insert(cell)
                advanced = true
            }
            if advanced {
                schedules[cell] = schedule
                changed = true
            }
        }
        return changed
    }
}
