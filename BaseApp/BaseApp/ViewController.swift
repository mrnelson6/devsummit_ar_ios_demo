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
    
    // UI controls and state
    @IBOutlet var arView: ArcGISARView!
    @IBOutlet var arKitStatusLabel: UILabel!
    @IBOutlet var calibrationBBI: UIBarButtonItem!
    @IBOutlet var helpLabel: UILabel!
    @IBOutlet var toolbar: UIToolbar!
    private var graphics_overlay : AGSGraphicsOverlay?
    private var plane_finder : AirplaneFinder?
    private var animateTimer : Timer?

    private var calibrationVC: CollectDataARCalibrationViewController?
    private var isCalibrating = false {
        didSet {
            if isCalibrating {
                arView.sceneView.scene?.baseSurface?.opacity = 0.7
            } else {
                arView.sceneView.scene?.baseSurface?.opacity = 0.2

                // Dismiss popover
                if let calibrationVC = calibrationVC {
                    calibrationVC.dismiss(animated: true)
                }
            }
        }
    }

    private func configureSceneForAR()
    {
        arView.locationDataSource = AGSCLLocationDataSource()
        // Create scene with imagery basemap
        let scene = AGSScene(basemapType: .imagery)

        // Create an elevation source and add it to the scene
        let elevationSource = AGSArcGISTiledElevationSource(url:
            URL(string: "https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer")!)
        scene.baseSurface?.elevationSources.append(elevationSource)

        // Allow camera to go beneath the surface
        scene.baseSurface?.navigationConstraint = .none
        scene.baseSurface?.opacity = 0.2
        // Display the scene
        arView.sceneView.scene = scene

        // Configure atmosphere and space effect
        arView.sceneView.spaceEffect = .transparent
        arView.sceneView.atmosphereEffect = .none
        
        graphics_overlay = AGSGraphicsOverlay()
        arView.sceneView.graphicsOverlays.add(graphics_overlay!)
        plane_finder = AirplaneFinder(graphicsOverlay: graphics_overlay!, useRealPlanes: false)
        
        DispatchQueue.global(qos: .background).async {
            // 1 / _updatesPerSecond in airplane finder
            self.animateTimer = Timer.scheduledTimer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(self.timerAction), userInfo: nil, repeats: true)
            let runLoop = RunLoop.current
            runLoop.add(self.animateTimer!, forMode: .default)
            runLoop.run()
        }
    }
            
    @objc func timerAction(){
        plane_finder?.animatePlanes()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set ourself as location change delegate so we can get location data source events.
        arView.locationChangeHandlerDelegate = self
        
        // Constrain toolbar to the scene view's attribution label
        toolbar.bottomAnchor.constraint(equalTo: arView.sceneView.attributionTopAnchor).isActive = true

        // Create and prep the calibration view controller
        calibrationVC = CollectDataARCalibrationViewController(arcgisARView: arView)
        calibrationVC?.preferredContentSize = CGSize(width: 250, height: 100)
        calibrationVC?.useContinuousPositioning = false

        // Set delegates and configure arView
        arView.arSCNViewDelegate = self
        arView.locationDataSource = AGSCLLocationDataSource()
        
        configureSceneForAR()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.startTracking(.initial)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        arView.stopTracking()
    }
    
    @IBAction func showCalibrationPopup(_ sender: UIBarButtonItem) {
        if let controller = calibrationVC {

            isCalibrating.toggle()
           
            if isCalibrating {
                showPopup(controller, sourceButton: sender)
            }
        }
    }
}

// MARK: - Calibration view management
extension ViewController {
    private func showPopup(_ controller: UIViewController, sourceButton: UIBarButtonItem) {
        controller.modalPresentationStyle = .popover
        if let presentationController = controller.popoverPresentationController {
            presentationController.delegate = self
            presentationController.barButtonItem = sourceButton
            presentationController.permittedArrowDirections = [.down, .up]
        }
        present(controller, animated: true)
    }
}

