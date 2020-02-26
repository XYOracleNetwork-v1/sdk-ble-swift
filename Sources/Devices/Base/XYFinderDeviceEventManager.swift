//
//  XYFinderDeviceEventManager.swift
//  XYBleSdk
//
//  Created by Darren Sutherland on 10/11/18.
//  Copyright © 2018 XY - The Findables Company. All rights reserved.
//

import Foundation

public typealias XYFinderDeviceEventNotifier = (_ event: XYFinderEventNotification) -> Void

internal struct XYFinderDeviceEventDirective {
    let
    referenceKey: UUID = UUID.init(),
    handler: XYFinderDeviceEventNotifier,
    device: XYBluetoothDevice?
}

public class XYFinderDeviceEventManager {

    fileprivate static var handlerRegistry = [XYFinderEvent: [XYFinderDeviceEventDirective]]()

    fileprivate static let managerQueue = DispatchQueue(label: "com.xyfindables.sdk.XYFinderDeviceEventManagerQueue")

    // Notify those directives that want all events and those that subscribe to the event's device
    public static func report(events: [XYFinderEventNotification]) {
        events.forEach { event in
            handlerRegistry[event.toEvent]?
                .filter { $0.device == nil || $0.device?.id == event.device.id }
                .forEach { $0.handler(event) }
        }
    }

    // Equivalent to subscribing to every device's events
    public static func subscribe(to events: [XYFinderEvent], handler: @escaping XYFinderDeviceEventNotifier) -> UUID {
        return subscribe(to: events, for: nil, handler: handler)
    }

    // Subscribe to a single device's events. This will simply filter when it comes to reporting to the handlers
    public static func subscribe(to events: [XYFinderEvent], for device: XYBluetoothDevice?, handler: @escaping XYFinderDeviceEventNotifier) -> UUID {
        let directive = XYFinderDeviceEventDirective(handler: handler, device: device)
        managerQueue.async {
            events.forEach { event in
                handlerRegistry[event] == nil ?
                    handlerRegistry[event] = [directive] :
                    handlerRegistry[event]?.append(directive)
            }
        }

        return directive.referenceKey
    }

    public static func unsubscribe(to events: [XYFinderEvent], referenceKey: UUID?) {
        managerQueue.async {
            guard let key = referenceKey else { return }
            for event in events {
                guard let eventsInRegistry = handlerRegistry[event] else { continue }
                let updatedArray = eventsInRegistry.filter { $0.referenceKey != key }
                self.handlerRegistry[event] = updatedArray
            }
        }
    }

}
