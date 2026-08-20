import ArgumentParser
import BFishCore
import BFishWhisperKit
import Foundation

@main
struct BFishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bfish",
        abstract: "Local speech transcription and English translation",
        version: BFishCore.version,
        subcommands: [TranscribeCommand.self, DoctorCommand.self, VersionCommand.self]
    )
}

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio file locally with WhisperKit"
    )

    @Argument(help: "Audio file to transcribe")
    var audioFile: String

    @Option(name: .long, help: "WhisperKit model variant or repository identifier")
    var model = "tiny"

    @Option(name: .long, help: "Existing local WhisperKit model directory")
    var modelPath: String?

    @Option(name: .long, help: "Whisper language token, or auto")
    var language = "auto"

    @Option(name: .long, help: "Display locale such as pt-BR")
    var locale: String?

    @Flag(name: .long, help: "Load long audio files with bounded memory")
    var incremental = false

    func run() async throws {
        guard let whisperLanguage = WhisperLanguage(rawValue: language) else {
            throw ValidationError("Unsupported Whisper language token: \(language)")
        }
        let sessionLocale: SessionLocale?
        if let locale {
            guard let parsed = SessionLocale(rawValue: locale) else {
                throw ValidationError("Invalid locale: \(locale)")
            }
            sessionLocale = parsed
        } else {
            sessionLocale = nil
        }

        let fileURL = URL(fileURLWithPath: audioFile).standardizedFileURL
        let recognizer = WhisperKitRecognizer(configuration: .init(
            model: model,
            modelFolder: modelPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
            incrementalLoading: incremental,
            statusHandler: { message in
                FileHandle.standardError.write(Data("\(message)\n".utf8))
            }
        ))
        let output = try await recognizer.transcribe(.file(fileURL), language: whisperLanguage)
        let formatter = TerminalSourceTranscriptFormatter()

        for segment in output.segments {
            write(formatter.format(segment, sessionLocale: sessionLocale) + "\n\n", to: .standardOutput)
        }
        for diagnostic in output.diagnostics {
            FileHandle.standardError.write(try diagnostic.jsonLine())
        }
        if !output.timings.isEmpty {
            let timing = DiagnosticEvent(
                event: .recognitionCompleted,
                timings: output.timings,
                details: output.metrics.map {
                    DiagnosticDetails(
                        audioDurationSeconds: $0.audioDurationSeconds,
                        realTimeFactor: $0.realTimeFactor
                    )
                }
            )
            FileHandle.standardError.write(try timing.jsonLine())
        }
    }

    private func write(_ string: String, to handle: FileHandle) {
        handle.write(Data(string.utf8))
    }
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the bfish version"
    )

    func run() {
        print("bfish \(BFishCore.version)")
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Inspect the platform, resources, permissions, signing, and Ollama"
    )

    @Flag(name: .long, help: "Emit the schema-versioned report as JSON")
    var json = false

    func run() async throws {
        let report = await Doctor.run()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            Doctor.print(report)
        }
        if report.hasFailures { throw ExitCode.failure }
    }
}
