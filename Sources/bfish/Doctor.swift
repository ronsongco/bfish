import BFishCore
import Foundation

enum Doctor {
    static func run() async -> DoctorReport {
        var checks: [DoctorCheck] = []
        checks.append(platformCheck())
        checks.append(architectureCheck())
        checks.append(commandCheck(name: "Xcode", executable: "/usr/bin/xcodebuild", arguments: ["-version"]))
        checks.append(commandCheck(name: "Developer directory", executable: "/usr/bin/xcode-select", arguments: ["-p"]))
        checks.append(permissionMetadataCheck())
        checks.append(signingCheck())
        checks.append(await ollamaCheck())
        return DoctorReport(checks: checks)
    }

    static func print(_ report: DoctorReport) {
        Swift.print("bfish doctor")
        for check in report.checks {
            let marker = switch check.status {
            case .pass: "PASS"
            case .warning: "WARN"
            case .fail: "FAIL"
            }
            Swift.print("[\(marker)] \(check.name): \(check.detail)")
        }
    }

    private static func platformCheck() -> DoctorCheck {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let detail = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return DoctorCheck(
            name: "Platform",
            status: version.majorVersion >= 26 ? .pass : .fail,
            detail: detail
        )
    }

    private static func architectureCheck() -> DoctorCheck {
        #if arch(arm64)
        DoctorCheck(name: "Architecture", status: .pass, detail: "arm64 / Apple Silicon")
        #else
        DoctorCheck(name: "Architecture", status: .fail, detail: "bfish requires Apple Silicon")
        #endif
    }

    private static func permissionMetadataCheck() -> DoctorCheck {
        let bundle = Bundle.main
        let audio = bundle.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") as? String
        let microphone = bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String

        if audio != nil, microphone != nil {
            return DoctorCheck(name: "Permission metadata", status: .pass, detail: "system-audio and microphone descriptions embedded")
        }

        return DoctorCheck(
            name: "Permission metadata",
            status: .warning,
            detail: "not embedded in this executable; use Scripts/package-local.sh before live capture"
        )
    }

    private static func signingCheck() -> DoctorCheck {
        guard let executable = Bundle.main.executablePath else {
            return DoctorCheck(name: "Code signing", status: .warning, detail: "unable to locate executable")
        }

        let result = runCommand("/usr/bin/codesign", ["-dv", "--verbose=2", executable])
        guard result.exitCode == 0 else {
            return DoctorCheck(name: "Code signing", status: .warning, detail: "unsigned development executable")
        }

        let identityLine = result.output
            .split(separator: "\n")
            .first { $0.hasPrefix("Authority=") || $0.hasPrefix("Signature=") }
        return DoctorCheck(name: "Code signing", status: .pass, detail: identityLine.map(String.init) ?? "signature present")
    }

    private static func commandCheck(name: String, executable: String, arguments: [String]) -> DoctorCheck {
        let result = runCommand(executable, arguments)
        return DoctorCheck(
            name: name,
            status: result.exitCode == 0 ? .pass : .fail,
            detail: result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func ollamaCheck() async -> DoctorCheck {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            return DoctorCheck(name: "Ollama", status: .fail, detail: "invalid default endpoint")
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return DoctorCheck(name: "Ollama", status: .fail, detail: "service returned an unexpected response")
            }

            let tags = try JSONDecoder().decode(OllamaTags.self, from: data)
            return DoctorCheck(name: "Ollama", status: .pass, detail: "reachable with \(tags.models.count) installed model(s)")
        } catch {
            return DoctorCheck(name: "Ollama", status: .fail, detail: "not reachable at 127.0.0.1:11434")
        }
    }

    private static func runCommand(_ executable: String, _ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (1, error.localizedDescription)
        }
    }
}

private struct OllamaTags: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String
}
