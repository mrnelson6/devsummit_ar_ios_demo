//
//  AirplaneFinder.swift
//  ios_test_app
//
//  Created by Matthew Nelson on 3/2/20.
//  Copyright © 2020 Matthew Nelson. All rights reserved.
//

import Foundation
import ArcGIS

class AirplaneFinder
{
    private var _smallPlane3DSymbol : AGSModelSceneSymbol
    private var _largePlane3DSymbol : AGSModelSceneSymbol
    private var _graphicsOverlay : AGSGraphicsOverlay
    
    private var  _updatesPerSecond : Int = 60;
    private var _secondsPerQuery : Int = 10;
    private var _secondsPerCleanup : Int = 30;
    public var _coordinateTolerance : Double = 0.5;
    public var _center : AGSPoint?
    public var planes : [String : Plane]
    private var _useRealPlanes : Bool
    
    init(graphicsOverlay : AGSGraphicsOverlay, useRealPlanes : Bool)
    {
        _graphicsOverlay = graphicsOverlay
        //_smallPlane3DSymbol = AGSSimpleMarkerSceneSymbol.sphere(with: UIColor.red, diameter: 400)
        //_largePlane3DSymbol = AGSSimpleMarkerSceneSymbol.sphere(with: UIColor.blue, diameter: 800)
        _smallPlane3DSymbol = AGSModelSceneSymbol(name: "B_787_8", extension: "dae", scale: 60.0)
        _largePlane3DSymbol = AGSModelSceneSymbol(name: "Bristol", extension: "dae", scale: 20.0)
        planes = [String : Plane]()
        _useRealPlanes = useRealPlanes
        setupScene()
    }
    
    private func setupScene()
    {
        _graphicsOverlay.sceneProperties?.surfacePlacement = .absolute
        var renderer3D = AGSSimpleRenderer()
        renderer3D.sceneProperties?.headingExpression = "[HEADING]"
        renderer3D.sceneProperties?.pitchExpression = "[PITCH]"
        renderer3D.sceneProperties?.rollExpression = "[ROLL]"
        _graphicsOverlay.renderer = renderer3D
    }

    public func setCenter(center : AGSPoint)
    {
        if(center.x != 0)
        {
            _center = center
        }
    }
    
