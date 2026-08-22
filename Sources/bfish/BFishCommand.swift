import ArgumentParser
import BFishCore
import BFishWhisperKit
import Foundation

private struct SignalInterruption: Error {}

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

    @Flag(name: .long, help: "Compatibility flag; file recognition now always streams with bounded audio loading")
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
            statusHandler: { status in
                let event = DiagnosticEvent(
                    event: .modelStatus,
                    details: DiagnosticDetails(
                        modelStatus: status.diagnosticModelStatus,
                        progressPercentage: status.progressPercentage
                    )
                )
                if let line = try? event.jsonLine() {
                    FileHandle.standardError.write(line)
                }
            }
        ))
        let pipeline = TranslationPipeline(
            recognizer: recognizer,
            translator: PassThroughTranslator(),
            profile: .offline,
            sessionLocale: sessionLocale
        )
        let formatter = TerminalSourceTranscriptFormatter()
        let signalMonitor = SignalMonitor()
        defer { signalMonitor.stop() }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await event in await pipeline.events(
                        for: .file(fileURL),
                        language: whisperLanguage
                    ) {
                        switch event {
                        case let .transcript(turn):
                            FileHandle.standardOutput.write(Data((formatter.format(turn) + "\n\n").utf8))
                        case let .diagnostic(diagnostic):
                            FileHandle.standardError.write(try diagnostic.jsonLine())
                        }
                    }
                }
                group.addTask {
                    for await _ in signalMonitor.events {
                        throw SignalInterruption()
                    }
                }
                _ = try await group.next()
                group.cancelAll()
                try await group.waitForAll()
            }
        } catch is SignalInterruption {
            return
        }
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
