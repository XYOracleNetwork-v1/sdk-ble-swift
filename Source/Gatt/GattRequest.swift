//
//  GattRequest.swift
//  XYBleSdk
//
//  Created by Darren Sutherland on 9/12/18.
//  Copyright © 2018 XY - The Findables Company. All rights reserved.
//

import Foundation
import CoreBluetooth
import Promises

public enum GattRequestStatus: String {
    case disconnected
    case discoveringServices
    case discoveringCharacteristics

    case reading
    case writing
    case notifying

    case timedOut
    case completed
}

// A "single use" object for discovering a requested service/characteristic from a peripheral and either getting
// that value (returned as a Data promise) or setting a value.
final class GattRequest: NSObject {
    // Promises that resolve locating the characteristic and reading and writing data
    fileprivate lazy var characteristicPromise = Promise<Void>.pending()
    fileprivate lazy var readPromise = Promise<Data?>.pending()
    fileprivate lazy var writePromise = Promise<Void>.pending()
    fileprivate lazy var notifyPromise = Promise<Void>.pending()

    fileprivate let serviceCharacteristic: XYServiceCharacteristic

    fileprivate var
    device: XYBluetoothDevice?,
    service: CBService?,
    characteristic: CBCharacteristic?,
    specifiedTimeout: DispatchTimeInterval

    fileprivate var disconnectSubKey: UUID? = nil

    public fileprivate(set) var status: GattRequestStatus = .disconnected

    fileprivate let operationsQueue = DispatchQueue(label:"com.xyfindables.sdk.XYGattRequestOperationsQueue")

    fileprivate static let callTimeout: DispatchTimeInterval = .seconds(18)
    fileprivate static let queue = DispatchQueue(label:"com.xyfindables.sdk.XYGattRequestTimeoutQueue")
    fileprivate var timer: DispatchSourceTimer?

    init(_ serviceCharacteristic: XYServiceCharacteristic, timeout: DispatchTimeInterval? = nil) {
        self.serviceCharacteristic = serviceCharacteristic
        self.specifiedTimeout = timeout ??  GattRequest.callTimeout
        super.init()
    }

    func delegateKey(deviceUuid: UUID) -> String {
        return ["GC", deviceUuid.uuidString, serviceCharacteristic.characteristicUuid.uuidString].joined(separator: ":")
    }

    func get(from device: XYBluetoothDevice) -> Promise<Data?> {
        var operationPromise = Promise<Data?>.pending()
        guard let peripheral = device.peripheral, peripheral.state == .connected else {
            operationPromise.reject(XYBluetoothError.notConnected)
            return operationPromise
        }

        // If we disconnect at any point in the request, we stop the timeout and reject the promise
        self.disconnectSubKey = XYFinderDeviceEventManager.subscribe(to: [.disconnected]) { [weak self] event in
            XYFinderDeviceEventManager.unsubscribe(to: [.disconnected], referenceKey: self?.disconnectSubKey)
            guard let device = self?.device as? XYFinderDevice, device == event.device else { return }
            self?.timer = nil
            self?.status = .disconnected
            self?.readPromise.reject(XYBluetoothError.peripheralDisconected(state: device.peripheral?.state))
            operationPromise.reject(XYBluetoothError.peripheralDisconected(state: device.peripheral?.state))
        }

        print("START Get: \(device.id.shortId) for Service: \(self.serviceCharacteristic.displayName)")

        // Create timeout using the operation queue. Self-cleaning if we timeout
        timer = DispatchSource.singleTimer(interval: self.specifiedTimeout, queue: GattRequest.queue) { [weak self] in
            guard let strong = self else { return }
            print("TIMEOUT Get: \(device.id.shortId) for Service: \(strong.serviceCharacteristic.displayName)")
            if let device = self as? XYFinderDevice {
                XYFinderDeviceEventManager.report(events: [.timedOut(device: device, type: .getOperation)])
            }
            strong.timer = nil
            strong.status = .timedOut
            strong.readPromise.reject(XYBluetoothError.timedOut)
        }

        // Assign the pending operation promise to the results from getting services/characteristics and
        // reading the result from the characteristic. Always unsubscribe from the delegate to ensure the
        // request object is properly cleaned up by ARC. Catch errors and propagate them to the caller
        operationPromise = self.getCharacteristic(device).then(on: operationsQueue) { _ in
            self.read(device)
        }.always(on: operationsQueue) {
            device.unsubscribe(for: self.delegateKey(deviceUuid: peripheral.identifier))
            self.timer = nil
            XYFinderDeviceEventManager.unsubscribe(to: [.disconnected], referenceKey: self.disconnectSubKey)
            print("ALWAYS Get: \(device.id.shortId) for Service: \(self.serviceCharacteristic.displayName)")
        }.catch(on: operationsQueue) { error in
            operationPromise.reject(error)
        }.catch(on: operationsQueue) { error in
            self.characteristicPromise.reject(error)
        }

        return operationPromise
    }

