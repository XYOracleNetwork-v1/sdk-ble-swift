//
//  ViewController.swift
//  XYSdkSample
//
//  Created by Darren Sutherland on 9/6/18.
//  Copyright © 2018 Darren Sutherland. All rights reserved.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController {

    @IBOutlet weak var spinner: UIActivityIndicatorView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var deviceLabel: UILabel!
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var deviceName: UILabel!
    @IBOutlet weak var deviceStatus: UILabel!
    @IBOutlet weak var notifyLabel: UILabel!

    fileprivate let scanner = XYSmartScan.instance
    fileprivate var central = XYCentral.instance
    fileprivate var xy4Device: XYBluetoothDevice?

    @IBOutlet weak var rangedDevicesTableView: UITableView!

    fileprivate var rangedDevices = [XY4BluetoothDevice]()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.spinner.stopAnimating()
        self.notifyLabel.alpha = 0.0

        rangedDevicesTableView.dataSource = self
        rangedDevicesTableView.delegate = self
    }

    @IBAction func connectTapped(_ sender: Any) {
        self.spinner.startAnimating()
        central.setDelegate(self, key: "ViewController")
        central.enable()
    }

    @IBAction func notifyTapped(_ sender: Any) {
        guard let device = self.xy4Device else { return }
        device.subscribe(to: PrimaryService.buttonState, delegate: ("ViewController", self))
    }
    
    @IBAction func scanStart(_ sender: Any) {
        scanner.start()
        scanner.setDelegate(self, key: "ViewController")
    }

    @IBAction func scanStop(_ sender: Any) {
        scanner.stop()
        rangedDevices.removeAll()
        self.countLabel.text = nil
        rangedDevicesTableView.reloadData()
    }

    @IBAction func disconnectTapped(_ sender: Any) {
        xy4Device?.disconnect()
    }

    @IBAction func actionTapped(_ sender: Any) {
        guard let device = xy4Device else { return }
        self.spinner.startAnimating()

        let request = [
            DeviceInformationService.firmwareRevisionString.read,
            DeviceInformationService.modelNumberString.read,
            DeviceInformationService.hardwareRevisionString.read,
            PrimaryService.buzzer.write(XYBluetoothValue(PrimaryService.buzzer, data: Data([UInt8(0x0b), 0x03]))),
            BatteryService.level.read
        ]

        device.request(for: request, complete: self.processResult)
    }

    func processResult(_ results: [XYBluetoothValue]) -> Void {
        self.spinner.stopAnimating()

        let modalViewController = ActionResultViewController()
        modalViewController.set(results: results)
        modalViewController.modalPresentationStyle = .overCurrentContext
        present(modalViewController, animated: true, completion: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
//        guard let myDevice = xy4Device else { return }
//        scanner.startTracking(for: myDevice)
    }
}

extension ViewController: XYBluetoothDeviceNotifyDelegate {
    func update(for serviceCharacteristic: ServiceCharacteristic, value: XYBluetoothValue) {
        DispatchQueue.main.async {
            self.notifyLabel.alpha = 1.0
            UIView.animate(withDuration: 2.0) {
                self.notifyLabel.alpha = 0.0
            }
        }
    }
}

extension ViewController: XYSmartScanDelegate {
    func smartScan(location: XYLocationCoordinate2D) {

    }

    func smartScan(entered device: XYBluetoothDevice) {

    }

    func smartScan(exited device: XYBluetoothDevice) {

    }

    // Probably should change this to an array of what it's found
    func smartScan(detected device: XY4BluetoothDevice, signalStrength: Int) {
        DispatchQueue.main.async {
            if self.rangedDevices.contains(where: { $0.id == device.id }) {
                return
            }

            // Only show those in range
            if device.rssi != 0 && device.rssi > -95 {
                self.rangedDevices.append(device)
                self.rangedDevicesTableView.reloadData()
                self.countLabel.text = "\(self.rangedDevices.count)"
            }
        }
    }
}

extension ViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rangedDevices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "rangedDevicesCell")!

        let device = rangedDevices[indexPath.row]

        cell.textLabel?.text = "\(device.iBeacon?.major ?? 0) + \(device.iBeacon?.minor ?? 0)"

        return cell
    }
}

extension ViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let device = self.rangedDevices[safe: indexPath.row] else { return }

        guard central.state == .poweredOn else { return }

        deviceName.text = "\(device.iBeacon?.major ?? 0) + \(device.iBeacon?.minor ?? 0)"
        deviceStatus.text = "Scanning..."

        self.spinner.startAnimating()

        self.xy4Device = device

        central.scan() // TOOD add timeout
    }

}

extension ViewController: XYCentralDelegate {
    func timeout() {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.statusLabel.text = "Central timeout"
        }
    }

    func couldNotConnect(peripheral: XYPeripheral) {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.deviceStatus.text = "Could not connect"
        }
    }

    func stateChanged(newState: CBManagerState) {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.statusLabel.text = newState.toString
        }
    }

    func connected(peripheral: XYPeripheral) {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.deviceStatus.text = "Connected"
        }
    }

    func located(peripheral: XYPeripheral) {
        if xy4Device?.attachPeripheral(peripheral) ?? false {
            central.stop()
            central.connect(to: self.xy4Device!)
            DispatchQueue.main.async {
                self.deviceStatus.text = "Connecting..."
            }
        }
    }

    func disconnected(periperhal: XYPeripheral) {
        DispatchQueue.main.async {
            self.deviceStatus.text = "Disconnected"
        }
    }
}
