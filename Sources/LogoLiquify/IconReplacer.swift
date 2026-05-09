import Foundation

enum IconReplacerError: LocalizedError {
    case invalidApp(URL)
    case invalidIcon(URL)
    case actoolMissing
    case actoolFailed(stderr: String)
    case noAssetsCar
    case codesignMissing
    case codesignFailed(stderr: String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidApp(let url):
            return "‘\(url.lastPathComponent)’ is not a valid .app bundle (Contents/Info.plist missing)."
        case .invalidIcon(let url):
            return "‘\(url.lastPathComponent)’ is not a valid Icon Composer .icon (icon.json missing)."
        case .actoolMissing:
            return "actool not found. Install Xcode or the Xcode Command Line Tools."
        case .actoolFailed(let stderr):
            return "actool failed:\n\(stderr.isEmpty ? "(no stderr)" : stderr)"
        case .noAssetsCar:
            return "actool exited 0 but did not produce Assets.car."
        case .codesignMissing:
            return "codesign not found."
        case .codesignFailed(let stderr):
            return "codesign failed:\n\(stderr.isEmpty ? "(no stderr)" : stderr)"
        case .copyFailed(let s):
            return "Could not copy app bundle: \(s)"
        }
    }
}

struct IconReplacer: Sendable {
    private static let workRoot = URL(fileURLWithPath: "/var/tmp/LogoLiquify")
    private static let iconName = "AppIcon"
    private static let minDeploymentTarget = "26.0"