    func set(to device: XYBluetoothDevice, valueObj: XYBluetoothResult, withResponse: Bool = true) -> Promise<Void> {
        var operationPromise = Promise<Void>.pending()
        guard let peripheral = device.peripheral, peripheral.state == .connected else {
            operationPromise.reject(XYBluetoothError.notConnected)
            return operationPromise
        }

        // If we disconnect at any point in the request, we stop the timeout and reject the promise
        self.disconnectSubKey = XYFinderDeviceEventManager.subscribe(to: [.disconnected]) { [weak self] event in
            XYFinderDeviceEventManager.unsubscribe(to: [.disconnected], referenceKey: self?.disconnectSubKey)
            guard let device = self?.device as? XYFinderDevice, device == event.device else { return }
            self?.timer = nil
            self?.status = .disconnected
            self?.writePromise.reject(XYBluetoothError.peripheralDisconected(state: device.peripheral?.state))
            operationPromise.reject(XYBluetoothError.peripheralDisconected(state: device.peripheral?.state))
        }

        print("START Set: \(device.id.shortId) for Service: \(self.serviceCharacteristic.displayName)")

        // Create timeout using the operation queue. Self-cleaning if we timeout
        timer = DispatchSource.singleTimer(interval: self.specifiedTimeout, queue: GattRequest.queue) { [weak self] in
            guard let strong = self else { return }
            print("TIMEOUT Set: \(device.id.shortId) for Service: \(strong.serviceCharacteristic.displayName)")
            if let device = self as? XYFinderDevice {
                XYFinderDeviceEventManager.report(events: [.timedOut(device: device, type: .setOperation)])
            }
            strong.timer = nil
            strong.status = .timedOut
            strong.writePromise.reject(XYBluetoothError.timedOut)
        }

        // Assign the pending operation promise to the results from getting services/characteristics and
        // reading the result from the characteristic. Always unsubscribe from the delegate to ensure the
        // request object is properly cleaned up by ARC. Catch errors and propagate them to the caller
        operationPromise = self.getCharacteristic(device).then(on: operationsQueue) { _ in
            self.write(device, data: valueObj, withResponse: withResponse)
        }.always(on: operationsQueue) {
            device.unsubscribe(for: self.delegateKey(deviceUuid: peripheral.identifier))
            self.timer = nil
            XYFinderDeviceEventManager.unsubscribe(to: [.disconnected], referenceKey: self.disconnectSubKey)
            print("ALWAYS Set: \(device.id.shortId) for Service: \(self.serviceCharacteristic.displayName)")
        }.catch(on: operationsQueue) { error in
            operationPromise.reject(error)
        }.catch(on: operationsQueue) { error in
            self.characteristicPromise.reject(error)
        }

        return operationPromise
    }

