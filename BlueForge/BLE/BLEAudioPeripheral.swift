//
//  BLEAudioPeripheral.swift
//  BlueForge
//
//  Receiver side: advertises the BlueForge GATT service so another iPhone
//  (or any BLE central) can write encoded audio frames to it.
//

import Foundation
import CoreBluetooth
import os

final class BLEAudioPeripheral: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    static let audioCharUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abd")

    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var subscriberCount = 0

    /// Called on the BLE queue with one complete encoded frame.
    var onFrame: ((Data) -> Void)?

    private var manager: CBPeripheralManager?
    private var audioChar: CBMutableCharacteristic?
    private let queue = DispatchQueue(label: "blueforge.ble.peripheral")
    private let log = Logger(subsystem: "com.blueforge", category: "ble-rx")
    private var rxBuffer = Data()
    private var expectedLength: Int?

    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.manager == nil {
                self.manager = CBPeripheralManager(delegate: self, queue: self.queue)
            } else if self.manager?.state == .poweredOn {
                self.publishService()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.manager?.stopAdvertising()
            self.manager?.removeAllServices()
            self.rxBuffer.removeAll(keepingCapacity: true)
            self.expectedLength = nil
            DispatchQueue.main.async {
                self.isAdvertising = false
                self.subscriberCount = 0
            }
        }
    }

    private func publishService() {
        let characteristic = CBMutableCharacteristic(
            type: Self.audioCharUUID,
            properties: [.writeWithoutResponse, .notify],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        audioChar = characteristic
        manager?.removeAllServices()
        manager?.add(service)
    }

    private func startAdvertising() {
        manager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "BlueForge RX"
        ])
        DispatchQueue.main.async { self.isAdvertising = true }
    }

    /// Reassemble length-prefixed frames. A frame may be split across writes.
    private func ingest(_ data: Data) {
        rxBuffer.append(data)
        while true {
            if expectedLength == nil {
                guard rxBuffer.count >= 2 else { return }
                let header = Array(rxBuffer.prefix(2))
                let length = Int(header[0]) | (Int(header[1]) << 8)
                guard length > 0, length <= 8192 else {
                    log.error("invalid frame length \(length)")
                    rxBuffer.removeAll(keepingCapacity: true)
                    return
                }
                expectedLength = length
                rxBuffer.removeFirst(2)
            }
            guard let length = expectedLength, rxBuffer.count >= length else { return }
            let frame = Data(rxBuffer.prefix(length))
            rxBuffer.removeFirst(length)
            expectedLength = nil
            onFrame?(frame)
        }
    }
}

extension BLEAudioPeripheral: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        DispatchQueue.main.async { self.state = peripheral.state }
        if peripheral.state == .poweredOn {
            publishService()
        } else {
            DispatchQueue.main.async {
                self.isAdvertising = false
                self.subscriberCount = 0
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            log.error("add service failed: \(error.localizedDescription)")
            return
        }
        startAdvertising()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == Self.audioCharUUID,
                  let value = request.value, !value.isEmpty else { continue }
            ingest(value)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        DispatchQueue.main.async { self.subscriberCount += 1 }
        log.info("central subscribed: \(central.identifier.uuidString)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        DispatchQueue.main.async { self.subscriberCount = max(0, self.subscriberCount - 1) }
    }
}
