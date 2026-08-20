import Foundation

/// Reusable domain and pipeline components for bfish.
public enum BFishCore {
    public static let version: String = {
        guard let url = Bundle.module.url(forResource: "VERSION", withExtension: nil),
              let value = try? String(contentsOf: url, encoding: .utf8)
        else { return "unknown" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()
}
