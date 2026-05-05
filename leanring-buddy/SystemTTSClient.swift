//
//  SystemTTSClient.swift
//  leanring-buddy
//
//  Simple wrapper around macOS system text-to-speech (NSSpeechSynthesizer).
//  Provides `isPlaying` so the app can coordinate UI state + transient overlay timing.
//

import AppKit
import Foundation

@MainActor
final class SystemTTSClient: NSObject, NSSpeechSynthesizerDelegate {
    private let speechSynthesizer = NSSpeechSynthesizer()
    private(set) var isPlaying: Bool = false

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func speakText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stopPlayback()
        isPlaying = true
        speechSynthesizer.startSpeaking(text)
    }

    func stopPlayback() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking()
        }
        isPlaying = false
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        isPlaying = false
    }
}

