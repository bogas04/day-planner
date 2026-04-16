import AppKit
import Foundation
import OSLog

enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.divjot.focuseddayplanner"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let audio = Logger(subsystem: subsystem, category: "audio")
}

enum AppLogAccess {
    static func openConsoleApp() {
        let consoleURL = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.openApplication(at: consoleURL, configuration: NSWorkspace.OpenConfiguration())
    }

    static func exportRecentLogs(last interval: String = "1h") throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--style", "compact",
            "--last", interval,
            "--predicate", "subsystem == \"\(AppLogger.subsystem)\""
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw AppLogAccessError.exportFailed(errorOutput.isEmpty ? "The log command failed." : errorOutput)
        }

        let content = output.isEmpty
            ? "No unified log entries were found for subsystem \(AppLogger.subsystem) in the last \(interval).\n"
            : output

        let fileName = "focused-day-planner-logs-\(timestampString()).log"
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try content.write(to: destinationURL, atomically: true, encoding: .utf8)
        return destinationURL
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

enum AppLogAccessError: LocalizedError {
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case let .exportFailed(message):
            return message
        }
    }
}
