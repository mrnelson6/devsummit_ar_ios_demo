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
       
        
        arView.sceneView.scene = AGSScene(basemap: AGSBasemap.streets())
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.startTracking(.ignore)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        arView.stopTracking()
    }


}

