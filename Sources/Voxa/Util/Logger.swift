import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "im.navio.voxa", category: "app")
    static let audio = Logger(subsystem: "im.navio.voxa", category: "audio")
    static let hotkey = Logger(subsystem: "im.navio.voxa", category: "hotkey")
    static let stt = Logger(subsystem: "im.navio.voxa", category: "stt")
    static let llm = Logger(subsystem: "im.navio.voxa", category: "llm")
    static let inject = Logger(subsystem: "im.navio.voxa", category: "inject")
    static let ui = Logger(subsystem: "im.navio.voxa", category: "ui")
}
