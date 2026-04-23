//
//  SceneView3D.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI
import SceneKit

struct SceneView3D: UIViewRepresentable {
    @Binding var rotationX: Double    // pitch (up/down)
    @Binding var rotationY: Double    // yaw (left/right)
    @Binding var rotationZ: Double    // roll (tilt left/right)
    let usdzFileName: String
    let ledColor: UIColor
    let ledIntensity: Double
    var gesturesEnabled: Bool = true
    var smoothRotation: Bool = false
    var idleWobble: Bool = false
    var wobbleIntensity: Double = 1.0
    var liveQuaternion: SCNVector4? = nil
    var onTap: (() -> Void)? = nil

    // MARK: - Scene & Texture Cache
    private static var cachedNormalMap: UIImage?
    private static var cachedRoughnessMap: UIImage?
    private static var cachedUsdzNodes: [SCNNode]?
    private static var cachedUsdzFileName: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = createScene()
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false
        sceneView.backgroundColor = .clear

        let root = sceneView.scene!.rootNode

        // Low ambient so shadows stay dramatic
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 40
        ambientLight.light?.color = UIColor(white: 0.5, alpha: 1.0)
        root.addChildNode(ambientLight)

        // Key light — strong, from upper-right side
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1200
        keyLight.light?.color = UIColor(white: 0.95, alpha: 1.0)
        keyLight.light?.castsShadow = true
        keyLight.light?.shadowRadius = 3
        keyLight.light?.shadowSampleCount = 8
        keyLight.eulerAngles = SCNVector3(-0.5, 0.8, 0)
        root.addChildNode(keyLight)

