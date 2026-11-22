struct TrackLine {
    static func points(for exits: [Direction], edge: Float) -> [SIMD2<Float>] {
        guard let first = exits.first else { return [] }
        let a = SIMD2(Float(first.dx), Float(first.dy))
        guard exits.count > 1 else { return [a * edge, .zero] }

        let second = exits[1]
        let b = SIMD2(Float(second.dx), Float(second.dy))
        if second == first.opposite { return [a * edge, b * edge] }

        let radius: Float = 0.20
        let tangent: Float = 0.55228475
        let start = a * radius
        let end = b * radius
        let startControl = start * (1 - tangent)
        let endControl = end * (1 - tangent)
        let curve = (0...12).map { step -> SIMD2<Float> in
            let t = Float(step) / 12
            let u = 1 - t
            return start * (u * u * u) + startControl * (3 * u * u * t)
                + endControl * (3 * u * t * t) + end * (t * t * t)
        }
        return [a * edge] + curve + [b * edge]
    }
}
