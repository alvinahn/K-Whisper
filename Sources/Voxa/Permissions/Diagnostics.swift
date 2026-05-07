import Foundation
import AppKit
import AVFoundation
import Combine

@MainActor
final class Diagnostics: ObservableObject {
    static let shared = Diagnostics()

    @Published var lastMessage: String = ""
    @Published var lastSuccess: Bool = false

    @Published var micTestActive: Bool = false
    @Published var micTestLevel: Float = 0
    @Published var micTestPeak: Float = 0
    @Published var micTestSeconds: TimeInterval = 0

    let recorder = AudioRecorder()
    private var levelSub: AnyCancellable?
    private var elapsedSub: AnyCancellable?

    /// Toggle a manual mic test. Click once to start, again to stop.
    func toggleMicTest() {
        if micTestActive {
            stopMicTest()
        } else {
            startMicTest()
        }
    }

    private func startMicTest() {
        micTestPeak = 0
        micTestLevel = 0
        micTestSeconds = 0
        do {
            try recorder.start()
            micTestActive = true
            lastMessage = "Recording… speak now. Click Stop when done."
            lastSuccess = false

            levelSub = recorder.$levelRMS.sink { [weak self] v in
                guard let self else { return }
                self.micTestLevel = v
                if v > self.micTestPeak { self.micTestPeak = v }
            }
            elapsedSub = recorder.$elapsed.sink { [weak self] e in
                self?.micTestSeconds = e
            }
        } catch {
            lastMessage = "❌ Mic failed to start: \(error.localizedDescription)"
            lastSuccess = false
        }
    }

    private func stopMicTest() {
        levelSub?.cancel()
        elapsedSub?.cancel()
        levelSub = nil
        elapsedSub = nil
        do {
            let wav = try recorder.stop()
            micTestActive = false
            let qual = micTestPeak > 0.05 ? "✅ Strong signal" :
                       micTestPeak > 0.01 ? "⚠️ Faint signal — try speaking louder" :
                                            "❌ No signal — check your input device"
            lastMessage = "\(qual). Captured \(wav.count) bytes in \(String(format: "%.1f", micTestSeconds))s. Peak \(String(format: "%.2f", micTestPeak))."
            lastSuccess = micTestPeak > 0.01
        } catch {
            micTestActive = false
            lastMessage = "❌ \(error.localizedDescription)"
            lastSuccess = false
        }
    }

    /// 3-second countdown then pastes "voxa-paste-test ✓" wherever the cursor is.
    func testPaste() {
        lastMessage = "Switch focus to a text field — pasting in 3…"
        lastSuccess = false
        let countdown: [String] = ["pasting in 3…", "pasting in 2…", "pasting in 1…"]
        for (i, msg) in countdown.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) { [weak self] in
                self?.lastMessage = msg
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            TextInjector.deliver("voxa-paste-test ✓")
            self.lastMessage = "✅ Sent paste — did 'voxa-paste-test ✓' appear in your text field?"
            self.lastSuccess = true
        }
    }

    /// Probes a tiny call to OpenAI to verify the API key works.
    func testOpenAIKey() {
        lastMessage = "Testing OpenAI key…"
        lastSuccess = false
        guard let key = SecretsStore.shared.get(.openai) else {
            lastMessage = "❌ No OpenAI key configured."
            return
        }
        Task {
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                await MainActor.run {
                    if (200..<300).contains(code) {
                        self.lastMessage = "✅ OpenAI key works (HTTP \(code))"
                        self.lastSuccess = true
                    } else {
                        self.lastMessage = "❌ OpenAI returned HTTP \(code) — key is bad."
                        self.lastSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = "❌ Network error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Probes Groq to verify the Groq API key works.
    func testGroqKey() {
        lastMessage = "Testing Groq key…"
        lastSuccess = false
        guard let key = SecretsStore.shared.get(.groq) else {
            lastMessage = "❌ No Groq key configured."
            return
        }
        Task {
            var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                await MainActor.run {
                    if (200..<300).contains(code) {
                        self.lastMessage = "✅ Groq key works (HTTP \(code))"
                        self.lastSuccess = true
                    } else {
                        self.lastMessage = "❌ Groq returned HTTP \(code) — key is bad."
                        self.lastSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = "❌ Network error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Probes Gemini to verify the Google API key works.
    func testGoogleKey() {
        lastMessage = "Testing Google key…"
        lastSuccess = false
        guard let key = SecretsStore.shared.get(.google) else {
            lastMessage = "❌ No Google key configured."
            return
        }
        Task {
            var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)")!)
            req.httpMethod = "GET"
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                await MainActor.run {
                    if (200..<300).contains(code) {
                        self.lastMessage = "✅ Google key works (HTTP \(code))"
                        self.lastSuccess = true
                    } else {
                        self.lastMessage = "❌ Google returned HTTP \(code) — key is bad."
                        self.lastSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = "❌ Network error: \(error.localizedDescription)"
                }
            }
        }
    }

    func openConsole() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Console"]
        try? task.run()
        lastMessage = "Console.app opened. Filter by subsystem: im.navio.voxa"
    }
}
