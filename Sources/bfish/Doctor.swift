import BFishCore
import Foundation

enum Doctor {
    static func run() async -> DoctorReport {
        var checks: [DoctorCheck] = []
        checks.append(platformCheck())
        checks.append(architectureCheck())
        checks.append(memoryCheck())
        checks.append(diskCheck())
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
        let identity = identityLine.map(String.init) ?? "signature present"
        let lowercasedOutput = result.output.lowercased()
        if lowercasedOutput.contains("signature=adhoc") {
            return DoctorCheck(
                name: "Code signing",
                status: .warning,
                detail: "\(identity); ad-hoc identity may not preserve TCC grants across builds"
            )
        }
        return DoctorCheck(name: "Code signing", status: .pass, detail: identity)
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
        let configuredHost = ProcessInfo.processInfo.environment["OLLAMA_HOST"] ?? "http://127.0.0.1:11434"
        let host = configuredHost.contains("://") ? configuredHost : "http://\(configuredHost)"
        guard var components = URLComponents(string: host) else {
            return DoctorCheck(name: "Ollama", status: .fail, detail: "invalid OLLAMA_HOST: \(configuredHost)")
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/tags"
        guard let url = components.url else {
            return DoctorCheck(name: "Ollama", status: .fail, detail: "invalid OLLAMA_HOST: \(configuredHost)")
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return DoctorCheck(name: "Ollama", status: .fail, detail: "service returned an unexpected response")
            }

            let tags = try JSONDecoder().decode(OllamaTags.self, from: data)
            return DoctorCheck(
                name: "Ollama",
                status: tags.models.isEmpty ? .warning : .pass,
                detail: "reachable at \(url.host ?? configuredHost) with \(tags.models.count) installed model(s); translation suitability not yet verified"
            )
        } catch {
            return DoctorCheck(name: "Ollama", status: .fail, detail: "not reachable at \(configuredHost)")
        }
    }

    private static func memoryCheck() -> DoctorCheck {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gibibytes = Double(bytes) / 1_073_741_824
        return DoctorCheck(
            name: "Physical memory",
            status: gibibytes >= 16 ? .pass : .warning,
            detail: String(format: "%.1f GiB installed; simultaneous model capacity must be benchmarked", gibibytes)
        )
    }

    private static func diskCheck() -> DoctorCheck {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
                return DoctorCheck(name: "Available disk", status: .warning, detail: "capacity unavailable")
            }
            let gibibytes = Double(bytes) / 1_073_741_824
            return DoctorCheck(
                name: "Available disk",
                status: gibibytes >= 20 ? .pass : .warning,
                detail: String(format: "%.1f GiB available for models and benchmark artifacts", gibibytes)
            )
        } catch {
            return DoctorCheck(name: "Available disk", status: .warning, detail: error.localizedDescription)
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
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
