enum CoreForm: Int, CaseIterable {
    case crystal = 0
    case mars = 10
    case fire = 20

    static func unlocked(after clearedLevel: Int) -> Self {
        allCases.last { $0.rawValue <= clearedLevel } ?? .crystal
    }

    var title: String {
        switch self {
        case .crystal: "Crystal Marble"
        case .mars: "Mars"
        case .fire: "Fireball"
        }
    }

    var symbol: String {
        switch self {
        case .crystal: "diamond.fill"
        case .mars: "globe.americas.fill"
        case .fire: "flame.fill"
        }
    }

    var next: Self? {
        Self.allCases.first { $0.rawValue > rawValue }
    }
}
