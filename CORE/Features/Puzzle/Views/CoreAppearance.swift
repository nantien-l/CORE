import SwiftUI

extension CoreForm {
    var tint: Color {
        switch self {
        case .crystal: Color(red: 0.70, green: 0.91, blue: 0.98)
        case .mars: Color(red: 0.99, green: 0.61, blue: 0.47)
        case .fire: Color(red: 1, green: 0.72, blue: 0.30)
        }
    }
}

#if os(iOS)
import SceneKit
import UIKit

extension CoreForm {
    func configure(_ sphere: SCNNode, corona: SCNNode) {
        sphere.childNodes.forEach { $0.removeFromParentNode() }
        corona.removeAllParticleSystems()

        guard let material = sphere.geometry?.firstMaterial else { return }
        material.lightingModel = .phong
        material.diffuse.contents = UIColor(tint)
        material.specular.contents = UIColor.white
        material.shininess = 0.75
        material.transparency = 1
        material.emission.contents = UIColor.black

        switch self {
        case .crystal:
            material.transparency = 0.84
            material.emission.contents = UIColor(red: 0.04, green: 0.15, blue: 0.18, alpha: 1)
            let inner = SCNSphere(radius: 0.105)
            inner.isGeodesic = true
            inner.segmentCount = 12
            inner.firstMaterial?.diffuse.contents = UIColor(red: 0.27, green: 0.63, blue: 0.74, alpha: 1)
            let node = SCNNode(geometry: inner)
            node.categoryBitMask = 2
            sphere.addChildNode(node)
        case .mars:
            material.diffuse.contents = Self.marsTexture
            material.shininess = 0.14
            material.specular.contents = UIColor(white: 0.19, alpha: 1)
        case .fire:
            material.diffuse.contents = Self.fireTexture
            material.emission.contents = Self.fireTexture
            material.emission.intensity = 0.43
            let sparks = SCNParticleSystem()
            sparks.birthRate = 42
            sparks.particleLifeSpan = 0.32
            sparks.particleLifeSpanVariation = 0.12
            sparks.particleSize = 0.061
            sparks.particleSizeVariation = 0.034
            sparks.particleVelocity = 0.19
            sparks.particleVelocityVariation = 0.14
            sparks.emitterShape = SCNSphere(radius: 0.16)
            sparks.spreadingAngle = 135
            sparks.particleColor = UIColor(red: 1, green: 0.43, blue: 0.10, alpha: 0.85)
            sparks.blendMode = .additive
            sparks.particleImage = Self.sparkTexture
            corona.addParticleSystem(sparks)
        }
    }

    private static let marsTexture = makeTexture(fire: false)
    private static let fireTexture = makeTexture(fire: true)

    private static let sparkTexture: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
        let colors = [UIColor.white.cgColor, UIColor.clear.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            let center = CGPoint(x: 16, y: 16)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                                 endCenter: center, endRadius: 16, options: [])
        }
    }

    private static func makeTexture(fire: Bool) -> UIImage {
        let size = CGSize(width: 256, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            (fire ? UIColor(red: 0.87, green: 0.19, blue: 0.035, alpha: 1)
                  : UIColor(red: 0.75, green: 0.28, blue: 0.17, alpha: 1)).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for index in 0..<420 {
                let x = CGFloat((index * 73 + index * index * 11) % 256)
                let y = CGFloat((index * 31 + index * index * 3) % 128)
                let radius = CGFloat(2 + (index * 7) % 9)
                let shade = index.isMultiple(of: 3)
                    ? UIColor(red: 0.28, green: 0.06, blue: 0.06, alpha: fire ? 0.22 : 0.41)
                    : UIColor(red: 1, green: fire ? 0.73 : 0.53, blue: fire ? 0.22 : 0.29, alpha: 0.43)
                context.cgContext.setFillColor(shade.cgColor)
                for shift in [-size.width, 0, size.width] {
                    context.cgContext.fillEllipse(in: CGRect(x: x + shift - radius, y: y - radius / 2,
                                                            width: radius * 2, height: radius))
                }
            }
        }
    }
}
#endif
