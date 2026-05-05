//
//  SystemTTSClient.swift
//  leanring-buddy
//
//  Simple wrapper around macOS system text-to-speech (AVSpeechSynthesizer).
//  Provides `isPlaying` so the app can coordinate UI state + transient overlay timing.
//

import AVFoundation
import Foundation

final class SystemTTSClient: NSObject {
    private let speechSynthesizer = AVSpeechSynthesizer()
    @MainActor private(set) var isPlaying: Bool = false

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    @MainActor
    func speakText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stopPlayback()
        isPlaying = true

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    @MainActor
    func stopPlayback() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
    }
}

extension SystemTTSClient: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
