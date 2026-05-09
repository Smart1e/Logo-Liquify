import Foundation
import SwiftUI

@MainActor
final class LogoLiquifyModel: ObservableObject {
    @Published var iconURL: URL?
    @Published var appURL: URL?
    @Published var status: Status = .idle
    @Published var logLines: [String] = []

    private let replacer = IconReplacer()

    enum Status: Equatable {
        case idle
        case working(String)
        case readyToSave(URL)
        case saved(URL)
        case error(String)
    }

    var canStart: Bool {
        if case .working = status { return false }
        return iconURL != nil && appURL != nil
    }

    func resetAll() {
        status = .idle
        logLines.removeAll()
        iconURL = nil
        appURL = nil
    }

    func start() async {
        guard canStart, let iconURL, let appURL else { return }
        logLines.removeAll()
        status = .working("Starting…")

        let logger: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in
                guard let self else { return }
                self.logLines.append(line)
                if case .working = self.status {
                    self.status = .working(line)
                }
            }
        }

        do {
            let staged = try await replacer.replace(
                appURL: appURL,
                iconURL: iconURL,
                log: logger
            )
            status = .readyToSave(staged)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logLines.append("ERROR: \(msg)")
            status = .error(msg)
        }
    }

    func saveStaged(to destination: URL) async {
        guard case .readyToSave(let staged) = status else { return }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: staged, to: destination)
            logLines.append("Saved to \(destination.path)")
            status = .saved(destination)
        } catch {
            let msg = "Save failed: \(error.localizedDescription)"
            logLines.append("ERROR: \(msg)")
            status = .error(msg)
        }
    }
}
