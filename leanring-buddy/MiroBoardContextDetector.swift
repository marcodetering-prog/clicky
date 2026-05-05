import Foundation

enum MiroBoardContextDetector {
    static func extractMiroBoardID(from urlString: String) -> String? {
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURLString.isEmpty else { return nil }

        guard let url = URL(string: trimmedURLString) else { return nil }
        let host = (url.host ?? "").lowercased()
        guard host.contains("miro.com") || host.contains("realtimeboard.com") else { return nil }

        // Typical patterns:
        // - https://miro.com/app/board/uXjV...=/
        // - https://miro.com/app/board/<boardId>/
        let path = url.path
        guard let boardRange = path.range(of: "/app/board/") else { return nil }
        let afterBoard = path[boardRange.upperBound...]

        let boardId = afterBoard.split(separator: "/").first.map(String.init) ?? ""
        let trimmedBoardId = boardId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBoardId.isEmpty else { return nil }
        return trimmedBoardId
    }
}