    func notify(for device: XYBluetoothDevice, enabled: Bool) -> Promise<Void> {
        var operationPromise = Promise<Void>.pending()
        guard let peripheral = device.peripheral, peripheral.state == .connected else {
            operationPromise.reject(XYBluetoothError.notConnected)
            return operationPromise
        }

        // If we disconnect at any point in the request, we stop the timeout and reject the promise
        self.disconnectSubKey = XYFinderDeviceEventManager.subscribe(to: [.disconnected]) { [weak self] event in
            XYFinderDeviceEventManager.unsubscribe(to: [.disconnected], referenceKey: self?.disconnectSubKey)
            guard let device = self?.device as? XYFinderDevice, device == event.device else { return }
            self?.timer = nil
            self?.status = .disconnected
            self?.notifyPromise.reject(XYBluetoothError.peripheralDisconected(state: device.peripheral?.state))
            operationPromise.reject(XYBluetoothError.peripheralDisconected(state: device.peripheral?.state))
        }

        print("START Notify: \(device.id.shortId) for Service: \(self.serviceCharacteristic.displayName)")

        // Create timeout using the operation queue. Self-cleaning if we timeout
        timer = DispatchSource.singleTimer(interval: self.specifiedTimeout, queue: GattRequest.queue) { [weak self] in
            guard let strong = self else { return }
            print("TIMEOUT Notify: \(device.id.shortId) for Service: \(strong.serviceCharacteristic.displayName)")
            if let device = self as? XYFinderDevice {
                XYFinderDeviceEventManager.report(events: [.timedOut(device: device, type: .notifyOperation)])
            }
            strong.timer = nil
            strong.status = .timedOut
            strong.notifyPromise.reject(XYBluetoothError.timedOut)
            operationPromise.reject(XYBluetoothError.timedOut)
        }

        // Assign the pending operation promise to the results from getting services/characteristics and
        // reading the result from the characteristic. Always unsubscribe from the delegate to ensure the
        // request object is properly cleaned up by ARC. Catch errors and propagate them to the caller
        operationPromise = self.getCharacteristic(device).then(on: operationsQueue) { _ in
            self.setNotify(device, enabled: enabled)
        }.always(on: operationsQueue) {
            device.unsubscribe(for: self.delegateKey(deviceUuid: peripheral.identifier))
            self.timer = nil
            XYFinderDeviceEventManager.unsubscribe(to: [.disconnected], referenceKey: self.disconnectSubKey)
            print("ALWAYS Notify: \(device.id.shortId) for Service: \(self.serviceCharacteristic.displayName)")
        }.catch(on: operationsQueue) { error in
            operationPromise.reject(error)
        }.catch(on: operationsQueue) { error in
            self.characteristicPromise.reject(error)
        }

        return operationPromise
    }
}

// MARK: Get service and characteristic
internal extension GattRequest {

    func getCharacteristic(_ device: XYBluetoothDevice) -> Promise<Void> {
        guard
            self.status != .timedOut,
            let peripheral = device.peripheral,
            peripheral.state == .connected
            else {
                self.characteristicPromise.reject(XYBluetoothError.notConnected)
                return self.characteristicPromise
            }

        print("START Discover Services: \(device.id.shortId) for Service: \(self.serviceCharacteristic.displayName)")

        self.device = device
        device.subscribe(self, key: self.delegateKey(deviceUuid: peripheral.identifier))

        if  // Has this already been located and cached to the peripheral?
            let service = self.device?.peripheral?.services?.first(where: { $0.uuid == self.serviceCharacteristic.serviceUuid }),
            let characteristic = service.characteristics?.first(where: { $0.uuid == self.serviceCharacteristic.characteristicUuid }) {
            self.characteristic = characteristic
            self.characteristicPromise.fulfill(())
        } else {
            self.status = .discoveringServices
            peripheral.discoverServices([self.serviceCharacteristic.serviceUuid])
        }

        return self.characteristicPromise
    }
}

// MARK: Internal getters + setters
private extension GattRequest {

    func read(_ device: XYBluetoothDevice) -> Promise<Data?> {
        guard
            self.status != .timedOut,
            let characteristic = self.characteristic,
            let peripheral = device.peripheral,
            peripheral.state == .connected
            else {
                self.readPromise.reject(XYBluetoothError.notConnected)
                return self.readPromise
            }

        print("GET: read")

        self.status = .reading
        peripheral.readValue(for: characteristic)

        return self.readPromise
    }

    func write(_ device: XYBluetoothDevice, data: XYBluetoothResult, withResponse: Bool) -> Promise<Void> {
        guard
            self.status != .timedOut,
            let characteristic = self.characteristic,
            let peripheral = device.peripheral,
            peripheral.state == .connected,
            let data = data.data
            else {
                self.writePromise.reject(XYBluetoothError.notConnected)
                return self.writePromise
            }

        print("Gatt(set): write")

        self.status = .writing
        peripheral.writeValue(data, for: characteristic, type: withResponse ? .withResponse : .withoutResponse)

        if !withResponse {
            print("Gatt(set): set as no response, done")
            writePromise.fulfill(())
        }

        return self.writePromise
    }

    func setNotify(_ device: XYBluetoothDevice, enabled: Bool) -> Promise<Void> {
        guard
            self.status != .timedOut,
            let characteristic = self.characteristic,
            let peripheral = device.peripheral,
            peripheral.state == .connected
            else {
                self.notifyPromise.reject(XYBluetoothError.notConnected)
                return self.notifyPromise
            }

        print("Gatt(notify): notify")

        self.status = .notifying
        peripheral.setNotifyValue(enabled, for: characteristic)

        return self.notifyPromise
    }

}

