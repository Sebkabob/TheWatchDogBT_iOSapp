//
//  SceneView3D.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI
import SceneKit

struct SceneView3D: UIViewRepresentable {
    let rotation: SIMD3<Double>
    let dragRotation: SIMD3<Double>
    let usdzFileName: String
    let ledIntensity: Double
    
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
        
        return sceneView
    }
    
    func updateUIView(_ sceneView: SCNView, context: Context) {
        guard let model = context.coordinator.modelNode else { return }
        
        if !context.coordinator.hasSearchedForLED {
            context.coordinator.hasSearchedForLED = true
            searchForLED(in: model, coordinator: context.coordinator)
        }
        
        let combinedRotation = SIMD3<Double>(
            rotation.x + dragRotation.x,
            rotation.z + dragRotation.y,
            dragRotation.z
        )
        
        model.eulerAngles = SCNVector3(
            Float(combinedRotation.x),
            Float(rotation.z + dragRotation.z),
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
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
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
    
    class Coordinator {
        var modelNode: SCNNode?
        var ledNode: SCNNode?
        var hasSearchedForLED = false
        var sceneView: SCNView?
    }
}