// MARK: AGSLocationChangeHandlerDelegate methods
extension ViewController: AGSLocationChangeHandlerDelegate {
    func locationDataSource(_ locationDataSource: AGSLocationDataSource, locationDidChange location: AGSLocation) {
        if(location.position != nil)
        {
            plane_finder?.setCenter(center: location.position!)
        }
    }
}

extension ViewController: UIPopoverPresentationControllerDelegate {
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        isCalibrating = false
    }
}

extension ViewController: UIAdaptivePresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        // show presented controller as popovers even on small displays
        return .none
    }
}

// MARK: - Calibration view controller
class CollectDataARCalibrationViewController: UIViewController {
    /// The camera controller used to adjust user interactions.
    private let arcgisARView: ArcGISARView
    
    /// The `UISlider` used to adjust elevation.
    private let elevationSlider: UISlider = {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = -5.0
        slider.maximumValue = 5.0
        slider.isEnabled = false
        return slider
    }()
    
    /// The UISlider used to adjust heading.
    private let headingSlider: UISlider = {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = -10.0
        slider.maximumValue = 10.0
        return slider
    }()
    
    /// Determines whether continuous positioning is in use
    /// Showing the elevation slider is only appropriate when using local positioning
    var useContinuousPositioning: Bool = false {
        didSet {
            if useContinuousPositioning {
                elevationSlider.isEnabled = false
                elevationSlider.removeTarget(self, action: #selector(elevationChanged(_:)), for: .valueChanged)
                elevationSlider.removeTarget(self, action: #selector(touchUpElevation(_:)), for: [.touchUpInside, .touchUpOutside])
            } else {
                elevationSlider.isEnabled = true
                
                // Set up events for the heading slider
                elevationSlider.addTarget(self, action: #selector(elevationChanged(_:)), for: .valueChanged)
                elevationSlider.addTarget(self, action: #selector(touchUpElevation(_:)), for: [.touchUpInside, .touchUpOutside])
            }
        }
    }
    
    /// The elevation delta amount based on the elevation slider value.
    private var joystickElevation: Double {
        let deltaElevation = Double(elevationSlider.value)
        return pow(deltaElevation, 2) / 50.0 * (deltaElevation < 0 ? -1.0 : 1.0)
    }
    
    ///  The heading delta amount based on the heading slider value.
    private var joystickHeading: Double {
        let deltaHeading = Double(headingSlider.value)
        return pow(deltaHeading, 2) / 25.0 * (deltaHeading < 0 ? -1.0 : 1.0)
    }

    /// Initialized a new calibration view with the given scene view and camera controller.
    ///
    /// - Parameters:
    ///   - arcgisARView: The ArcGISARView we are calibrating..
    init(arcgisARView: ArcGISARView) {
        self.arcgisARView = arcgisARView
        super.init(nibName: nil, bundle: nil)

        // Add the heading label and slider.
        let headingLabel = UILabel(frame: .zero)
        headingLabel.text = "Heading:"
        headingLabel.textColor = .yellow
        view.addSubview(headingLabel)
        headingLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headingLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            headingLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        
        view.addSubview(headingSlider)
        headingSlider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headingSlider.leadingAnchor.constraint(equalTo: headingLabel.trailingAnchor, constant: 16),
            headingSlider.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            headingSlider.centerYAnchor.constraint(equalTo: headingLabel.centerYAnchor)
        ])
        
        // Add the elevation label and slider.
        let elevationLabel = UILabel(frame: .zero)
        elevationLabel.text = "Elevation:"
        elevationLabel.textColor = .yellow
        view.addSubview(elevationLabel)
        elevationLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            elevationLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            elevationLabel.bottomAnchor.constraint(equalTo: headingLabel.topAnchor, constant: -24)
        ])
        
        view.addSubview(elevationSlider)
        elevationSlider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            elevationSlider.leadingAnchor.constraint(equalTo: elevationLabel.trailingAnchor, constant: 16),
            elevationSlider.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            elevationSlider.centerYAnchor.constraint(equalTo: elevationLabel.centerYAnchor)
        ])
        
        // Setup actions for the two sliders. The sliders operate as "joysticks",
        // where moving the slider thumb will start a timer
        // which roates or elevates the current camera when the timer fires.  The elevation and heading delta
        // values increase the further you move away from center.  Moving and holding the thumb a little bit from center
        // will roate/elevate just a little bit, but get progressively more the further from center the thumb is moved.
        headingSlider.addTarget(self, action: #selector(headingChanged(_:)), for: .touchDown)
        headingSlider.addTarget(self, action: #selector(touchUpHeading(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // The timers for the "joystick" behavior.
    private var elevationTimer: Timer?
    private var headingTimer: Timer?
    
    /// Handle an elevation slider value-changed event.
    ///
    /// - Parameter sender: The slider tapped on.
    @objc
    func elevationChanged(_ sender: UISlider) {
        if elevationTimer == nil {
            // Create a timer which elevates the camera when fired.
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] (_) in
                let delta = self?.joystickElevation ?? 0.0
                self?.elevate(delta)
            }
            
            // Add the timer to the main run loop.
            RunLoop.main.add(timer, forMode: .default)
            elevationTimer = timer
        }
    }
    
    /// Handle an heading slider value-changed event.
    ///
    /// - Parameter sender: The slider tapped on.
    @objc
    func headingChanged(_ sender: UISlider) {
        if headingTimer == nil {
            // Create a timer which rotates the camera when fired.
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] (_) in
                let delta = self?.joystickHeading ?? 0.0
                self?.rotate(delta)
            }
            
            // Add the timer to the main run loop.
            RunLoop.main.add(timer, forMode: .default)
            headingTimer = timer
        }
    }
    
    /// Handle an elevation slider touchUp event.  This will stop the timer.
    ///
    /// - Parameter sender: The slider tapped on.
    @objc
    func touchUpElevation(_ sender: UISlider) {
        elevationTimer?.invalidate()
        elevationTimer = nil
        sender.value = 0.0
    }
    
    /// Handle a heading slider touchUp event.  This will stop the timer.
    ///
    /// - Parameter sender: The slider tapped on.
    @objc
    func touchUpHeading(_ sender: UISlider) {
        headingTimer?.invalidate()
        headingTimer = nil
        sender.value = 0.0
    }
    
    /// Rotates the camera by `deltaHeading`.
    ///
    /// - Parameter deltaHeading: The amount to rotate the camera.
    private func rotate(_ deltaHeading: Double) {
        let camera = arcgisARView.originCamera
        let newHeading = camera.heading + deltaHeading
        arcgisARView.originCamera = camera.rotate(toHeading: newHeading, pitch: camera.pitch, roll: camera.roll)
    }
    
    /// Change the cameras altitude by `deltaAltitude`.
    ///
    /// - Parameter deltaAltitude: The amount to elevate the camera.
    private func elevate(_ deltaAltitude: Double) {
        let camera = arcgisARView.originCamera
        arcgisARView.originCamera = camera.elevate(withDeltaAltitude: deltaAltitude)
    }
}

// MARK: - tracking status display
extension ViewController: ARSCNViewDelegate {
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            arKitStatusLabel.isHidden = true
        case .notAvailable:
            arKitStatusLabel.text = "ARKit location not available"
            arKitStatusLabel.isHidden = false
        case .limited(let reason):
            arKitStatusLabel.isHidden = false
            switch reason {
            case .excessiveMotion:
                arKitStatusLabel.text = "Try moving your phone more slowly"
                arKitStatusLabel.isHidden = false
            case .initializing:
                arKitStatusLabel.text = "Keep moving your phone"
                arKitStatusLabel.isHidden = false
            case .insufficientFeatures:
                arKitStatusLabel.text = "Try turning on more lights and moving around"
                arKitStatusLabel.isHidden = false
            case .relocalizing:
                // this won't happen as this sample doesn't use relocalization
                break
            @unknown default:
                break
            }
        }
    }
}
