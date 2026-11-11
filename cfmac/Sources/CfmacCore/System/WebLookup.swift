import Foundation

/// Builds a web search that shows how to free up space or uninstall something.
///
/// cfmac never requests these pages itself. The link only opens in the default browser when
/// the user clicks Look Up, and the query holds nothing but the item's public name.
public enum WebLookup {
    static let searchEndpoint = "https://www.google.com/search"

    public static func searchURL(_ query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: searchEndpoint) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }

    /// "How do I get this space back?" for a cleanable or app-managed location.
    public static func freeSpaceQuery(for name: String) -> String {
        "how to safely delete \(name) on Mac to free up disk space"
    }

    /// "How do I remove this app completely?"
    public static func uninstallQuery(for appName: String) -> String {
        "how to completely uninstall \(appName) on Mac and free up space"
    }
}
