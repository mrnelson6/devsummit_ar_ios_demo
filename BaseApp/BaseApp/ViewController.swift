//
//  ViewController.swift
//  BaseApp
//
//  Created by Matthew Nelson on 3/4/20.
//  Copyright © 2020 Matthew Nelson. All rights reserved.
//

import UIKit
import ARKit
import ArcGISToolkit
import ArcGIS

class ViewController: UIViewController {
    
    @IBOutlet var arView: ArcGISARView!
    @IBOutlet var helpLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSceneForAR()
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
        let scene = AGSScene(basemapType: .imagery)
        let portal = AGSPortal(url: URL(string: "https://www.arcgis.com")!, loginRequired: false)
        let portalItem = AGSPortalItem(portal: portal, itemID: "1f97ba887fd4436c8b17a14d83584611")
        let meshLayer = AGSIntegratedMeshLayer(item: portalItem)
        scene.operationalLayers.add(meshLayer)
        
        let elevationSource = AGSArcGISTiledElevationSource(url: URL(string:"https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer")!)
        scene.baseSurface?.elevationSources.append(elevationSource)
        // Disable the navigation constraint
        scene.baseSurface?.navigationConstraint = .stayAbove
        // show scene
        arView.sceneView.scene = scene
    
        // Wait for the layer to load, then set the AR camera
        meshLayer.load { [weak self, weak meshLayer] (err: Error?) in
            guard let self = self else { return }
            guard let `meshLayer` = meshLayer else { return }
            if (err != nil) {
                return
            } else if let envelope = meshLayer.fullExtent {
                let camera = AGSCamera(latitude: envelope.center.y,
                                        longitude: envelope.center.x,
                                        altitude: 2500,
                                        heading: 0,
                                        pitch: 90,
                                        roll: 0)
                self.arView.originCamera = camera
            }
        }

        // Set the translation factor to enable rapid movement through the scene
        arView.translationFactor = 4000

        // Turn the space and atmosphere effects on for an immersive experience
        arView.sceneView.spaceEffect = .stars
        arView.sceneView.atmosphereEffect = .realistic
    }


}

