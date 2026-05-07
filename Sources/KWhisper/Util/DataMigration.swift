import Foundation

/// One-shot data folder migration. The app was previously called "Voxa"; rename the
/// Application Support directory so existing keys, history, glossary, and modes carry
/// over after the rename.
enum DataMigration {
    static func runIfNeeded() {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let oldDir = support.appendingPathComponent("Voxa", isDirectory: true)
        let newDir = support.appendingPathComponent("KWhisper", isDirectory: true)

        guard fm.fileExists(atPath: oldDir.path) else { return }
        if fm.fileExists(atPath: newDir.path) {
            // Already migrated — nothing to do.
            return
        }

        do {
            try fm.moveItem(at: oldDir, to: newDir)
            Log.app.info("Migrated data folder: Voxa → KWhisper")
        } catch {
            Log.app.error("Data folder migration failed: \(error.localizedDescription)")
        }
    }
}
