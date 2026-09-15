import AppKit
import CryptoKit
import Darwin
import Foundation

private enum UpdateFailure: LocalizedError {
    case invalidArguments
    case invalidTarget
    case invalidDownload
    case downloadFailed
    case checksumMismatch
    case invalidArchive
    case invalidApplication
    case signatureInvalid
    case replacementFailed
    case parentDidNotExit

    var errorDescription: String? {
        switch self {
        case .invalidArguments: "The updater received invalid instructions."
        case .invalidTarget: "QuickAdd must be installed as QuickAdd.app before it can update itself."
        case .invalidDownload: "The update download is not an approved QuickAdd GitHub release."
        case .downloadFailed: "The update could not be downloaded from GitHub."
        case .checksumMismatch: "The downloaded update failed its SHA-256 verification."
        case .invalidArchive: "The downloaded QuickAdd ZIP could not be extracted."
        case .invalidApplication: "The update does not contain a valid QuickAdd application."
        case .signatureInvalid: "The downloaded QuickAdd application has an invalid code signature."
        case .replacementFailed: "QuickAdd could not replace the installed application."
        case .parentDidNotExit: "QuickAdd did not quit in time, so the update was cancelled."
        }
    }
}

private struct Instructions {
    let target: URL
    let downloadURL: URL
    let sha256: String
    let version: String
    let parentPID: pid_t
    let shouldRelaunch: Bool

    init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 1
        while index + 1 < arguments.count {
            values[arguments[index]] = arguments[index + 1]
            index += 2
        }
        guard let targetPath = values["--target"],
              let urlText = values["--url"],
              let downloadURL = URL(string: urlText),
              let sha256 = values["--sha256"]?.lowercased(),
              sha256.count == 64,
              sha256.allSatisfy(\.isHexDigit),
              let version = values["--version"],
              let parentText = values["--parent-pid"],
              let parentPID = pid_t(parentText) else {
            throw UpdateFailure.invalidArguments
        }

        let target = URL(fileURLWithPath: targetPath).standardizedFileURL
        guard target.lastPathComponent == "QuickAdd.app",
              !target.pathComponents.contains(".."),
              downloadURL.scheme == "https",
              downloadURL.host == "github.com",
              downloadURL.path.hasPrefix("/TheCuriousProcrastinator/QuickAdd-for-Reminders/releases/download/"),
              downloadURL.lastPathComponent == "QuickAdd.zip" else {
            throw UpdateFailure.invalidDownload
        }

        self.target = target
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.version = version.hasPrefix("v") ? String(version.dropFirst()) : version
        self.parentPID = parentPID
        self.shouldRelaunch = values["--relaunch"] != "no"
    }
}

private enum QuickAddUpdater {
    private static let expectedBundleIdentifier = "local.alex.QuickAdd"

    static func install(_ instructions: Instructions) async throws {
        try validateTarget(instructions.target)
        try await waitForExit(of: instructions.parentPID)

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickAddUpdate-\(UUID().uuidString)", isDirectory: true)
        let archive = work.appendingPathComponent("QuickAdd.zip")
        let extracted = work.appendingPathComponent("Extracted", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }

        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try await download(instructions.downloadURL, to: archive)
        try verifyChecksum(of: archive, expected: instructions.sha256)
        try run("/usr/bin/ditto", arguments: ["-x", "-k", archive.path, extracted.path], failure: .invalidArchive)

        let candidate = extracted.appendingPathComponent("QuickAdd.app", isDirectory: true)
        try validateCandidate(candidate, expectedVersion: instructions.version)
        try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", candidate.path], failure: .signatureInvalid)
        try replace(instructions.target, with: candidate)

        if instructions.shouldRelaunch {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: instructions.target, configuration: configuration)
        }
    }

    private static func validateTarget(_ target: URL) throws {
        let isSymbolicLink = try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        guard !target.hasDirectoryPath || target.lastPathComponent == "QuickAdd.app" else {
            throw UpdateFailure.invalidTarget
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !isSymbolicLink else {
            throw UpdateFailure.invalidTarget
        }
        guard Bundle(url: target)?.bundleIdentifier == expectedBundleIdentifier else {
            throw UpdateFailure.invalidTarget
        }
    }

    private static func waitForExit(of pid: pid_t) async throws {
        guard pid > 1 else { return }
        for _ in 0..<300 {
            guard kill(pid, 0) == 0 else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw UpdateFailure.parentDidNotExit
    }

    private static func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("QuickAdd-for-Reminders-Updater", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              response.url?.scheme == "https" else {
            throw UpdateFailure.downloadFailed
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private static func verifyChecksum(of file: URL, expected: String) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateFailure.checksumMismatch }
    }

    private static func validateCandidate(_ candidate: URL, expectedVersion: String) throws {
        let isSymbolicLink = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !isSymbolicLink,
              let bundle = Bundle(url: candidate),
              bundle.bundleIdentifier == expectedBundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion,
              FileManager.default.isExecutableFile(atPath: candidate.appendingPathComponent("Contents/MacOS/QuickAdd").path) else {
            throw UpdateFailure.invalidApplication
        }
    }

    private static func replace(_ target: URL, with candidate: URL) throws {
        let backup = target.deletingLastPathComponent()
            .appendingPathComponent(".QuickAdd-backup-\(UUID().uuidString).app")
        do {
            try FileManager.default.moveItem(at: target, to: backup)
            do {
                try FileManager.default.moveItem(at: candidate, to: target)
                try? FileManager.default.removeItem(at: backup)
            } catch {
                try? FileManager.default.moveItem(at: backup, to: target)
                throw UpdateFailure.replacementFailed
            }
        } catch let error as UpdateFailure {
            throw error
        } catch {
            throw UpdateFailure.replacementFailed
        }
    }

    private static func run(_ executable: String, arguments: [String], failure: UpdateFailure) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure }
    }

    static func showFailure(_ error: Error, relaunch target: URL?) async {
        if let target, FileManager.default.fileExists(atPath: target.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: target, configuration: configuration)
        }
        await MainActor.run {
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "QuickAdd Couldn’t Update"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

@main
private struct QuickAddUpdaterApp {
    static func main() async {
        do {
            let instructions = try Instructions(arguments: CommandLine.arguments)
            do {
                try await QuickAddUpdater.install(instructions)
            } catch {
                await QuickAddUpdater.showFailure(error, relaunch: instructions.shouldRelaunch ? instructions.target : nil)
            }
        } catch {
            await QuickAddUpdater.showFailure(error, relaunch: nil)
        }
    }
}
