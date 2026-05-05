import AppKit
import Foundation

@MainActor
final class MacToolsWorkspaceManager: ObservableObject {
    private let workspaceRootDefaultsKey = "macToolsWorkspaceRootPath"

    @Published private(set) var workspaceRootPath: String

    init() {
        workspaceRootPath = UserDefaults.standard.string(forKey: workspaceRootDefaultsKey) ?? ""
    }

    var hasWorkspaceFolderConfigured: Bool {
        !workspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func promptUserToSelectWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Clicky Workspace Folder"
        panel.prompt = "Select Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        setWorkspaceRootURL(url)
    }

    func clearWorkspaceFolder() {
        setWorkspaceRootPath("")
    }

    func resolveUserPath(_ userProvidedPath: String) throws -> URL {
        let trimmedUserPath = userProvidedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserPath.isEmpty else {
            throw NSError(domain: "MacToolsWorkspaceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Path is required.",
            ])
        }

        let rootURL = try workspaceRootURL()

        let candidateURL: URL
        if trimmedUserPath.hasPrefix("/") {
            candidateURL = URL(fileURLWithPath: trimmedUserPath)
        } else {
            candidateURL = rootURL.appendingPathComponent(trimmedUserPath)
        }

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL

        let rootPath = resolvedRoot.path
        let candidatePath = resolvedCandidate.path

        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            throw NSError(domain: "MacToolsWorkspaceManager", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Blocked: path is outside the configured workspace folder.",
            ])
        }

        return resolvedCandidate
    }

    private func workspaceRootURL() throws -> URL {
        let trimmed = workspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "MacToolsWorkspaceManager", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "No workspace folder configured.",
            ])
        }
        return URL(fileURLWithPath: trimmed)
    }

    private func setWorkspaceRootURL(_ url: URL) {
        setWorkspaceRootPath(url.path)
    }

    private func setWorkspaceRootPath(_ path: String) {
        workspaceRootPath = path
        UserDefaults.standard.set(path, forKey: workspaceRootDefaultsKey)
    }
}

