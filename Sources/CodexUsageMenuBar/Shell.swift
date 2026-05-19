import Foundation

struct ShellResult {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
    let timedOut: Bool

    var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

enum ShellError: Error, CustomStringConvertible {
    case launchFailed(String)

    var description: String {
        switch self {
        case .launchFailed(let message):
            return message
        }
    }
}

enum Shell {
    static func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 5
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(error.localizedDescription)
        }

        let timeoutTime = DispatchTime.now() + timeout
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        var timedOut = false
        if finished.wait(timeout: timeoutTime) == .timedOut {
            timedOut = true
            process.terminate()
            process.waitUntilExit()
        }

        return ShellResult(
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile(),
            exitCode: process.terminationStatus,
            timedOut: timedOut
        )
    }
}
