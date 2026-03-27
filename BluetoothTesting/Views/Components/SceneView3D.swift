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
    let usdzFileName: String
    let ledIntensity: Double
    var onTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = createScene()
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = false
        sceneView.backgroundColor = .clear

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 20
        sceneView.scene?.rootNode.addChildNode(ambientLight)

        context.coordinator.modelNode = sceneView.scene?.rootNode.childNode(withName: "model", recursively: true)

        if let model = context.coordinator.modelNode {
            let (min, max) = model.boundingBox
            let centerY = (min.y + max.y) / 2.0
            model.pivot = SCNMatrix4MakeTranslation(0, centerY, 0)
        }

        context.coordinator.sceneView = sceneView

        // Add gesture recognizers — only begin when touching the 3D model
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        sceneView.addGestureRecognizer(panGesture)

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

        model.eulerAngles = SCNVector3(
            Float(rotationX),
            Float(rotationY),
            0
        )

        if let ledNode = context.coordinator.ledNode {
            updateLED(node: ledNode, intensity: ledIntensity)
        }
    }

    private func searchForLED(in rootNode: SCNNode, coordinator: Coordinator) {
        rootNode.enumerateHierarchy { (childNode, stop) in
            if let nodeName = childNode.name {
                if nodeName.uppercased().contains("LED") {
                    coordinator.ledNode = childNode
                    print("✅ LED found: \(nodeName)")
                    stop.pointee = true
                }
            }
        }
        if coordinator.ledNode == nil {
            print("❌ LED not found")
        }
    }

    private func updateLED(node: SCNNode, intensity: Double) {
        guard let material = node.geometry?.firstMaterial else { return }

        if intensity > 0.0 {
            let brightness = CGFloat(intensity)
            let brightnessMultiplier: CGFloat = 10.0
            let warmOrange = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)

            material.emission.contents = warmOrange
            material.emission.intensity = brightness * brightnessMultiplier
            material.diffuse.contents = warmOrange

            if node.childNode(withName: "ledLight", recursively: false) == nil {
                let lightNode = SCNNode()
                lightNode.name = "ledLight"
                lightNode.light = SCNLight()
                lightNode.light?.type = .omni
                lightNode.light?.color = warmOrange

                let (min, max) = node.boundingBox
                let center = SCNVector3(
                    (min.x + max.x) / 2,
                    (min.y + max.y) / 2,
                    (min.z + max.z) / 2
                )
                lightNode.position = center

                lightNode.light?.attenuationStartDistance = 0.5
                lightNode.light?.attenuationEndDistance = 1.5

                node.addChildNode(lightNode)
            }

            if let lightNode = node.childNode(withName: "ledLight", recursively: false) {
                lightNode.light?.intensity = CGFloat(intensity * 30)
                lightNode.light?.color = warmOrange
            }

        } else {
            material.emission.contents = UIColor.white
            material.emission.intensity = 0.0
            material.diffuse.contents = UIColor.darkGray

            if let lightNode = node.childNode(withName: "ledLight", recursively: false) {
                lightNode.light?.intensity = 0
            }
        }
    }

    private func createScene() -> SCNScene {
        let scene = SCNScene()

        if let usdzURL = Bundle.main.url(forResource: usdzFileName, withExtension: "usdz") {
            do {
                let usdzScene = try SCNScene(url: usdzURL, options: nil)

                let modelNode = SCNNode()
                modelNode.name = "model"

                for child in usdzScene.rootNode.childNodes {
                    modelNode.addChildNode(child)
                }

                modelNode.scale = SCNVector3(0.07, 0.07, 0.07)
                modelNode.position = SCNVector3(0, 0, 0)

                scene.rootNode.addChildNode(modelNode)
            } catch {
                addFallbackCube(to: scene)
            }
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

        // Drag state
        private var dragStartRotationX: Double = 0
        private var dragStartRotationY: Double = 0
        private var lastTranslation: CGPoint = .zero

        // Momentum
        private var velocityX: Double = 0
        private var velocityY: Double = 0
        private var decayTimer: Timer?

        private let dragSensitivity: Double = 0.008
        private let maxPitch: Double = 1.2
        private let decayFactor: Double = 0.95
        private let minVelocity: Double = 0.0005

        init(parent: SceneView3D) {
            self.parent = parent
        }

        deinit {
            decayTimer?.invalidate()
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
                decayTimer?.invalidate()
                decayTimer = nil

            case .changed:
                let translation = gesture.translation(in: sceneView)
                let deltaW = translation.x - lastTranslation.x
                let deltaH = translation.y - lastTranslation.y

                parent.rotationY = dragStartRotationY + Double(translation.x) * dragSensitivity
                let newPitch = dragStartRotationX + Double(translation.y) * dragSensitivity
                parent.rotationX = max(-maxPitch, min(maxPitch, newPitch))

                velocityX = Double(deltaH) * dragSensitivity
                velocityY = Double(deltaW) * dragSensitivity
                lastTranslation = translation

            case .ended, .cancelled:
                startMomentumDecay()

            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onTap?()
        }

        private func startMomentumDecay() {
            decayTimer?.invalidate()

            decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }

                self.velocityX *= self.decayFactor
                self.velocityY *= self.decayFactor

                self.parent.rotationY += self.velocityY
                let newPitch = self.parent.rotationX + self.velocityX
                self.parent.rotationX = max(-self.maxPitch, min(self.maxPitch, newPitch))

                if abs(self.velocityX) < self.minVelocity && abs(self.velocityY) < self.minVelocity {
                    self.velocityX = 0
                    self.velocityY = 0
                    timer.invalidate()
                    self.decayTimer = nil
                }
            }
        }
    }
}

#Preview {
    SceneView3D(
        rotationX: .constant(0),
        rotationY: .constant(0),
        usdzFileName: "WatchDogBTCase_Final",
        ledIntensity: 0.5
    )
    .frame(width: 300, height: 400)
}
