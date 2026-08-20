import BFishCore
import Foundation

@main
enum BFishCommand {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"

        switch command {
        case "help", "--help", "-h":
            print(Self.help)
        case "version", "--version":
            print("bfish \(BFishCore.version)")
        case "doctor":
            let report = await Doctor.run()
            if arguments.dropFirst().contains("--json") {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    FileHandle.standardOutput.write(try encoder.encode(report))
                    FileHandle.standardOutput.write(Data("\n".utf8))
                } catch {
                    FileHandle.standardError.write(Data("Unable to encode doctor report: \(error)\n".utf8))
                }
            } else {
                Doctor.print(report)
            }
            if report.hasFailures {
                Foundation.exit(1)
            }
        default:
            FileHandle.standardError.write(Data("Unknown command: \(command)\n\n\(Self.help)\n".utf8))
            Foundation.exit(64)
        }
    }

    private static let help = """
    bfish — local speech transcription and English translation

    USAGE
      bfish <command>

    COMMANDS
      doctor [--json]
                 Inspect local platform, resources, permissions, signing, and Ollama
      version    Print the bfish version
      help       Show this help

    PLANNED
      devices
      translate <audio-file>
      listen [--device <name> | --system | --app <bundle-id>]
      benchmark translation
    """
}
