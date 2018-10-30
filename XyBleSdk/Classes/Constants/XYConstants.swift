//
//  XYConstants.swift
//  XYSdkSample
//
//  Created by Darren Sutherland on 9/7/18.
//  Copyright © 2018 Darren Sutherland. All rights reserved.
//

import Foundation

internal struct XYConstants {
    static let DEVICE_TUNING_SECONDS_INTERVAL_CONNECTED_RSSI_READ = 3
    static let DEVICE_TUNING_LOCATION_CHANGE_THRESHOLD = 10.0
    static let DEVICE_TUNING_SECONDS_EXIT_CHECK_INTERVAL = 1.0
    static let DEVICE_TUNING_SECONDS_WITHOUT_SIGNAL_FOR_EXITING = 12.0

    static let DEVICE_TUNING_SECONDS_WITHOUT_SIGNAL_FOR_EXIT_GAP_SIZE = 2.0
    static let DEVICE_TUNING_SECONDS_WITHOUT_SIGNAL_FOR_EXIT_WINDOW_COUNT = 3
    static let DEVICE_TUNING_SECONDS_WITHOUT_SIGNAL_FOR_EXIT_WINDOW_SIZE = 2.5
}

public enum XYDeviceProximity: Int {
    case none
    case outOfRange
    case veryFar
    case far
    case medium
    case near
    case veryNear
    case touching

    public static func fromSignalStrength(_ strength: Int) -> XYDeviceProximity {
        if strength == -999 { return XYDeviceProximity.none }
        if strength >= -40 { return XYDeviceProximity.touching }
        if strength >= -60 { return XYDeviceProximity.veryNear }
        if strength >= -70 { return XYDeviceProximity.near }
        if strength >= -80 { return XYDeviceProximity.medium }
        if strength >= -90 { return XYDeviceProximity.far }
        if strength >= -200 { return XYDeviceProximity.veryFar }
        return XYDeviceProximity.outOfRange
    }

    public static let defaultProximity: Int = -999
}

public enum XYButtonType2 : Int {
    case none
    case single
    case double
    case long
}

public enum XYFinderSong {
    case off
    case findIt

    public func values(for device: XYFinderDeviceFamily) -> [UInt8] {
        switch self {
        case .off:
            switch device {
            case .xy4:
                return [0xff, 0x03]
            case .xy1:
                return [0x01]
            default:
                return [0xff]
            }
        case .findIt:
            switch device {
            case .xy4:
                return [0x0b, 0x03]
            case .xy2:
                return [0x01]
            case .xy1:
                return [0x01]
            default:
                return [0x02]
            }
        }

    }
}

internal class GenericLock {

    private static var counter = 0
    private var currentCounter = 0
    private var name: String?

//    private let semaphore = DispatchSemaphore(value: 1)
//    internal static let waitTimeout: TimeInterval = 15

    private let
    semaphore: DispatchSemaphore,
    waitTimeout: TimeInterval

    init(_ value: Int = 1, timeout: TimeInterval = 15) {
        self.semaphore = DispatchSemaphore(value: value)
        self.waitTimeout = timeout
    }

    public func lock(_ name: String? = nil) {
        currentCounter = GenericLock.counter
        self.name = name
        GenericLock.counter += 1
        print(" ------------ LOCKING: \(currentCounter) : \(name ?? "unnamed") ------------ ")
        if self.semaphore.wait(timeout: .now() + self.waitTimeout) == .timedOut {
            self.unlock()
        }
    }

    public func unlock() {
        print(" +++++++++++++ UNLOCKING \(currentCounter) : \(name ?? "unnamed") +++++++++++++ ")
        self.semaphore.signal()
    }

}
