import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "app.kwhisper", category: "app")
    static let audio = Logger(subsystem: "app.kwhisper", category: "audio")
    static let hotkey = Logger(subsystem: "app.kwhisper", category: "hotkey")
    static let stt = Logger(subsystem: "app.kwhisper", category: "stt")
    static let llm = Logger(subsystem: "app.kwhisper", category: "llm")
    static let inject = Logger(subsystem: "app.kwhisper", category: "inject")
    static let ui = Logger(subsystem: "app.kwhisper", category: "ui")
}
