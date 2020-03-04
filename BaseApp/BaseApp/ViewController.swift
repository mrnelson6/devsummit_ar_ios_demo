// Copyright 2019 Esri.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import ARKit
import ArcGISToolkit
import ArcGIS

class ViewController: UIViewController {
    // UI controls
    @IBOutlet var arView: ArcGISARView!
    @IBOutlet var helpLabel: UILabel!
    
    // State
    private var hasPlacedScene = false {
        didSet {
            helpLabel.isHidden = hasPlacedScene
        }
    }

    // Wait for at least one detected plane before allowing user to place map
    var hasFoundPlane = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure a starting invisible scene with a tiling scheme matching that of the scene that will be used
        arView.sceneView.scene = AGSScene(tilingScheme: .webMercator)
        arView.sceneView.scene?.baseSurface?.opacity = 0
        // Listen for tracking state changes
        arView.arSCNViewDelegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.startTracking(.ignore)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        arView.stopTracking()
    }

      private func configureSceneForAR() {

        // create scene with basemap
        let scene = AGSScene(url: URL(string:"https://www.arcgis.com/home/webscene/viewer.html?webscene=6bf6d9f17bdd4d33837e25e1cae4e9c9")!)!

        hasPlacedScene = true
        // Wait for the layer to load, then set the AR camera
        scene.load { [weak self] (err: Error?) in
            guard let self = self else { return }

            if (err == nil) {
                // Display the scene
                self.arView.sceneView.scene = scene

                // Configure scene surface opacity and navigation constraint
                if let surface = scene.baseSurface {
                    //surface.opacity = 0.0
                    surface.navigationConstraint = .none
                }
                self.arView.translationFactor = 700
                let point = AGSPoint(x:-117.168654, y:32.71012, z:0.0, spatialReference: nil)
                let camera = AGSCamera(location: point, heading: 0, pitch: 90, roll: 0)
                self.arView.originCamera = camera
                self.arView.clippingDistance = 180
            }
        }

    }

}

// MARK: - position the scene on touch
extension ViewController: AGSGeoViewTouchDelegate {
    func geoView(_ geoView: AGSGeoView, didTapAtScreenPoint screenPoint: CGPoint, mapPoint: AGSPoint) {
        // Only let the user place the scene once
        guard !hasPlacedScene else { return }
        
        // Use a screen point to set the initial transformation on the view.
        if self.arView.setInitialTransformation(using: screenPoint) {
            configureSceneForAR()
        } else {
            //presentAlert(message: "Failed to place scene, try again")
        }
    }

    private func enableTapToPlace() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.helpLabel.isHidden = false
            self.helpLabel.text = "Tap a surface to place the scene"

            // Wait for the user to tap to place the scene
            self.arView.sceneView.touchDelegate = self
        }
    }
}

// MARK: - tracking status display
extension ViewController: ARSCNViewDelegate {
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            if hasPlacedScene {
                helpLabel.isHidden = true
            } else if !hasFoundPlane {
                helpLabel.isHidden = false
                helpLabel.text = "Keep moving your phone"
            }
        case .notAvailable:
            helpLabel.text = "Location not available"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                helpLabel.text = "Try moving your phone more slowly"
                helpLabel.isHidden = false
            case .initializing:
                helpLabel.text = "Keep moving your phone"
                helpLabel.isHidden = false
            case .insufficientFeatures:
                helpLabel.text = "Try turning on more lights and moving around"
                helpLabel.isHidden = false
            case .relocalizing:
                // this won't happen as this sample doesn't use relocalization
                break
            @unknown default:
               break
            }
        }
    }

    // MARK: - Wait for plane before enabling scene
    public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor as? ARPlaneAnchor != nil else { return }

        // If we haven't placed a scene yet, enable tapping to place a scene and draw the ARKit plane found
        if !hasPlacedScene {
            hasFoundPlane = true
            enableTapToPlace()
            visualizePlane(renderer, didAdd: node, for: anchor)
        }
    }

    // MARK: - Plane visualization
    private func visualizePlane(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Create a custom object to visualize the plane geometry and extent.
        if #available(iOS 11.3, *) {
            // Place content only for anchors found by plane detection.
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

            let arGeometry = planeAnchor.geometry

            let arPlaneSceneGeometry = ARSCNPlaneGeometry(device: renderer.device!)

            arPlaneSceneGeometry?.update(from: arGeometry)

            let newNode = SCNNode(geometry: arPlaneSceneGeometry)

            node.addChildNode(newNode)

            let newMaterial = SCNMaterial()

            newMaterial.isDoubleSided = true

            newMaterial.diffuse.contents = UIColor(red: 1.0, green: 0, blue: 0, alpha: 0.4)

            arPlaneSceneGeometry?.materials = [newMaterial]

            node.geometry = arPlaneSceneGeometry
        }
    }

    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if hasPlacedScene {
            // Remove plane visualization
            node.removeFromParentNode()
            return
        }

        // Create a custom object to visualize the plane geometry and extent.
        if #available(iOS 11.3, *) {
            // Place content only for anchors found by plane detection.
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

            let arGeometry = planeAnchor.geometry

            let arPlaneSceneGeometry = ARSCNPlaneGeometry(device: renderer.device!)

            arPlaneSceneGeometry?.update(from: arGeometry)

            node.childNodes[0].geometry = arPlaneSceneGeometry

            if let material = node.geometry?.materials {
                arPlaneSceneGeometry?.materials = material
            }
        }
    }
}
