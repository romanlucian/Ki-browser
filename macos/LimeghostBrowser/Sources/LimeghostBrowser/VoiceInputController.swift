import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class VoiceInputController: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case ready
        case unavailable(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionID: UUID?
    private var hasInstalledTap = false

    var isListening: Bool { state == .listening }

    var presentsStatus: Bool { state != .idle }

    var statusMessage: String {
        switch state {
        case .idle: return ""
        case .requestingPermission: return "Requesting microphone and speech access…"
        case .listening: return transcript.isEmpty ? "Listening… Speak a search or web address." : "Listening… Review the live transcript before submitting."
        case .ready: return "Voice input stopped. Review the text, then press Return or Go."
        case .unavailable(let message), .failed(let message): return message
        }
    }

    func toggle() {
        if state == .listening || state == .requestingPermission {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        endCapture(cancelTask: true)
        transcript = ""
        state = .requestingPermission
        let identifier = UUID()
        sessionID = identifier

        guard await requestSpeechAccess(), sessionID == identifier else {
            if sessionID == identifier {
                sessionID = nil
                state = .unavailable("Speech recognition permission is required. You can continue typing normally.")
            }
            return
        }
        guard await requestMicrophoneAccess(), sessionID == identifier else {
            if sessionID == identifier {
                sessionID = nil
                state = .unavailable("Microphone permission is required. You can continue typing normally.")
            }
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            sessionID = nil
            state = .unavailable("Speech recognition is not currently available. You can continue typing normally.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            sessionID = nil
            state = .unavailable("On-device English recognition is not available on this Mac. This prototype will not upload microphone audio.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .search
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            sessionID = nil
            recognitionRequest = nil
            state = .failed("No usable microphone input was found.")
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasInstalledTap = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == identifier else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.endCapture(cancelTask: false)
                        self.state = .ready
                    }
                } else if let error {
                    self.endCapture(cancelTask: false)
                    self.state = .failed("Voice input stopped: \(error.localizedDescription)")
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            state = .listening
        } catch {
            endCapture(cancelTask: true)
            state = .failed("The microphone could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        let hadTranscript = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        endCapture(cancelTask: true)
        state = hadTranscript ? .ready : .idle
    }

    func dismissStatus() {
        if state != .listening && state != .requestingPermission {
            state = .idle
        }
    }

    private func endCapture(cancelTask: Bool) {
        sessionID = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if cancelTask { recognitionTask?.cancel() }
        recognitionTask = nil
    }

    private func requestSpeechAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default: return false
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }
}
