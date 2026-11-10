//
//  BLEAudioService.swift
//  BlueForge
//
//  Streams encoded audio frames over BLE to a paired receiver (custom firmware).
//  Important: jailed iOS cannot alter classic A2DP codec negotiation. The only
//  way an app can move audio over Bluetooth is via BLE (Core Bluetooth) with a
//  custom GATT service. The receiver must implement the matching service.
//

import Foundation
import CoreBluetooth
import Combine
import os

final class BLEAudioService: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    static let audioCharUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abd")
    static let controlCharUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abe")

    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var connected: Bool = false
    @Published private(set) var discoveredPeripherals: [CBPeripheral] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var audioChar: CBCharacteristic?
    private let queue = DispatchQueue(label: "blueforge.ble")
    private let log = Logger(subsystem: "com.blueforge", category: "ble")
    private var reconnectAttempts = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() { central.stopScan() }

    func connect(_ p: CBPeripheral) {
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    /// Send one encoded audio frame. Frames are chunked to fit MTU.
    func sendFrame(_ data: Data) {
        guard let p = peripheral, let ch = audioChar else { return }
        let mtu = p.maximumWriteValueLength(for: .withoutResponse)
        var offset = 0
        while offset < data.count {
            let len = min(mtu, data.count - offset)
            let chunk = data.subdata(in: offset..<(offset+len))
            p.writeValue(chunk, for: ch, type: .withoutResponse)
            offset += len
        }
    }
}

extension BLEAudioService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { self.state = central.state }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        DispatchQueue.main.async {
            if !self.discoveredPeripherals.contains(peripheral) {
                self.discoveredPeripherals.append(peripheral)
            }
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
        DispatchQueue.main.async { self.connected = true }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.warning("disconnected: \(error?.localizedDescription ?? "none")")
        DispatchQueue.main.async { self.connected = false }
        let target = peripheral
        self.peripheral = nil
        // Best-effort reconnect with backoff.
        if reconnectAttempts < 3 {
            reconnectAttempts += 1
            queue.asyncAfter(deadline: .now() + .seconds(reconnectAttempts)) { [weak self] in
                guard let self = self else { return }
                self.central.connect(target, options: nil)
            }
        }
    }
}

extension BLEAudioService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svcs = peripheral.services else { return }
        for s in svcs where s.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.audioCharUUID, Self.controlCharUUID], for: s)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == Self.audioCharUUID { audioChar = c }
        }
    }
}
