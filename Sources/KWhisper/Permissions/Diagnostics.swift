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
    @Published var pasteTestSucceeded: Bool = false

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
            lastMessage = "녹음 중… 지금 말해보세요. 끝나면 중지를 누르세요."
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
            lastMessage = "❌ 마이크 시작 실패: \(error.localizedDescription)"
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
            let qual = micTestPeak > 0.05 ? "✅ 신호 양호" :
                       micTestPeak > 0.01 ? "⚠️ 신호 약함 - 조금 더 크게 말해보세요" :
                                            "❌ 신호 없음 - 입력 장치를 확인하세요"
            lastMessage = "\(qual). \(String(format: "%.1f", micTestSeconds))초 동안 \(wav.count)바이트를 녹음했습니다. 피크 \(String(format: "%.2f", micTestPeak))."
            lastSuccess = micTestPeak > 0.01
        } catch {
            micTestActive = false
            lastMessage = "❌ \(error.localizedDescription)"
            lastSuccess = false
        }
    }

    /// 3-second countdown then pastes "voxa-paste-test ✓" wherever the cursor is.
    func testPaste() {
        lastMessage = "텍스트 입력 칸에 포커스를 옮기세요 - 3초 뒤 붙여넣습니다…"
        lastSuccess = false
        pasteTestSucceeded = false
        let countdown: [String] = ["3초 뒤 붙여넣기…", "2초 뒤 붙여넣기…", "1초 뒤 붙여넣기…"]
        for (i, msg) in countdown.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) { [weak self] in
                self?.lastMessage = msg
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            do {
                try TextInjector.deliver("kwhisper-paste-test ✓")
                self.lastMessage = "✅ 붙여넣기 전송 완료 - 입력 칸에 'kwhisper-paste-test ✓'가 나타났나요?"
                self.lastSuccess = true
                self.pasteTestSucceeded = true
            } catch {
                self.lastMessage = "❌ \(error.localizedDescription) - 위 접근성 섹션에서 '다시 허용'을 누르세요."
                self.lastSuccess = false
                self.pasteTestSucceeded = false
            }
        }
    }

    /// Probes a tiny call to OpenAI to verify the API key works.
    func testOpenAIKey() {
        lastMessage = "OpenAI 키 확인 중…"
        lastSuccess = false
        guard let key = SecretsStore.shared.get(.openai) else {
            lastMessage = "❌ OpenAI 키가 설정되어 있지 않습니다."
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
                        self.lastMessage = "✅ OpenAI 키 정상 (HTTP \(code))"
                        self.lastSuccess = true
                    } else {
                        self.lastMessage = "❌ OpenAI가 HTTP \(code)를 반환했습니다 - 키를 확인하세요."
                        self.lastSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = "❌ 네트워크 오류: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Probes Groq to verify the Groq API key works.
    func testGroqKey() {
        lastMessage = "Groq 키 확인 중…"
        lastSuccess = false
        guard let key = SecretsStore.shared.get(.groq) else {
            lastMessage = "❌ Groq 키가 설정되어 있지 않습니다."
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
                        self.lastMessage = "✅ Groq 키 정상 (HTTP \(code))"
                        self.lastSuccess = true
                    } else {
                        self.lastMessage = "❌ Groq가 HTTP \(code)를 반환했습니다 - 키를 확인하세요."
                        self.lastSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = "❌ 네트워크 오류: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Probes Gemini to verify the Google API key works.
    func testGoogleKey() {
        lastMessage = "Google 키 확인 중…"
        lastSuccess = false
        guard let key = SecretsStore.shared.get(.google) else {
            lastMessage = "❌ Google 키가 설정되어 있지 않습니다."
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
                        self.lastMessage = "✅ Google 키 정상 (HTTP \(code))"
                        self.lastSuccess = true
                    } else {
                        self.lastMessage = "❌ Google이 HTTP \(code)를 반환했습니다 - 키를 확인하세요."
                        self.lastSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = "❌ 네트워크 오류: \(error.localizedDescription)"
                }
            }
        }
    }

    func openConsole() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Console"]
        try? task.run()
        lastMessage = "Console.app을 열었습니다. subsystem: app.kwhisper 로 필터링하세요."
    }
}
