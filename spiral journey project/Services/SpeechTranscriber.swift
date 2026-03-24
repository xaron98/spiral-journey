import Foundation
import Speech
import AVFoundation

/// On-device speech-to-text transcription using SFSpeechRecognizer.
/// Streams recognized text in real-time while the user speaks.
@MainActor
@Observable
final class SpeechTranscriber {

    var isRecording = false
    var transcript = ""
    var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    init() {
        recognizer = SFSpeechRecognizer()
    }

    /// Request microphone + speech recognition permissions.
    /// Returns true if both are authorized.
    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            errorMessage = "Speech recognition not authorized"
            return false
        }

        let audioStatus = await AVAudioApplication.requestRecordPermission()
        guard audioStatus else {
            errorMessage = "Microphone not authorized"
            return false
        }

        return true
    }

    /// Start real-time transcription. Appends recognized text to `transcript`.
    func startRecording() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition unavailable"
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        self.audioEngine = engine
        self.request = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopRecording()
                }
            }
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            try engine.start()
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = "Audio engine failed: \(error.localizedDescription)"
            stopRecording()
        }
    }

    /// Stop transcription and clean up audio resources.
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        request = nil
        recognitionTask = nil
        isRecording = false
    }
}
