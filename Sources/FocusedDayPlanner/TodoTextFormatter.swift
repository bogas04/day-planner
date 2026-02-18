import Foundation

struct ParsedTodoLink {
    let url: URL
    let textBeforeURL: String
    let textAfterURL: String
    let linearIssueID: String?
    let linearDescription: String?

    var isLinear: Bool { linearIssueID != nil }
}

enum TodoTextFormatter {
    private static let urlRegex = try? NSRegularExpression(pattern: #"https?://\S+"#, options: [])

    static func parseFirstURL(from text: String) -> ParsedTodoLink? {
        guard let urlRegex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = urlRegex.firstMatch(in: text, options: [], range: range),
              let matchedRange = Range(match.range, in: text) else {
            return nil
        }

        let urlString = String(text[matchedRange])
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }

        let prefix = text[..<matchedRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = text[matchedRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)

        let linearInfo = parseLinear(from: url, fallbackSuffix: String(suffix))
        return ParsedTodoLink(
            url: url,
            textBeforeURL: String(prefix),
            textAfterURL: String(suffix),
            linearIssueID: linearInfo?.issueID,
            linearDescription: linearInfo?.description
        )
    }

    private static func parseLinear(from url: URL, fallbackSuffix: String) -> (issueID: String, description: String)? {
        guard url.host?.contains("linear.app") == true else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let issueIndex = components.firstIndex(of: "issue"), issueIndex + 1 < components.count else {
            return nil
        }

        let issueID = components[issueIndex + 1].uppercased()
        let slug: String
        if issueIndex + 2 < components.count {
            slug = components[issueIndex + 2].replacingOccurrences(of: "-", with: " ")
        } else {
            slug = ""
        }

        let description = fallbackSuffix.isEmpty ? slug : fallbackSuffix
        return (issueID, description)
    }
}
