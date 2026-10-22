//
//  BackgroundAudioService.swift
//  SideStore
//
//  Created by Magesh K on 15/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import AVFoundation

public final class BackgroundAudioService: BackgroundService, @unchecked Sendable {
    public static let shared = BackgroundAudioService()

    public var isRunning: Bool {
        player?.isPlaying ?? false
    }

    private var player: AVAudioPlayer?
    private var interruptionObserver: (any NSObjectProtocol)?
    private let lock = NSLock()

    public init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleInterruption(notification: notification)
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        player?.stop()
    }

    @discardableResult
    public func start() -> Bool {
        BackgroundLocationService.shared.stop()

        lock.lock()
        defer { lock.unlock() }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if player == nil {
                let silentData = Self.generateSilentWAV()
                player = try AVAudioPlayer(data: silentData)
                player?.numberOfLoops = -1
                player?.volume = 0.01
                player?.prepareToPlay()
            }
            player?.play()
            return true
        } catch {
            print("BackgroundAudioService start failed: \(error)")
            return false
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        player?.stop()
        player = nil
    }

    public func prepare() async -> Bool {
        true
    }

    private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        if type == .ended {
            lock.lock()
            defer { lock.unlock() }
            guard player != nil, UserDefaults.standard.isBackgroundServiceEnabled, UserDefaults.standard.backgroundServiceMode == .audio else {
                return
            }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                player?.play()
            } catch {
                print("Failed to reactivate audio session: \(error)")
            }
        }
    }

    /*
        wav pcm header and payload format taken from: 
        https://ccrma.stanford.edu/courses/422-winter-2014/projects/WaveFormat/

        0                   1                   2                   3
        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        |   "R"   "I"   "F"   "F"       |        ChunkSize (36+data)    |
        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        |   "W"   "A"   "V"   "E"       |   "f"   "m"   "t"   " "       |
        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        |      Subchunk1Size (16)       |  Format (1=PCM) | Channels (1)|
        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        |          SampleRate (8000 Hz) |          ByteRate (16000)     |
        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        |  BlockAlign(2)| BitsSample(16)|   "d"   "a"   "t"   "a"       |
        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        |          DataSize (16000)     | Zero Bytes (Pure Silence)...  |
        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    */
    private static func generateSilentWAV() -> Data {
        let sampleRate:    UInt32 = 8000
        let numChannels:   UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples:    UInt32 = 8000
        let dataSize:      UInt32 = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let chunkSize:     UInt32 = 36 + dataSize
        let byteRate:      UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign:    UInt16 = numChannels * (bitsPerSample / 8)

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: chunkSize.littleEndian)     { data.append(contentsOf: $0) }
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        withUnsafeBytes(of: UInt32(16).littleEndian)    { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian)     { data.append(contentsOf: $0) }
        withUnsafeBytes(of: numChannels.littleEndian)   { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sampleRate.littleEndian)    { data.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian)      { data.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian)    { data.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataSize.littleEndian)      { data.append(contentsOf: $0) }
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}
