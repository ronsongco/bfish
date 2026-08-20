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
            Doctor.print(report)
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
      doctor     Inspect local platform, developer tools, permissions metadata, and Ollama
      version    Print the bfish version
      help       Show this help

    PLANNED
      devices
      translate <audio-file>
      listen [--device <name> | --system | --app <bundle-id>]
      benchmark translation
    """
}