    private func addPlanesViaAPI()
    {
        let envelop = AGSEnvelope(center: _center!, width: _coordinateTolerance, height: _coordinateTolerance)
        let xMax = envelop.xMax
        let xMin = envelop.xMin
        let yMax = envelop.yMax
        let yMin = envelop.yMin
        
        var requestString = "https://matt9678:Window430@opensky-network.org/api/states/all?lamin=" + String(yMin)
        requestString += "&lomin=" + String(xMin)
        requestString += "&lamax=" + String(yMax)
        requestString += "&lomax=" + String(xMax)
        
        let url = URL(string: requestString)!
        //create the session object
        let session = URLSession.shared
        //now create the URLRequest object using the url object
        let request = URLRequest(url: url)

        //create dataTask using the session object to send data to the server
        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in

            guard error == nil else {
                self.outstandingRequest = false
                return
            }

            guard let data = data else {
                self.outstandingRequest = false
                return
            }
            let decodedString = String(data: data, encoding: .utf8)!
            self.parseResponse(response : decodedString)
            self.outstandingRequest = false
        })
        outstandingRequest = true
        task.resume()
    }
    
    private func parseResponse(response : String)
    {
        let time_message_sent = Int(String(response[response.index(response.startIndex, offsetBy: 8)..<response.index(response.startIndex, offsetBy: 18)]))
        let unixTimestamp = Int(NSDate().timeIntervalSince1970)
        let states = String(response[response.index(response.startIndex, offsetBy: 30)..<response.index(response.endIndex, offsetBy: 0)])
        //let elements = states.split(separator: ",")
        let elements = states.components(separatedBy: "[")
        for element in elements
        {
            let attributes = element.components(separatedBy: ",")
            if(attributes.count < 13)
            {
                return
            }
            if(attributes[5] != "null" && attributes[6] != "null")
            {
                let at1 = attributes[1]
                let stI = at1.index(at1.startIndex, offsetBy: 1)
                let enI = at1.index(at1.endIndex, offsetBy: -2)
                var callsign : String
                if (stI > enI)
                {
                    callsign = "Unknown"
                }
                else
                {
                    let rnI = at1[stI..<enI]
                    callsign = String(rnI)
                }
                var last_timestamp : Int = 0;
                let lat = Double(attributes[6])!
                let lon = Double(attributes[5])!
                var alt : Double = 0.0
                if (attributes[13] != "null")
                 {
                     alt = Double(attributes[13])!;
                 }
                 else if (attributes[7] != "null")
                 {
                     alt = Double(attributes[7])!;
                 }
                var velocity : Double = 0.0;
                var heading : Double = 0.0;
                var vert_rate : Double = 0.0;
                if (attributes[9] != "null")
                {
                    velocity = Double(attributes[9])!;
                }

                if (attributes[10] != "null")
                {
                    heading = Double(attributes[10])!;
                }

                if (attributes[11] != "null")
                {
                    vert_rate = Double(attributes[11])!;
                }

                if (attributes[3] != "null")
                {
                    last_timestamp = Int(attributes[3])!;
                }
                let point = AGSPoint(x: lon, y: lat, z: alt, spatialReference: AGSSpatialReference.init(wkid: 4326))
                let time_difference = unixTimestamp - last_timestamp
                var point_array =  [AGSPoint]()
                point_array.append(point)
                let distance = velocity * Double(time_difference)
                let updated_point = AGSGeometryEngine.geodeticMove(point_array, distance: distance, distanceUnit: .meters(), azimuth: heading, azimuthUnit: .degrees(), curveType: .geodesic)![0]
                let delta_z = updated_point.z + (vert_rate * Double(time_difference))
                let new_location = AGSPoint(x: updated_point.x, y: updated_point.y, z: delta_z, spatialReference: AGSSpatialReference.init(wkid: 4326))
                
                let curr_plane = planes[callsign]
                if(curr_plane != nil)
                {
                    curr_plane?._graphic.geometry = new_location
                    curr_plane?._graphic.attributes["HEADING"] = heading + 180
                    curr_plane?._graphic.attributes["CALLSIGN"] = callsign
                    curr_plane?._velocity = velocity
                    curr_plane?._verticalRateOfChange = vert_rate
                    curr_plane?._heading = heading
                    curr_plane?._lastUpdate = last_timestamp
                }
                else
                {
                    let callsign_array = Array(callsign)
                    if(callsign_array.count > 0 && callsign_array[0] == "N")
                    {
                        var gr = AGSGraphic(geometry: new_location, symbol:_smallPlane3DSymbol)
                        gr.attributes["HEADING"] = heading + 180
                        gr.attributes["CALLSIGN"] = callsign
                        let new_plane = Plane(graphic: gr, velocity: velocity, verticalRateOfChange: vert_rate, heading: heading, lastUpdate: last_timestamp, bigPlane: false, callsign: callsign)
                        planes[callsign] = new_plane
                        _graphicsOverlay.graphics.add(gr)
                    }
                    else
                    {
                        var gr = AGSGraphic(geometry: new_location, symbol:_largePlane3DSymbol)
                        gr.attributes["HEADING"] = heading
                        gr.attributes["CALLSIGN"] = callsign
                        let new_plane = Plane(graphic: gr, velocity: velocity, verticalRateOfChange: vert_rate, heading: heading, lastUpdate: last_timestamp, bigPlane: true, callsign: callsign)
                        planes[callsign] = new_plane
                        _graphicsOverlay.graphics.add(gr)
                    }
                }
            }
        }
    }
    
    private var updateCounter : Int = -1
    private var outstandingRequest : Bool = false
    public func animatePlanes()
    {
        if(_center == nil)
        {
            return
        }
        if(!_useRealPlanes && updateCounter == -1)
        {
            generateRandomPlanes()
        }
        if(outstandingRequest)
        {
            return
        }
        updateCounter += 1
        if (_useRealPlanes && (updateCounter % (_secondsPerCleanup * _updatesPerSecond) == 0))
        {
            var planes_to_remove = [String]()
            let unixTimestamp = Int(NSDate().timeIntervalSince1970)
            for plane in planes
            {
                if(unixTimestamp - plane.value._lastUpdate > _secondsPerCleanup)
                {
                    _graphicsOverlay.graphics.remove(plane.value._graphic)
                    planes_to_remove.append(plane.key)
                }
            }
            for remove_callsign in planes_to_remove
            {
                planes[remove_callsign] = nil
            }
        }
        if (_useRealPlanes && (updateCounter % (_updatesPerSecond * _secondsPerQuery) == 0))
        {
            addPlanesViaAPI();
        }
        else
        {
            for plane in planes
            {
                let point = plane.value._graphic.geometry as! AGSPoint
                var point_array =  [AGSPoint]()
                point_array.append(point)
                let distance = 10 * plane.value._velocity / Double(_updatesPerSecond)
                let updated_point = AGSGeometryEngine.geodeticMove(point_array, distance: distance, distanceUnit: .meters(), azimuth: plane.value._heading, azimuthUnit: .degrees(), curveType: .geodesic)![0]
                let delta_z = updated_point.z + (plane.value._verticalRateOfChange / Double(_updatesPerSecond))
                let new_location = AGSPoint(x: updated_point.x, y: updated_point.y, z: delta_z, spatialReference: AGSSpatialReference.init(wkid: 4326))
                plane.value._graphic.geometry = new_location
            }
        }
    }
    
    
    private func generateRandomPlanes()
    {
        let numPlanes = 20
        let unixTimestamp = Int(NSDate().timeIntervalSince1970)
        for i in 0...numPlanes
        {
            var callsign = ""
            var gr : AGSGraphic
            var bigPlane : Bool
            let heading = Double.random(in: 0...359)
            let velocity = Double.random(in: 100...300)
            let x = _center!.x + Double.random(in: -0.5...0.5)
            let y = _center!.y + Double.random(in: -0.5...0.5)
            let z = _center!.z + Double.random(in: 800...9000)
            let point = AGSPoint(x: x, y: y, z: z, spatialReference: _center!.spatialReference)
            if(i < numPlanes / 4)
            {
                callsign = "N" + String(i)
                gr = AGSGraphic(geometry: point, symbol:_smallPlane3DSymbol)
                gr.attributes["HEADING"] = heading + 180
                gr.attributes["CALLSIGN"] = callsign
                bigPlane = false
            }
            else
            {
                callsign = "ARC" + String(i)
                gr = AGSGraphic(geometry: point, symbol:_largePlane3DSymbol)
                gr.attributes["HEADING"] = heading
                gr.attributes["CALLSIGN"] = callsign
                bigPlane = true
            }

            let new_plane = Plane(graphic: gr, velocity: velocity, verticalRateOfChange: 0.0, heading: heading, lastUpdate: unixTimestamp, bigPlane: bigPlane, callsign: callsign)
            planes[callsign] = new_plane
            _graphicsOverlay.graphics.add(gr)
        }
    }
}
