import ArgumentParser
import BFishCore
import Foundation

@main
struct BFishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bfish",
        abstract: "Local speech transcription and English translation",
        version: BFishCore.version,
        subcommands: [DoctorCommand.self, VersionCommand.self]
    )
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
