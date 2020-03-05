//
//  Plane.swift
//  ios_test_app
//
//  Created by Matthew Nelson on 3/2/20.
//  Copyright © 2020 Matthew Nelson. All rights reserved.
//

import Foundation
import ArcGIS

class Plane
{
    public var _callsign : String
    public var _velocity : Double
    public var _verticalRateOfChange : Double
    public var _heading : Double
    public var _graphic : AGSGraphic
    public var _lastUpdate : Int
    public var _bigPlane : Bool
    
    init(graphic : AGSGraphic, velocity : Double, verticalRateOfChange : Double, heading : Double, lastUpdate : Int, bigPlane : Bool, callsign : String)
    {
        _graphic = graphic
        _velocity = velocity
        _verticalRateOfChange = verticalRateOfChange
        _heading = heading
        _lastUpdate = lastUpdate
        _bigPlane = bigPlane
        _callsign = callsign
    }
}