        // Fill light — softer, from lower-left to reveal detail without flattening
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 400
        fillLight.light?.color = UIColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1.0)
        fillLight.eulerAngles = SCNVector3(0.3, -0.7, 0)
        root.addChildNode(fillLight)

        // Rim light — from behind to outline edges
        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .directional
        rimLight.light?.intensity = 600
        rimLight.light?.color = UIColor(white: 0.9, alpha: 1.0)
        rimLight.eulerAngles = SCNVector3(-0.2, Float.pi, 0)
        root.addChildNode(rimLight)

        context.coordinator.modelNode = sceneView.scene?.rootNode.childNode(withName: "model", recursively: true)

        if let model = context.coordinator.modelNode {
            let (min, max) = model.boundingBox
            let centerY = (min.y + max.y) / 2.0
            model.pivot = SCNMatrix4MakeTranslation(0, centerY, 0)
        }

        context.coordinator.sceneView = sceneView

        // Add gesture recognizers — only begin when touching the 3D model
        if gesturesEnabled {
            let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            panGesture.delegate = context.coordinator
            sceneView.addGestureRecognizer(panGesture)
        }

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        sceneView.addGestureRecognizer(tapGesture)

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        context.coordinator.parent = self

        guard let model = context.coordinator.modelNode else { return }

        if !context.coordinator.hasSearchedForLED {
            context.coordinator.hasSearchedForLED = true
            searchForLED(in: model, coordinator: context.coordinator)
        }

        // Manage idle wobble state
        if idleWobble && !context.coordinator.isWobbling {
            context.coordinator.startWobble()
        } else if !idleWobble && context.coordinator.isWobbling {
            context.coordinator.stopWobble()
        }

        // Only set rotation from bindings when not wobbling
        if !context.coordinator.isWobbling {
            if let q = liveQuaternion {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.15
                model.orientation = SCNQuaternion(q.x, q.y, q.z, q.w)
                SCNTransaction.commit()
            } else {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = smoothRotation ? 0.5 : 0
                model.eulerAngles = SCNVector3(
                    Float(rotationX),
                    Float(rotationY),
                    Float(rotationZ)
                )
                SCNTransaction.commit()
            }
        }

        if let ledNode = context.coordinator.ledNode {
            updateLED(node: ledNode, color: ledColor, intensity: ledIntensity)
        }
    }

    private func searchForLED(in rootNode: SCNNode, coordinator: Coordinator) {
        // The USDZ export flattened all body names to "empty_N".
        // "empty_4" is the LED lens: 100-face circle, r≈0.55, centered on the front face.
        // Fall back to any node whose name contains "LED" in case the model is re-exported
        // with names intact.
        var allNodes: [String] = []

        rootNode.enumerateHierarchy { (childNode, _) in
            if let name = childNode.name {
                allNodes.append(name)
                if name == "empty_4" || name.uppercased().contains("LED") || name.uppercased().contains("LIGHT") {
                    if coordinator.ledNode == nil {
                        coordinator.ledNode = childNode
                        print("✅ LED node found: \(name)")
                    }
                }
            }
        }

        print("🔍 All scene nodes: \(allNodes.joined(separator: ", "))")
        if coordinator.ledNode == nil {
            print("❌ LED node not found in scene")
        }
    }

    private func updateLED(node: SCNNode, color: UIColor, intensity: Double) {
        guard let material = node.geometry?.firstMaterial else { return }

        if intensity > 0.0 {
            let brightness = CGFloat(intensity)

            // Subtle glow on the lens surface only
            material.emission.contents = color
            material.emission.intensity = brightness * 2.5
            material.diffuse.contents = color
            // Single-sided: emission visible only on the front face (normal pointing toward camera)
            material.isDoubleSided = false

            if node.childNode(withName: "ledLight", recursively: false) == nil {
                let lightNode = SCNNode()
                lightNode.name = "ledLight"
                lightNode.light = SCNLight()
                lightNode.light?.type = .spot
                // Cone: 25° inner (bright core), 55° outer (soft falloff)
                lightNode.light?.spotInnerAngle = 25
                lightNode.light?.spotOuterAngle = 55
                // Default SceneKit light aims in -Z; rotate 180° around X to aim in +Z (toward camera)
                lightNode.eulerAngles = SCNVector3(Float.pi, 0, 0)

                let (min, max) = node.boundingBox
                lightNode.position = SCNVector3(
                    (min.x + max.x) / 2,
                    (min.y + max.y) / 2,
                    (min.z + max.z) / 2
                )
                lightNode.light?.attenuationStartDistance = 0.3
                lightNode.light?.attenuationEndDistance = 2.5
                node.addChildNode(lightNode)
            }

            if let lightNode = node.childNode(withName: "ledLight", recursively: false) {
                lightNode.light?.intensity = CGFloat(intensity * 12)
                lightNode.light?.color = color
            }

        } else {
            material.emission.contents = UIColor.darkGray
            material.emission.intensity = 0.0
            material.diffuse.contents = UIColor.darkGray
            material.isDoubleSided = false

            if let lightNode = node.childNode(withName: "ledLight", recursively: false) {
                lightNode.light?.intensity = 0
            }
        }
    }

    private func createScene() -> SCNScene {
        let scene = SCNScene()

        // Load USDZ nodes once, then clone for each instance
        if Self.cachedUsdzNodes == nil || Self.cachedUsdzFileName != usdzFileName {
            if let usdzURL = Bundle.main.url(forResource: usdzFileName, withExtension: "usdz"),
               let usdzScene = try? SCNScene(url: usdzURL, options: nil) {
                Self.cachedUsdzNodes = usdzScene.rootNode.childNodes.map { $0 }
                Self.cachedUsdzFileName = usdzFileName
            }
        }

        if let cachedNodes = Self.cachedUsdzNodes {
            let modelNode = SCNNode()
            modelNode.name = "model"

            for child in cachedNodes {
                modelNode.addChildNode(child.clone())
            }

            modelNode.scale = SCNVector3(0.07, 0.07, 0.07)
            modelNode.position = SCNVector3(0, 0, 0)

            applyPlasticMaterial(to: modelNode)

            scene.rootNode.addChildNode(modelNode)
        } else {
            addFallbackCube(to: scene)
        }

        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 8)
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    // MARK: - Plastic Material

    /// Applies a plastic-like finish to all materials in the node hierarchy.
    /// Switches to physically-based shading with slight roughness and a subtle
    /// procedural normal map so the surface looks like real injection-moulded plastic
    /// instead of perfectly smooth CG.
    private func applyPlasticMaterial(to node: SCNNode) {
        if Self.cachedNormalMap == nil {
            Self.cachedNormalMap = generateGrainNormalMap(size: 512, scale: 6, strength: 0.6)
        }
        if Self.cachedRoughnessMap == nil {
            Self.cachedRoughnessMap = generateRoughnessMap(size: 512, scale: 6)
        }
        let normalMap = Self.cachedNormalMap!
        let roughnessMap = Self.cachedRoughnessMap!

        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry else { return }
            // Skip the LED node so we don't clobber its emission material
            let name = child.name ?? ""
            if name == "empty_4" || name.uppercased().contains("LED") || name.uppercased().contains("LIGHT") { return }

            for material in geometry.materials {
                material.lightingModel = .physicallyBased
                material.diffuse.contents = UIColor(white: 0.08, alpha: 1.0)
                material.roughness.contents = roughnessMap   // varied matte texture
                material.metalness.contents = 0.0
                material.fresnelExponent = 1.0

                material.normal.contents = normalMap
                material.normal.intensity = 0.8              // strong visible grain

                // Tiling so the texture repeats and grain is fine
                material.normal.wrapS = .repeat
                material.normal.wrapT = .repeat
                material.roughness.wrapS = .repeat
                material.roughness.wrapT = .repeat
                let tiling = SCNMatrix4MakeScale(4, 4, 1)    // tile 4x for finer grain
                material.normal.contentsTransform = tiling
                material.roughness.contentsTransform = tiling
            }
        }
    }

    /// Value noise with smooth interpolation — produces visible bumps at a controllable scale.
    private func generateGrainNormalMap(size: Int, scale: Int, strength: Float) -> UIImage {
        // Generate a grid of random values for value noise
        let gridSize = scale + 1
        var grid = [[Float]](repeating: [Float](repeating: 0, count: gridSize), count: gridSize)
        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                grid[gy][gx] = Float.random(in: 0...1)
            }
        }

        func smoothstep(_ t: Float) -> Float { t * t * (3 - 2 * t) }

        func sampleNoise(x: Float, y: Float) -> Float {
            let gx = x * Float(scale) / Float(size)
            let gy = y * Float(scale) / Float(size)
            let x0 = Int(gx) % scale
            let y0 = Int(gy) % scale
            let x1 = (x0 + 1) % gridSize
            let y1 = (y0 + 1) % gridSize
            let fx = smoothstep(gx - Float(Int(gx)))
            let fy = smoothstep(gy - Float(Int(gy)))
            let top = grid[y0][x0] * (1 - fx) + grid[y0][x1] * fx
            let bot = grid[y1][x0] * (1 - fx) + grid[y1][x1] * fx
            return top * (1 - fy) + bot * fy
        }

        // Build a height field, then derive normals from it
        var heights = [Float](repeating: 0, count: size * size)
        // Layer multiple octaves for richer detail
        let octaves: [(scale: Int, weight: Float)] = [
            (scale, 0.5), (scale * 3, 0.3), (scale * 7, 0.2)
        ]
        for oct in octaves {
            var octGrid = [[Float]](repeating: [Float](repeating: 0, count: oct.scale + 1), count: oct.scale + 1)
            for gy in 0...(oct.scale) { for gx in 0...(oct.scale) { octGrid[gy][gx] = Float.random(in: 0...1) } }

            for y in 0..<size {
                for x in 0..<size {
                    let gx = Float(x) * Float(oct.scale) / Float(size)
                    let gy = Float(y) * Float(oct.scale) / Float(size)
                    let x0 = Int(gx) % oct.scale
                    let y0 = Int(gy) % oct.scale
                    let x1 = (x0 + 1) % (oct.scale + 1)
                    let y1 = (y0 + 1) % (oct.scale + 1)
                    let fx = smoothstep(gx - Float(Int(gx)))
                    let fy = smoothstep(gy - Float(Int(gy)))
                    let top = octGrid[y0][x0] * (1 - fx) + octGrid[y0][x1] * fx
                    let bot = octGrid[y1][x0] * (1 - fx) + octGrid[y1][x1] * fx
                    heights[y * size + x] += (top * (1 - fy) + bot * fy) * oct.weight
                }
            }
        }

        // Convert height field to normal map via finite differences
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let left  = heights[y * size + ((x - 1 + size) % size)]
                let right = heights[y * size + ((x + 1) % size)]
                let up    = heights[((y - 1 + size) % size) * size + x]
                let down  = heights[((y + 1) % size) * size + x]

                let dx = (left - right) * strength
                let dy = (up - down) * strength

                let i = (y * size + x) * 4
                pixels[i]     = UInt8(clamping: Int(128.0 + dx * 127.0))
                pixels[i + 1] = UInt8(clamping: Int(128.0 + dy * 127.0))
                pixels[i + 2] = 255
                pixels[i + 3] = 255
            }
        }

        return imageFromPixels(pixels, width: size, height: size)
    }

    /// Roughness map with variation so some spots are slightly shinier than others — like real moulded plastic.
    private func generateRoughnessMap(size: Int, scale: Int) -> UIImage {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        // Simple value noise for roughness variation
        let gridSize = scale + 1
        var grid = [[Float]](repeating: [Float](repeating: 0, count: gridSize), count: gridSize)
        for gy in 0..<gridSize { for gx in 0..<gridSize { grid[gy][gx] = Float.random(in: 0...1) } }

        func smoothstep(_ t: Float) -> Float { t * t * (3 - 2 * t) }

        for y in 0..<size {
            for x in 0..<size {
                let gx = Float(x) * Float(scale) / Float(size)
                let gy = Float(y) * Float(scale) / Float(size)
                let x0 = Int(gx) % scale
                let y0 = Int(gy) % scale
                let x1 = (x0 + 1) % gridSize
                let y1 = (y0 + 1) % gridSize
                let fx = smoothstep(gx - Float(Int(gx)))
                let fy = smoothstep(gy - Float(Int(gy)))
                let top = grid[y0][x0] * (1 - fx) + grid[y0][x1] * fx
                let bot = grid[y1][x0] * (1 - fx) + grid[y1][x1] * fx
                let noise = top * (1 - fy) + bot * fy

                // Roughness between 0.7 and 0.95 — all matte, but varies
                let roughness = UInt8(clamping: Int((0.7 + noise * 0.25) * 255.0))
                let i = (y * size + x) * 4
                pixels[i]     = roughness
                pixels[i + 1] = roughness
                pixels[i + 2] = roughness
                pixels[i + 3] = 255
            }
        }

        return imageFromPixels(pixels, width: size, height: size)
    }

    private func imageFromPixels(_ pixels: [UInt8], width: Int, height: Int) -> UIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil, shouldInterpolate: true,
            intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage)
    }

    private func addFallbackCube(to scene: SCNScene) {
        let cube = SCNBox(width: 1, height: 3, length: 0.3, chamferRadius: 0.1)

        let materials = [
            createMaterial(color: .systemRed),
            createMaterial(color: .systemBlue),
            createMaterial(color: .systemGreen),
            createMaterial(color: .systemYellow),
            createMaterial(color: .systemOrange),
            createMaterial(color: .systemPurple)
        ]
        cube.materials = materials

        let cubeNode = SCNNode(geometry: cube)
        cubeNode.name = "model"
        cubeNode.position = SCNVector3(0, 0, 0)

        scene.rootNode.addChildNode(cubeNode)
    }

    private func createMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.specular.contents = UIColor.white
        material.shininess = 0.5
        return material
    }

    // MARK: - Coordinator (handles gestures with hit testing)

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SceneView3D
        var modelNode: SCNNode?
        var ledNode: SCNNode?
        var hasSearchedForLED = false
        weak var sceneView: SCNView?

        // Wobble state
        var isWobbling = false
        private var displayLink: CADisplayLink?
        private var wobbleStartTime: CFTimeInterval = 0

        // Drag state
        private var dragStartRotationX: Double = 0
        private var dragStartRotationY: Double = 0
        private var lastTranslation: CGPoint = .zero

        // Spring animation
        private var velocityX: Double = 0
        private var velocityY: Double = 0
        private var springTimer: Timer?

        private let dragSensitivity: Double = 0.008
        private let stiffness: Double = 2.0
        private let damping: Double = 0.82

        init(parent: SceneView3D) {
            self.parent = parent
        }

        deinit {
            springTimer?.invalidate()
            displayLink?.invalidate()
        }

        // MARK: - Idle Wobble

        func startWobble() {
            guard !isWobbling else { return }
            isWobbling = true
            wobbleStartTime = CACurrentMediaTime()
            displayLink = CADisplayLink(target: self, selector: #selector(wobbleFrame))
            displayLink?.add(to: .main, forMode: .common)
        }

        func stopWobble() {
            guard isWobbling else { return }
            isWobbling = false
            displayLink?.invalidate()
            displayLink = nil

            // Smoothly return to base rotation
            if let model = modelNode {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.6
                model.eulerAngles = SCNVector3(
                    Float(parent.rotationX),
                    Float(parent.rotationY),
                    Float(parent.rotationZ)
                )
                SCNTransaction.commit()
            }
        }

        @objc private func wobbleFrame() {
            guard let model = modelNode else { return }
            let t = CACurrentMediaTime() - wobbleStartTime

            // Ramp up over 1 second for smooth start
            let intensity = Float(parent.wobbleIntensity)
            let ramp = Float(min(t, 1.0)) * intensity

            // Different frequencies per axis for organic, non-repeating feel
            let x = Float(sin(t * 1.2) * 0.06) * ramp
            let y = Float(sin(t * 0.8) * 0.08) * ramp
            let z = Float(sin(t * 0.5) * 0.04) * ramp

            model.eulerAngles = SCNVector3(x, y, z)
        }

        // Only begin gesture if the touch lands on actual 3D geometry
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let sceneView else { return false }
            let point = gestureRecognizer.location(in: sceneView)
            let hits = sceneView.hitTest(point, options: nil)
            return !hits.isEmpty
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView else { return }

            switch gesture.state {
            case .began:
                dragStartRotationX = parent.rotationX
                dragStartRotationY = parent.rotationY
                lastTranslation = .zero
                springTimer?.invalidate()
                springTimer = nil

            case .changed:
                let translation = gesture.translation(in: sceneView)
                let deltaW = translation.x - lastTranslation.x
                let deltaH = translation.y - lastTranslation.y

                parent.rotationY = dragStartRotationY + Double(translation.x) * dragSensitivity
                parent.rotationX = dragStartRotationX + Double(translation.y) * dragSensitivity

                velocityX = Double(deltaH) * dragSensitivity
                velocityY = Double(deltaW) * dragSensitivity
                lastTranslation = translation

            case .ended, .cancelled:
                startSpringBack()

            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onTap?()
        }

        private func startSpringBack() {
            springTimer?.invalidate()

            let dt = 1.0 / 60.0

            springTimer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }

                // Critically damped spring — smooth return, no oscillation
                let accelX = -self.stiffness * self.parent.rotationX
                let accelY = -self.stiffness * self.parent.rotationY

                self.velocityX = (self.velocityX + accelX * dt) * self.damping
                self.velocityY = (self.velocityY + accelY * dt) * self.damping

                self.parent.rotationX += self.velocityX
                self.parent.rotationY += self.velocityY

                // Stop when close enough to origin and barely moving
                if abs(self.parent.rotationX) < 0.001 && abs(self.parent.rotationY) < 0.001
                    && abs(self.velocityX) < 0.001 && abs(self.velocityY) < 0.001 {
                    self.parent.rotationX = 0
                    self.parent.rotationY = 0
                    self.velocityX = 0
                    self.velocityY = 0
                    timer.invalidate()
                    self.springTimer = nil
                }
            }
        }
    }
}

#Preview {
    SceneView3D(
        rotationX: .constant(0),
        rotationY: .constant(0),
        rotationZ: .constant(0),
        usdzFileName: "WatchDogBTCase_Final",
        ledColor: UIColor(red: 1, green: 0, blue: 0, alpha: 1),
        ledIntensity: 0.5
    )
    .frame(width: 300, height: 400)
}
