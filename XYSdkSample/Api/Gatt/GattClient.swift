//
//  GattClient.swift
//  XYSdkSample
//
//  Created by Darren Sutherland on 9/12/18.
//  Copyright © 2018 Darren Sutherland. All rights reserved.
//

import Foundation
import CoreBluetooth
import PromiseKit

enum GattError: Error {
    case notConnected
    case mismatchedPeripheral
    case serviceNotFound
    case characteristicNotFound
    case dataNotPresent
}

enum GattOperation: String {
    case read
    case write
}

// Used for proper upacking of the data result from reading characteristcs
public enum GattCharacteristicType {
    case string
    case integer
    case byte
}

class GattClient: NSObject {
    // Promises that resolve locating the characteristic and returning the
    fileprivate var
    (characteristicPromise, characteristicSeal) = Promise<Void>.pending(),
    (operationPromise, operationSeal) = Promise<Data?>.pending()

    fileprivate let serviceCharacteristic: ServiceCharacteristic

    fileprivate var
    device: XYBluetoothDevice?,
    service: CBService?,
    characteristic: CBCharacteristic?

    init(_ serviceCharacteristic: ServiceCharacteristic) {
        self.serviceCharacteristic = serviceCharacteristic
    }
    
    deinit {
        // TODO remove any unfulfilled promiseses if something goes wrong
//        if !characteristicPromise.isFulfilled { characteristicSeal.reject()
    }
    
    // TODO: Change to a per-session token for the key
    func delegateKey(deviceUuid: UUID) -> String {
        return ["GC", deviceUuid.uuidString, serviceCharacteristic.uuid.uuidString, serviceCharacteristic.characteristic.uuidString].joined(separator: ":")
    }

    func get(from device: XYBluetoothDevice, valueObj: XYBluetoothValue) -> Promise<Void> {
        return firstly {
            self.getCharacteristic(device)
        }.then {
            self.read(device)
        }.done { result in
            valueObj.setData(result)
        }.ensure {
            self.device?.unsubscribe(for: self.delegateKey(deviceUuid: device.uuid))
        }
    }

    func set(to device: XYBluetoothDevice, valueObj: XYBluetoothValue, withResponse: Bool = true) -> Promise<Void> {
        return firstly {
            self.getCharacteristic(device)
        }.then {
            self.write(device, data: valueObj, withResponse: withResponse)
        }.ensure {
            self.device?.unsubscribe(for: self.delegateKey(deviceUuid: device.uuid))
        }
    }
    
    func getCharacteristic(_ device: XYBluetoothDevice) -> Promise<Void> {
        guard
            let peripheral = device.getPeripheral(),
            peripheral.state == .connected
            else { return Promise(error: GattError.notConnected) }
        
        self.device = device
        device.subscribe(self, key: self.delegateKey(deviceUuid: device.uuid))
        peripheral.discoverServices(nil)
        
        return self.characteristicPromise
    }
}

// MARK: Internal getters
private extension GattClient {

    func read(_ device: XYBluetoothDevice) -> Promise<Data?> {
        guard
            let characteristic = self.characteristic,
            let peripheral = device.getPeripheral(),
            peripheral.state == .connected
            else { return Promise(error: GattError.notConnected) }

        peripheral.readValue(for: characteristic)

        return self.operationPromise
    }

}

// MARK: Internal setters
private extension GattClient {

    func write(_ device: XYBluetoothDevice, data: XYBluetoothValue, withResponse: Bool) -> Promise<Void> {
        guard
            let characteristic = self.characteristic,
            let peripheral = device.getPeripheral(),
            peripheral.state == .connected,
            let data = data.data
            else { return Promise(error: GattError.notConnected) }

        peripheral.writeValue(data, for: characteristic, type: withResponse ? .withResponse : .withoutResponse)

        return self.operationPromise.asVoid()
    }

}

extension GattClient: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard
            self.device?.getPeripheral() == peripheral
            else { self.characteristicSeal.reject(GattError.mismatchedPeripheral); return }

        guard
            let service = peripheral.services?.filter({ $0.uuid == self.serviceCharacteristic.uuid }).first
            else { self.characteristicSeal.reject(GattError.serviceNotFound); return }

        peripheral.discoverCharacteristics([self.serviceCharacteristic.characteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard
            self.device?.getPeripheral() == peripheral
            else { self.characteristicSeal.reject(GattError.mismatchedPeripheral); return }

        guard
            let characteristic = service.characteristics?.filter({ $0.uuid == self.serviceCharacteristic.characteristic }).first
            else { self.characteristicSeal.reject(GattError.characteristicNotFound); return }

        self.characteristic = characteristic
        
        characteristicSeal.fulfill(())
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard
            self.device?.getPeripheral() == peripheral
            else { self.operationSeal.reject(GattError.mismatchedPeripheral); return }

        guard characteristic.uuid == self.serviceCharacteristic.characteristic
            else { self.operationSeal.reject(GattError.characteristicNotFound); return }

        guard
            let data = characteristic.value
            else { self.operationSeal.reject(GattError.dataNotPresent); return }

        operationSeal.fulfill(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard
            self.device?.getPeripheral() == peripheral
            else { self.operationSeal.reject(GattError.mismatchedPeripheral); return }

        operationSeal.fulfill(nil)
    }

}
