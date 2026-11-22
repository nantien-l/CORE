#if os(iOS)
import SceneKit
import SwiftUI
import UIKit

struct SpatialBoard: UIViewRepresentable {
    let engine: PuzzleEngine
    let form: CoreForm
    let cameraReset: Int
    let reduceMotion: Bool
    let paused: Bool
    let onRotate: (Cell) -> Void

    func makeCoordinator() -> BoardScene {
        BoardScene(level: engine.level)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.accessibilityElementsHidden = true
        let board = context.coordinator
        let tap = UITapGestureRecognizer(target: board, action: #selector(BoardScene.tap(_:)))
        let orbit = UIPanGestureRecognizer(target: board, action: #selector(BoardScene.drag(_:)))
        orbit.maximumNumberOfTouches = 1
        let pan = UIPanGestureRecognizer(target: board, action: #selector(BoardScene.pan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: board, action: #selector(BoardScene.pinch(_:)))
        tap.require(toFail: orbit)
        tap.require(toFail: pan)
        tap.require(toFail: pinch)
        for recognizer in [tap, orbit, pan, pinch] as [UIGestureRecognizer] {
            recognizer.delegate = board
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let board = context.coordinator
        board.scene.isPaused = paused
        board.onRotate = engine.isFinished || paused ? nil : onRotate
        board.update(engine, form: form, cameraReset: cameraReset, reduceMotion: reduceMotion)
    }
}

@MainActor
final class BoardScene: NSObject, UIGestureRecognizerDelegate {
    private enum Metrics {
        static let spacing: Float = 1.42
        static let surface: Float = 0.96
        static let height: Float = 0.42
        static let coreRadius: Float = 0.16
    }

    let scene = SCNScene()
    let camera = SCNNode()
    var onRotate: ((Cell) -> Void)?

    private let orbit = SCNNode()
    private let core = SCNNode()
    private let sphere = SCNNode()
    private let corona = SCNNode()
    private let finishEffect = SCNNode()
    private var currentForm: CoreForm?
    private let tiles: [Cell: Tile]
    private var platforms: [Cell: SCNNode] = [:]
    private var trackLights: [Cell: SCNNode] = [:]
    private var tapTargets: [String: Cell] = [:]
    private var bridges: [(cell: Cell, direction: Direction, stripe: SCNNode)] = []
    private var previous: PuzzleEngine?
    private var lastCameraReset = 0
    private var cameraDistance: Float = 1
    private let defaultZoom: Float
    private var zoom: Float = 1
    private var yaw: Float = .pi / 4
    private var pitch: Float = 0.81
    private var boardCenter = SCNVector3Zero

    init(level: Level) {
        tiles = Dictionary(uniqueKeysWithValues: level.tiles.map { ($0.id, $0) })
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        defaultZoom = level.showsOpeningRoute ? (isPad ? 1.04 : 0.83) : (isPad ? 1.22 : 1)
        super.init()

        configureCamera(level)
        configureLighting()
        for tile in level.tiles {
            addPlatform(tile)
            for direction in [Direction.east, .south] {
                if level.hasBridge(tile.id, toward: direction), let neighbor = tiles[tile.id.neighbor(direction)] {
                    addBridge(from: tile, to: neighbor, toward: direction)
                }
            }
        }
        addCore(at: level.start.id)
    }

    func update(_ engine: PuzzleEngine, form: CoreForm, cameraReset: Int, reduceMotion: Bool) {
        let old = previous
        previous = engine
        if currentForm != form {
            form.configure(sphere, corona: corona)
            currentForm = form
        }
        if old?.turns != engine.turns {
            for (cell, platform) in platforms where old?.turns[cell] != engine.turns[cell] {
                let turns = engine.turns[cell, default: 0]
                SCNTransaction.begin()
                let swinging = engine.swingingStairs.contains(cell)
                let duration = StairTiming.swingDuration / .seconds(1)
                SCNTransaction.animationDuration = old == nil || reduceMotion ? 0 : (swinging ? duration : 0.19)
                platform.eulerAngles.y = -Float(turns) * .pi / 2
                SCNTransaction.commit()
                if swinging && !reduceMotion {
                    platform.runAction(.sequence([
                        .move(to: SCNVector3(0, 0.075, 0), duration: duration / 2),
                        .move(to: SCNVector3Zero, duration: duration / 2)
                    ]), forKey: "stair-swing")
                }
            }
        }
        if old?.turns != engine.turns || old?.swingingStairs != engine.swingingStairs {
            for (cell, track) in trackLights {
                let lit = engine.hasThroughTrack(cell)
                if old?.hasThroughTrack(cell) != lit {
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = old == nil || reduceMotion ? 0 : 0.16
                    track.opacity = lit ? 1 : 0
                    SCNTransaction.commit()
                }
            }
        }
        if old?.turns != engine.turns || old?.status != engine.status
            || old?.position != engine.position || old?.swingingStairs != engine.swingingStairs {
            updateRouteColors(engine, previous: old, reduceMotion: reduceMotion)
        }

        if lastCameraReset != cameraReset {
            lastCameraReset = cameraReset
            SCNTransaction.begin()
            SCNTransaction.animationDuration = reduceMotion ? 0 : 0.35
            zoom = defaultZoom
            yaw = .pi / 4
            pitch = 0.81
            orbit.position = boardCenter
            positionCamera()
            SCNTransaction.commit()
        }

        if let old, engine.status == .ready && old.status != .ready {
            core.removeAllActions()
            sphere.removeAllActions()
            finishEffect.childNodes.forEach { $0.removeFromParentNode() }
            core.position = ballPoint(engine.position)
            core.opacity = 1
            core.scale = SCNVector3(1, 1, 1)
            sphere.eulerAngles = SCNVector3Zero
        } else if let old, old.position != engine.position || old.status != engine.status || old.edge != engine.edge {
            animateCore(from: old, to: engine, reduceMotion: reduceMotion)
        }
    }

    private func updateRouteColors(_ engine: PuzzleEngine, previous: PuzzleEngine?, reduceMotion: Bool) {
        let preview = engine.upcomingFork
        let oldPreview = previous?.upcomingFork
        let nearFork = preview?.cell == engine.position
        let enteringFork = nearFork && previous?.position != engine.position
        let changedDirection = preview != oldPreview
        let preferred = preview.flatMap { fork in fork.preferred.map { Bridge(fork.cell, fork.cell.neighbor($0)) } }
            ?? engine.openingRoute
        let failedBridge = engine.failure == .uphill ? engine.edge.map { Bridge(engine.position, engine.position.neighbor($0)) } : nil

        for bridge in bridges {
            let key = Bridge(bridge.cell, bridge.cell.neighbor(bridge.direction))
            guard let material = bridge.stripe.geometry?.firstMaterial else { continue }
            if key == failedBridge {
                material.diffuse.contents = UIColor(PuzzlePalette.warning)
                material.emission.contents = UIColor(red: 0.34, green: 0.10, blue: 0.04, alpha: 1)
            } else if key == preferred {
                material.diffuse.contents = UIColor(PuzzlePalette.start)
                material.emission.contents = UIColor(red: 0.19, green: 0.52, blue: 0.68, alpha: 1)
                if !reduceMotion && nearFork && (enteringFork || changedDirection) {
                    bridge.stripe.runAction(.sequence([
                        .fadeOpacity(to: 0.46, duration: 0.09), .fadeOpacity(to: 1, duration: 0.12)
                    ]), forKey: "fork-pulse")
                }
                continue
            } else {
                let connected = engine.connects(bridge.cell, toward: bridge.direction)
                material.diffuse.contents = connected ? UIColor(red: 0.70, green: 0.82, blue: 0.56, alpha: 1) : UIColor(white: 0.18, alpha: 1)
                material.emission.contents = UIColor.black
            }

            if bridge.stripe.action(forKey: "fork-pulse") != nil {
                bridge.stripe.removeAction(forKey: "fork-pulse")
                bridge.stripe.opacity = 1
            }
        }
    }

    @objc func tap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view as? SCNView else { return }
        let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .categoryBitMask: 1])
        var node = hits.first?.node
        while let candidate = node {
            if let name = candidate.name, let cell = tapTargets[name] {
                onRotate?(cell)
                return
            }
            node = candidate.parent
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer.view === other.view else { return false }
        return (gestureRecognizer is UIPinchGestureRecognizer && (other as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2)
            || (other is UIPinchGestureRecognizer && (gestureRecognizer as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2)
    }

    @objc func drag(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed, gesture.numberOfTouches == 1 else { return }
        let delta = gesture.translation(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
        yaw = (yaw - Float(delta.x) * 0.009).truncatingRemainder(dividingBy: 2 * .pi)
        pitch = min(1.48, max(0.30, pitch + Float(delta.y) * 0.007))
        positionCamera()
    }

    @objc func pan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed, let view = gesture.view else { return }
        let delta = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)
        let transform = camera.worldTransform
        let scale = (cameraDistance / zoom) * 0.70 / Float(max(1, view.bounds.height))
        let x = -Float(delta.x) * scale
        let y = Float(delta.y) * scale
        let current = orbit.position
        let limit = cameraDistance * 0.75
        func clamp(_ value: Float, around center: Float) -> Float {
            min(center + limit, max(center - limit, value))
        }
        orbit.position = SCNVector3(
            clamp(current.x + transform.m11 * x + transform.m21 * y, around: boardCenter.x),
            clamp(current.y + transform.m12 * x + transform.m22 * y, around: boardCenter.y),
            clamp(current.z + transform.m13 * x + transform.m23 * y, around: boardCenter.z)
        )
    }

    @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        zoom = min(3.4, max(0.64, zoom * Float(gesture.scale)))
        gesture.scale = 1
        positionCamera()
    }

    private func configureCamera(_ level: Level) {
        let xs = level.tiles.map { Float($0.id.x) * Metrics.spacing }
        let zs = level.tiles.map { Float($0.id.y) * Metrics.spacing }
        let ys = level.tiles.map { Float($0.elevation) * Metrics.height }
        let width = (xs.max()! - xs.min()!) + 1.2
        let depth = (zs.max()! - zs.min()!) + 1.2
        let height = (ys.max()! - ys.min()!) + 0.65
        boardCenter = SCNVector3((xs.max()! + xs.min()!) / 2, (ys.max()! + ys.min()!) / 2, (zs.max()! + zs.min()!) / 2)
        orbit.position = boardCenter
        zoom = defaultZoom
        cameraDistance = max(6, sqrt(width * width + depth * depth) * 1.45 + height * 0.65)
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 39
        camera.camera?.zFar = 150
        orbit.addChildNode(camera)
        scene.rootNode.addChildNode(orbit)
        positionCamera()
    }

    private func positionCamera() {
        let distance = cameraDistance / zoom
        orbit.eulerAngles.y = yaw
        camera.position = SCNVector3(0, distance * sin(pitch), distance * cos(pitch))
        camera.eulerAngles.x = -pitch
    }

    private func configureLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 540
        ambient.light?.color = UIColor(red: 0.72, green: 0.79, blue: 0.86, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1150
        key.light?.color = UIColor(red: 1, green: 0.91, blue: 0.77, alpha: 1)
        key.eulerAngles = SCNVector3(-0.85, -0.65, 0)
        scene.rootNode.addChildNode(key)
    }

    private func addPlatform(_ tile: Tile) {
        let anchor = SCNNode()
        anchor.position = point(tile.id)
        scene.rootNode.addChildNode(anchor)
        let spinner = SCNNode()
        anchor.addChildNode(spinner)
        platforms[tile.id] = spinner
        if tile.isRotatable {
            let name = "tile/\(tile.id.x)/\(tile.id.y)"
            anchor.name = name
            tapTargets[name] = tile.id
        }

        let width = CGFloat(Metrics.surface)
        let stone: UIColor
        switch tile.role {
        case .start: stone = UIColor(red: 0.47, green: 0.69, blue: 0.78, alpha: 1)
        case .goal: stone = UIColor(red: 0.82, green: 0.65, blue: 0.37, alpha: 1)
        case .fixture, .platform:
            stone = tile.stair == nil ? UIColor(red: 0.93, green: 0.88, blue: 0.77, alpha: 1) : UIColor(PuzzlePalette.stair)
        }
        let baseHeight: CGFloat = tile.role == .fixture ? 0.22 : 0.31
        let base = box(width, baseHeight, width, chamfer: 0.035, color: UIColor(white: 0.27, alpha: 1))
        base.position.y = -Float(baseHeight / 2) - 0.01
        spinner.addChildNode(base)
        let surface = box(width, 0.07, width, chamfer: 0.025, color: stone)
        surface.position.y = -0.025
        spinner.addChildNode(surface)

        let centerline = TrackLine.points(for: tile.roads, edge: Metrics.surface / 2)
        spinner.addChildNode(trackRibbon(along: centerline, width: 0.16, elevation: 0.016, color: UIColor(white: 0.10, alpha: 1)))
        let light = trackRibbon(along: centerline, width: 0.095, elevation: 0.018,
                                color: UIColor(red: 0.72, green: 0.86, blue: 0.57, alpha: 1))
        light.opacity = 0
        spinner.addChildNode(light)
        trackLights[tile.id] = light

        if tile.stair != nil { addTreads(to: spinner, roads: tile.roads) }

        if tile.role == .start || tile.role == .goal {
            let goal = tile.role == .goal
            let markerColor = UIColor(goal ? PuzzlePalette.goal : PuzzlePalette.start)
            let marker = box(0.31, 0.032, 0.31, chamfer: 0.025, color: markerColor)
            marker.position.y = 0.04
            anchor.addChildNode(marker)
            anchor.addChildNode(floatingLabel(goal ? "GOAL" : "START", color: markerColor))
        }
    }

    private func trackRibbon(along points: [SIMD2<Float>], width: Float, elevation: Float, color: UIColor) -> SCNNode {
        guard points.count >= 2 else { return SCNNode() }
        var vertices: [SCNVector3] = []
        var indices: [UInt16] = []
        for (index, point) in points.enumerated() {
            let tangent = points[min(index + 1, points.count - 1)] - points[max(index - 1, 0)]
            let length = hypot(tangent.x, tangent.y)
            let normal = SIMD2(-tangent.y, tangent.x) * (width / (2 * length))
            let left = point + normal
            let right = point - normal
            vertices.append(SCNVector3(left.x, elevation, left.y))
            vertices.append(SCNVector3(right.x, elevation, right.y))
            if index > 0 {
                let end = UInt16(index * 2)
                indices += [end - 2, end - 1, end, end, end - 1, end + 1]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func addTreads(to platform: SCNNode, roads: [Direction]) {
        for direction in roads {
            for step in 1...3 {
                let tread = box(0.18, 0.016, 0.025, chamfer: 0.003,
                                color: UIColor(red: 0.83, green: 0.77, blue: 1, alpha: 1))
                let offset = Float(step) * 0.10
                tread.position = SCNVector3(Float(direction.dx) * offset, 0.030, Float(direction.dy) * offset)
                if direction.dx != 0 { tread.eulerAngles.y = .pi / 2 }
                platform.addChildNode(tread)
            }
        }
    }

    private func floatingLabel(_ title: String, color: UIColor) -> SCNNode {
        let text = SCNText(string: title, extrusionDepth: 0)
        text.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        text.materials = [material]

        let label = SCNNode(geometry: text)
        let limits = label.boundingBox
        let scale: Float = 0.012
        let caption = SCNNode()
        caption.position.y = 0.54
        caption.constraints = [SCNBillboardConstraint()]
        label.pivot = SCNMatrix4MakeTranslation((limits.min.x + limits.max.x) / 2, (limits.min.y + limits.max.y) / 2, 0)
        label.scale = SCNVector3(scale, scale, scale)
        label.position.z = 0.004
        let plate = SCNPlane(width: CGFloat((limits.max.x - limits.min.x) * scale + 0.07),
                             height: CGFloat((limits.max.y - limits.min.y) * scale + 0.05))
        plate.cornerRadius = 0.023
        plate.firstMaterial?.diffuse.contents = UIColor(white: 0.075, alpha: 1)
        plate.firstMaterial?.lightingModel = .constant
        plate.firstMaterial?.isDoubleSided = true
        caption.addChildNode(SCNNode(geometry: plate))
        caption.addChildNode(label)
        return caption
    }

    private func addBridge(from source: Tile, to destination: Tile, toward direction: Direction) {
        let first = point(source.id, toward: direction, distance: Metrics.surface / 2)
        let last = point(destination.id, toward: direction.opposite, distance: Metrics.surface / 2)
        let vertical = last.y - first.y
        let horizontal = Metrics.spacing - Metrics.surface
        let length = CGFloat(hypot(vertical, horizontal))
        let bridge = SCNNode()
        bridge.position = SCNVector3((first.x + last.x) / 2, (first.y + last.y) / 2, (first.z + last.z) / 2)
        let heading = SCNNode()
        heading.eulerAngles.y = direction == .east ? .pi / 2 : 0
        bridge.addChildNode(heading)
        let incline = SCNNode()
        incline.eulerAngles.x = -atan2(vertical, horizontal)
        heading.addChildNode(incline)
        let paint = vertical == 0 ? UIColor(white: 0.34, alpha: 1) : UIColor(red: 0.56, green: 0.42, blue: 0.25, alpha: 1)
        let deck = box(0.40, 0.078, length, chamfer: 0.013, color: paint)
        deck.position.y = -0.035
        incline.addChildNode(deck)
        let stripe = box(0.095, 0.014, length, chamfer: 0.004, color: .darkGray)
        stripe.position.y = 0.013
        incline.addChildNode(stripe)
        if vertical != 0 {
            for side in [-1.0, 1.0] {
                let rail = box(0.023, 0.026, length * 0.93, chamfer: 0.006,
                               color: UIColor(red: 0.83, green: 0.66, blue: 0.43, alpha: 1))
                rail.position = SCNVector3(Float(side) * 0.174, 0.022, 0)
                incline.addChildNode(rail)
            }
        }
        bridges.append((source.id, direction, stripe))
        scene.rootNode.addChildNode(bridge)
    }

    private func addCore(at cell: Cell) {
        let ball = SCNSphere(radius: CGFloat(Metrics.coreRadius))
        ball.segmentCount = 32
        sphere.geometry = ball
        sphere.categoryBitMask = 2
        core.addChildNode(sphere)
        core.addChildNode(corona)
        core.position = ballPoint(cell)
        scene.rootNode.addChildNode(core)
        scene.rootNode.addChildNode(finishEffect)
    }

    private func animateCore(from old: PuzzleEngine, to engine: PuzzleEngine, reduceMotion: Bool) {
        core.removeAllActions()
        sphere.removeAllActions()
        let cell = engine.position
        if engine.status == .fallen, let edge = engine.edge {
            if reduceMotion {
                core.opacity = 0
            } else if engine.failure == .uphill {
                var stop = ballPoint(cell, toward: edge, distance: 0.62)
                stop.y += 0.22
                core.runAction(.sequence([
                    .move(to: stop, duration: 0.19),
                    .group([.move(to: ballPoint(cell), duration: 0.30), .fadeOut(duration: 0.30)])
                ]))
            } else {
                var drop = ballPoint(cell, toward: edge, distance: 0.90)
                drop.y -= 0.72
                core.runAction(.group([.move(to: drop, duration: 0.48), .fadeOut(duration: 0.48)]))
            }
        } else if cell != old.position, let direction = engine.entry?.opposite {
            let duration = (engine.travelTime / .seconds(1)) * 0.82
            if reduceMotion {
                core.position = ballPoint(cell)
            } else {
                let edgeDistance = Metrics.surface / 2
                core.runAction(.sequence([
                    .move(to: ballPoint(old.position, toward: direction, distance: edgeDistance), duration: duration * 0.32),
                    .move(to: ballPoint(cell, toward: direction.opposite, distance: edgeDistance), duration: duration * 0.36),
                    .move(to: ballPoint(cell), duration: duration * 0.32)
                ]))
                sphere.runAction(.rotate(by: CGFloat(Metrics.spacing / Metrics.coreRadius),
                                         around: SCNVector3(Float(direction.dy), 0, -Float(direction.dx)), duration: duration))
            }
        } else if engine.status == .danger, let edge = engine.edge {
            core.runAction(.move(to: ballPoint(cell, toward: edge, distance: 0.37), duration: reduceMotion ? 0 : 0.20))
        } else if engine.status == .won, !reduceMotion {
            core.runAction(.sequence([.scale(to: 1.30, duration: 0.18), .scale(to: 1, duration: 0.30)]))
            celebrate(at: cell)
        }
    }

    private func celebrate(at cell: Cell) {
        finishEffect.position = point(cell)
        for index in 0..<2 {
            let geometry = SCNTorus(ringRadius: 0.34, pipeRadius: 0.018)
            geometry.firstMaterial?.diffuse.contents = UIColor(PuzzlePalette.goal)
            geometry.firstMaterial?.lightingModel = .constant
            let ring = SCNNode(geometry: geometry)
            ring.position.y = 0.065 + Float(index) * 0.05
            ring.categoryBitMask = 2
            ring.opacity = 0
            finishEffect.addChildNode(ring)
            ring.runAction(.sequence([
                .wait(duration: Double(index) * 0.13),
                .fadeIn(duration: 0.09),
                .group([.scale(to: 2.5, duration: 0.65), .fadeOut(duration: 0.65)]),
                .removeFromParentNode()
            ]))
        }
    }

    private func point(_ cell: Cell, toward direction: Direction? = nil, distance: Float = 0) -> SCNVector3 {
        SCNVector3(Float(cell.x) * Metrics.spacing + Float(direction?.dx ?? 0) * distance,
                   Float(tiles[cell]!.elevation) * Metrics.height,
                   Float(cell.y) * Metrics.spacing + Float(direction?.dy ?? 0) * distance)
    }

    private func ballPoint(_ cell: Cell, toward direction: Direction? = nil, distance: Float = 0) -> SCNVector3 {
        var result = point(cell, toward: direction, distance: distance)
        result.y += Metrics.coreRadius + 0.021
        return result
    }

    private func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, chamfer: CGFloat, color: UIColor) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: chamfer)
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.specular.contents = UIColor(white: 0.22, alpha: 1)
        return SCNNode(geometry: geometry)
    }
}
#endif
