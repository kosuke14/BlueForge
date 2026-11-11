//
//  ReceiverPipeline.swift
//  BlueForge
//
//  iPhone-as-receiver: BLE peripheral receives encoded frames, the selected
//  codec decodes them, and AVAudioEngine plays the PCM.
//

import Foundation
import CoreBluetooth
import Combine
import os

final class ReceiverPipeline: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var requestedOutputRate: Double = 0
    @Published private(set) var actualOutputRate: Double = 0
    @Published private(set) var outputRoute: String = ""

    private let codecManager: CodecManager
    private let peripheral = BLEAudioPeripheral()
    private let playback = AudioPlayback()
    private let log = Logger(subsystem: "com.blueforge", category: "receiver")
    private var cancellables = Set<AnyCancellable>()

    var peripheralState: CBManagerState { peripheral.state }
    var isAdvertising: Bool { peripheral.isAdvertising }
    var subscriberCount: Int { peripheral.subscriberCount }

    init(codecManager: CodecManager) {
        self.codecManager = codecManager
        peripheral.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
        peripheral.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning else { return }
        do {
            let format = codecManager.pcmFormat
            try playback.start(sampleRate: format.sampleRate, channels: format.channels)
            peripheral.start()
            isRunning = true
            lastError = nil
            requestedOutputRate = playback.requestedRate
            actualOutputRate = playback.actualRate
            outputRoute = playback.routeName
        } catch {
            lastError = error.localizedDescription
            log.error("receiver start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        peripheral.stop()
        playback.stop()
        isRunning = false
    }

    private func handle(_ frame: Data) {
        guard let codec = codecManager.current else { return }
        do {
            let pcm = try codec.decode(frame: frame)
            playback.play(pcm: pcm)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
            log.error("decode failed: \(error.localizedDescription)")
        }
    }
}
