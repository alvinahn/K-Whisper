import Foundation
@preconcurrency import AVFoundation
import Combine

/// Records voice input to a 16-kHz mono WAV file using AVAudioRecorder.
/// AVAudioRecorder handles device setup, format conversion, and file output internally —
/// far less fragile than AVAudioEngine for the dictation use case.
@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum RecordingError: Error, LocalizedError {
        case unauthorized
        case engineFailed(String)
        case noInput
        case empty
        case fileMissing
        var errorDescription: String? {
            switch self {
            case .unauthorized:    return "Microphone permission was denied for Voxa. Open Settings → Privacy → Microphone and enable Voxa."
            case .engineFailed(let m): return "Audio engine failed: \(m)"
            case .noInput:         return "No audio input device available."
            case .empty:           return "No audio captured."
            case .fileMissing:     return "Recording finished but the audio file is missing."
            }
        }
    }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var levelRMS: Float = 0  // 0.0 – 1.0
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var startTime: Date?
    private var pollTimer: Timer?

    /// Begin recording. Throws if mic is unauthorized or the recorder fails to set up.
    func start() throws {
        guard !isRecording else { return }

        let auth = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.audio.info("AVCaptureDevice auth status: \(auth.rawValue)")
        if auth == .denied || auth == .restricted {
            throw RecordingError.unauthorized
        }

        let url = makeTempURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.isMeteringEnabled = true
            guard r.prepareToRecord() else {
                Log.audio.error("AVAudioRecorder.prepareToRecord returned false")
                throw RecordingError.engineFailed("prepareToRecord failed")
            }
            guard r.record() else {
                Log.audio.error("AVAudioRecorder.record returned false")
                throw RecordingError.engineFailed("record() returned false — likely mic unauthorized or busy")
            }
            self.recorder = r
            self.fileURL = url
            self.isRecording = true
            self.startTime = Date()
            startPolling()
            Log.audio.info("▶︎ AVAudioRecorder started at \(url.path)")
        } catch let error as RecordingError {
            throw error
        } catch {
            Log.audio.error("AVAudioRecorder init failed: \(error.localizedDescription)")
            throw RecordingError.engineFailed(error.localizedDescription)
        }
    }

    /// Stop recording and return the captured WAV data. Throws if nothing was captured.
    @discardableResult
    func stop() throws -> Data {
        guard isRecording, let r = recorder, let url = fileURL else {
            throw RecordingError.empty
        }
        r.stop()
        pollTimer?.invalidate()
        pollTimer = nil
        isRecording = false
        elapsed = 0

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecordingError.fileMissing
        }
        let data = try Data(contentsOf: url)
        Log.audio.info("⏹ stopped, captured \(data.count) bytes")
        // Best-effort cleanup; not fatal if we can't delete.
        try? FileManager.default.removeItem(at: url)
        recorder = nil
        fileURL = nil

        guard data.count > 44 else { throw RecordingError.empty }  // 44 = WAV header bytes
        return data
    }

    func cancel() {
        recorder?.stop()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        fileURL = nil
        pollTimer?.invalidate()
        pollTimer = nil
        isRecording = false
        elapsed = 0
        levelRMS = 0
    }

    private func makeTempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rec-\(Int(Date().timeIntervalSince1970)).wav")
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        guard let r = recorder, let s = startTime else { return }
        r.updateMeters()
        // peakPower returns dB in the range -160 (silence) to 0 (max).
        let peakDb = r.peakPower(forChannel: 0)
        let level = max(0, min(1, (peakDb + 60) / 60))   // map -60..0 dB → 0..1
        self.levelRMS = level
        self.elapsed = Date().timeIntervalSince(s)
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            Log.audio.error("Encode error: \(error.localizedDescription)")
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Log.audio.info("recorder finished, success=\(flag)")
    }
}