extension GattRequest: CBPeripheralDelegate {

    // Handles all service and characteristic common validation for delegate callbacks
    private func serviceCharacteristicDelegateValidation(_ peripheral: CBPeripheral, error: Error?) -> Bool {
        guard self.status != .disconnected || self.status != .timedOut else { return false }

        guard error == nil else {
            self.characteristicPromise.reject(XYBluetoothError.cbPeripheralDelegateError(error!))
            return false
        }

        guard
            self.device?.peripheral == peripheral
            else {
                self.characteristicPromise.reject(XYBluetoothError.mismatchedPeripheral)
                return false
        }

        return true
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        operationsQueue.async {
            guard self.serviceCharacteristicDelegateValidation(peripheral, error: error) else { return }

            guard
                let service = peripheral.services?.filter({ $0.uuid == self.serviceCharacteristic.serviceUuid }).first
                else {
                    self.characteristicPromise.reject(XYBluetoothError.serviceNotFound)
                    return
            }

            print("START Discover Characteristics: \(self.device?.id.shortId ?? "") for Service: \(self.serviceCharacteristic.displayName)")

            self.status = .discoveringCharacteristics
            peripheral.discoverCharacteristics([self.serviceCharacteristic.characteristicUuid], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        operationsQueue.async {
            guard self.serviceCharacteristicDelegateValidation(peripheral, error: error) else { return }

            guard
                let characteristic = service.characteristics?.filter({ $0.uuid == self.serviceCharacteristic.characteristicUuid }).first
                else {
                    self.characteristicPromise.reject(XYBluetoothError.characteristicNotFound)
                    return
                }

            print("START Characteristics Discovered: \(self.device?.id.shortId ?? "") for Service: \(self.serviceCharacteristic.displayName)")

            self.characteristic = characteristic
            self.characteristicPromise.fulfill(())
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        operationsQueue.async {
            guard self.status != .disconnected || self.status != .timedOut else { return }

            guard error == nil else {
                self.readPromise.reject(XYBluetoothError.cbPeripheralDelegateError(error!))
                return
            }

            guard
                self.device?.peripheral == peripheral
                else {
                    self.readPromise.reject(XYBluetoothError.mismatchedPeripheral)
                    return
                }

            guard characteristic.uuid == self.serviceCharacteristic.characteristicUuid
                else {
                    self.readPromise.reject(XYBluetoothError.characteristicNotFound)
                    return
                }

            guard
                let data = characteristic.value
                else {
                    self.readPromise.reject(XYBluetoothError.dataNotPresent)
                    return
                }

            print("Gatt(get): read delegate called, done \(self.device?.id.shortId ?? "") for Service: \(self.serviceCharacteristic.displayName)")

            self.status = .completed
            self.readPromise.fulfill(data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        operationsQueue.async {
            guard self.status != .disconnected || self.status != .timedOut else { return }

            guard error == nil else {
                self.writePromise.reject(XYBluetoothError.cbPeripheralDelegateError(error!))
                return
            }

            guard
                self.device?.peripheral == peripheral
                else {
                    self.writePromise.reject(XYBluetoothError.mismatchedPeripheral)
                    return
                }

            guard characteristic.uuid == self.serviceCharacteristic.characteristicUuid
                else {
                    self.writePromise.reject(XYBluetoothError.characteristicNotFound)
                    return
                }

            print("Gatt(set): write delegate called, done \(self.device?.id.shortId ?? "") for Service: \(self.serviceCharacteristic.displayName)")

            self.writePromise.fulfill(())
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        operationsQueue.async {
            guard self.status != .disconnected || self.status != .timedOut else { return }

            guard error == nil else {
                self.notifyPromise.reject(XYBluetoothError.cbPeripheralDelegateError(error!))
                return
            }

            guard
                self.device?.peripheral == peripheral
                else {
                    self.notifyPromise.reject(XYBluetoothError.mismatchedPeripheral)
                    return
                }

            print("Gatt(notify): notify delegate called, done  \(self.device?.id.shortId ?? "") for Service: \(self.serviceCharacteristic.displayName)")

            self.notifyPromise.fulfill(())
        }
    }

}