    func replace(
        appURL: URL,
        iconURL: URL,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.performReplace(appURL: appURL, iconURL: iconURL, log: log)
        }.value
    }

    private static func performReplace(
        appURL: URL,
        iconURL: URL,
        log: @Sendable (String) -> Void
    ) throws -> URL {
        let fm = FileManager.default

        // Validate inputs
        let appInfoPlist = appURL.appending(path: "Contents/Info.plist")
        guard fm.fileExists(atPath: appInfoPlist.path) else {
            throw IconReplacerError.invalidApp(appURL)
        }
        let iconJSON = iconURL.appending(path: "icon.json")
        guard fm.fileExists(atPath: iconJSON.path) else {
            throw IconReplacerError.invalidIcon(iconURL)
        }

        // Working dir under /var/tmp
        try fm.createDirectory(at: workRoot, withIntermediateDirectories: true)
        let session = workRoot.appending(path: "session-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: session, withIntermediateDirectories: true)
        log("Working dir: \(session.path)")

        // Copy app to working dir
        let workApp = session.appending(path: appURL.lastPathComponent)
        log("Copying \(appURL.lastPathComponent) to working dir…")
        do {
            try fm.copyItem(at: appURL, to: workApp)
        } catch {
            throw IconReplacerError.copyFailed(error.localizedDescription)
        }

        // Locate tools
        guard let actool = Self.locateExecutable(named: "actool") else {
            throw IconReplacerError.actoolMissing
        }
        guard let codesign = Self.locateExecutable(named: "codesign") else {
            throw IconReplacerError.codesignMissing
        }

        // Stage the .icon as AppIcon.icon so actool names the resulting asset
        // catalog entry "AppIcon" — this must match CFBundleIconName, otherwise
        // macOS can't resolve the icon and shows the placeholder grid.
        let stagedIcon = session.appending(path: "\(iconName).icon")
        if iconURL.lastPathComponent != "\(iconName).icon" {
            log("Staging \(iconURL.lastPathComponent) as \(iconName).icon…")
        }
        try fm.copyItem(at: iconURL, to: stagedIcon)

        // Compile icon
        let compiled = session.appending(path: "compiled")
        try fm.createDirectory(at: compiled, withIntermediateDirectories: true)
        let partialPlist = compiled.appending(path: "info-partial.plist")

        log("Compiling \(stagedIcon.lastPathComponent) with actool…")
        let actoolResult = try Self.runProcess(
            executable: actool,
            arguments: [
                stagedIcon.path,
                "--compile", compiled.path,
                "--platform", "macosx",
                "--minimum-deployment-target", minDeploymentTarget,
                "--app-icon", iconName,
                "--include-all-app-icons",
                "--output-partial-info-plist", partialPlist.path,
            ]
        )
        if actoolResult.exitCode != 0 {
            throw IconReplacerError.actoolFailed(stderr: actoolResult.stderrOrStdout)
        }

        let compiledCar = compiled.appending(path: "Assets.car")
        guard fm.fileExists(atPath: compiledCar.path) else {
            throw IconReplacerError.noAssetsCar
        }
        log("actool produced Assets.car (\(Self.byteSize(compiledCar)))")

        // Inject into Resources/
        let resources = workApp.appending(path: "Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        try Self.replaceFile(at: resources.appending(path: "Assets.car"), with: compiledCar)
        log("Wrote Resources/Assets.car")

        let compiledIcns = compiled.appending(path: "\(iconName).icns")
        if fm.fileExists(atPath: compiledIcns.path) {
            try Self.replaceFile(at: resources.appending(path: "\(iconName).icns"), with: compiledIcns)
            log("Wrote Resources/\(iconName).icns")
        }

        // Merge icon keys into Info.plist
        try Self.mergePartialPlist(from: partialPlist, into: appInfoPlistRelative(workApp: workApp))
        log("Updated Info.plist (CFBundleIconFile, CFBundleIconName)")

        // Strip stale signature, then ad-hoc re-sign
        log("Re-codesigning (ad-hoc)…")
        let signResult = try Self.runProcess(
            executable: codesign,
            arguments: ["--force", "--deep", "--sign", "-", workApp.path]
        )
        if signResult.exitCode != 0 {
            throw IconReplacerError.codesignFailed(stderr: signResult.stderrOrStdout)
        }

        // Verify (best-effort; warn on failure)
        let verifyResult = try Self.runProcess(
            executable: codesign,
            arguments: ["--verify", "--deep", "--strict", workApp.path]
        )
        if verifyResult.exitCode == 0 {
            log("codesign --verify passed")
        } else {
            log("WARNING: codesign --verify reported issues:")
            for line in verifyResult.stderrOrStdout.split(separator: "\n") {
                log("  \(line)")
            }
        }

        return workApp
    }

    // MARK: - Helpers

    private static func appInfoPlistRelative(workApp: URL) -> URL {
        workApp.appending(path: "Contents/Info.plist")
    }

    private static func locateExecutable(named name: String) -> URL? {
        let direct = URL(fileURLWithPath: "/usr/bin/\(name)")
        if FileManager.default.isExecutableFile(atPath: direct.path) {
            return direct
        }
        if let xcrun = try? runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["-f", name]
        ), xcrun.exitCode == 0 {
            let path = xcrun.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var stderrOrStdout: String { stderr.isEmpty ? stdout : stderr }
    }

    private static func runProcess(executable: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private static func replaceFile(at destination: URL, with source: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    private static func mergePartialPlist(from partial: URL, into main: URL) throws {
        var mainDict: [String: Any] = [:]
        if let mainData = try? Data(contentsOf: main),
           let parsed = try PropertyListSerialization.propertyList(
                from: mainData, options: [], format: nil) as? [String: Any] {
            mainDict = parsed
        }

        if let partialData = try? Data(contentsOf: partial),
           let parsedPartial = try PropertyListSerialization.propertyList(
                from: partialData, options: [], format: nil) as? [String: Any] {
            for (k, v) in parsedPartial {
                mainDict[k] = v
            }
        }

        // Always pin these so the OS picks up the new icon, even if actool's partial
        // plist didn't include them.
        mainDict["CFBundleIconFile"] = iconName
        mainDict["CFBundleIconName"] = iconName

        let outData = try PropertyListSerialization.data(
            fromPropertyList: mainDict, format: .xml, options: 0)
        try outData.write(to: main, options: .atomic)
    }

    private static func byteSize(_ url: URL) -> String {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? NSNumber
        else { return "unknown size" }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }
}
