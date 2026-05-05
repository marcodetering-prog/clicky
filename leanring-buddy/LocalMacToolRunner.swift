import AppKit
import Foundation

@MainActor
final class LocalMacToolRunner {
    struct Tool {
        let name: String
        let description: String
        let parameters: [String: Any]
    }

    enum PermissionError: Error {
        case deniedByUser
        case toolDisabled(String)
    }

    private let approvalPresenter = MacToolApprovalPresenter()
    private let workspaceManager: MacToolsWorkspaceManager

    private let fileWriteEnabledDefaultsKey = "macToolsEnableFileWrite"
    private let shellEnabledDefaultsKey = "macToolsEnableShell"
    private let appleScriptEnabledDefaultsKey = "macToolsEnableAppleScript"

    init(workspaceManager: MacToolsWorkspaceManager) {
        self.workspaceManager = workspaceManager
    }

    var isFileWriteEnabled: Bool {
        UserDefaults.standard.object(forKey: fileWriteEnabledDefaultsKey) as? Bool ?? false
    }

    func setFileWriteEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: fileWriteEnabledDefaultsKey)
    }

    var isShellEnabled: Bool {
        UserDefaults.standard.object(forKey: shellEnabledDefaultsKey) as? Bool ?? false
    }

    func setShellEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: shellEnabledDefaultsKey)
    }

    var isAppleScriptEnabled: Bool {
        UserDefaults.standard.object(forKey: appleScriptEnabledDefaultsKey) as? Bool ?? false
    }

    func setAppleScriptEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: appleScriptEnabledDefaultsKey)
    }

    func toolDefinitions() -> [OpenAICompatibleChatAPI.ToolDefinition] {
        return [
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "fs_list_dir",
                description: "List files/folders under the configured workspace folder. Provide a relative path like '.' or 'src'.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Relative path under the workspace folder (default: '.')"],
                    ],
                    "required": [],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "fs_read_file",
                description: "Read a UTF-8 text file under the configured workspace folder.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Relative path under the workspace folder."],
                        "max_bytes": ["type": "integer", "description": "Max bytes to return (default: 20000)."],
                    ],
                    "required": ["path"],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "fs_write_file",
                description: "Write a UTF-8 text file under the configured workspace folder. Requires user approval.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Relative path under the workspace folder."],
                        "content": ["type": "string", "description": "File content to write."],
                        "overwrite": ["type": "boolean", "description": "Overwrite if the file exists (default: false)."],
                    ],
                    "required": ["path", "content"],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "shell_run",
                description: "Run a shell command with working directory set to the workspace folder. Requires user approval.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "command": ["type": "string", "description": "Command to run (zsh -lc)."],
                        "timeout_seconds": ["type": "integer", "description": "Timeout seconds (default: 30)."],
                    ],
                    "required": ["command"],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "mac_open",
                description: "Open a URL or file path with the default macOS handler (NSWorkspace.open). Requires user approval.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "target": ["type": "string", "description": "URL (https://...) or file path."],
                    ],
                    "required": ["target"],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "mac_frontmost_app",
                description: "Get the frontmost app name and bundle identifier.",
                parameters: [
                    "type": "object",
                    "properties": [:],
                    "required": [],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "mac_launch_app",
                description: "Launch or activate an app by name (e.g. 'Xcode', 'Terminal'). Requires user approval.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "app_name": ["type": "string", "description": "Application name (as shown in /Applications)."],
                    ],
                    "required": ["app_name"],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "mac_reveal_in_finder",
                description: "Reveal a file/folder in Finder. Path can be absolute or workspace-relative. Requires user approval.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Absolute path or workspace-relative path."],
                    ],
                    "required": ["path"],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "clipboard_get",
                description: "Read the current clipboard as plain text (if available).",
                parameters: [
                    "type": "object",
                    "properties": [:],
                    "required": [],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "clipboard_set",
                description: "Set the clipboard to plain text. Requires user approval.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "Text to put on the clipboard."],
                    ],
                    "required": ["text"],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "shortcuts_run",
                description: "Run an Apple Shortcut by name. Requires user approval. This is the safest way to let Clicky control your Mac via automations you define.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Shortcut name (as shown in the Shortcuts app)."],
                        "input": ["type": "string", "description": "Optional input passed to the shortcut."],
                    ],
                    "required": ["name"],
                ]
            ),
            OpenAICompatibleChatAPI.ToolDefinition(
                name: "applescript_run",
                description: "Run AppleScript via osascript. Requires user approval. Powerful and potentially dangerous.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "script": ["type": "string", "description": "AppleScript source code."],
                    ],
                    "required": ["script"],
                ]
            ),
        ]
    }

    func handleToolCall(toolName: String, arguments: [String: JSONValue]) async throws -> String? {
        switch toolName {
        case "fs_list_dir":
            return try handleListDir(arguments: arguments)
        case "fs_read_file":
            return try handleReadFile(arguments: arguments)
        case "fs_write_file":
            return try await handleWriteFile(arguments: arguments)
        case "shell_run":
            return try await handleShellRun(arguments: arguments)
        case "mac_open":
            return try await handleMacOpen(arguments: arguments)
        case "mac_frontmost_app":
            return handleFrontmostApp()
        case "mac_launch_app":
            return try await handleLaunchApp(arguments: arguments)
        case "mac_reveal_in_finder":
            return try await handleRevealInFinder(arguments: arguments)
        case "clipboard_get":
            return handleClipboardGet()
        case "clipboard_set":
            return try await handleClipboardSet(arguments: arguments)
        case "shortcuts_run":
            return try await handleShortcutsRun(arguments: arguments)
        case "applescript_run":
            return try await handleAppleScriptRun(arguments: arguments)
        default:
            return nil
        }
    }

    private func handleListDir(arguments: [String: JSONValue]) throws -> String {
        guard workspaceManager.hasWorkspaceFolderConfigured else {
            return "No workspace folder configured. In Clicky → Mac Tools, click Choose to select a folder."
        }
        let path = arguments["path"]?.stringValue ?? "."
        let url = try workspaceManager.resolveUserPath(path)

        let items = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let lines: [String] = items
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            .map { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDirectory = values?.isDirectory ?? false
                let fileSize = values?.fileSize ?? 0
                let suffix = isDirectory ? "/" : " (\(fileSize) bytes)"
                return itemURL.lastPathComponent + suffix
            }

        return lines.joined(separator: "\n")
    }

    private func handleReadFile(arguments: [String: JSONValue]) throws -> String {
        guard workspaceManager.hasWorkspaceFolderConfigured else {
            return "No workspace folder configured. In Clicky → Mac Tools, click Choose to select a folder."
        }
        let path = arguments["path"]?.stringValue ?? ""
        let maxBytes = arguments["max_bytes"]?.intValue ?? 20_000
        let url = try workspaceManager.resolveUserPath(path)

        let data = try Data(contentsOf: url)
        let truncatedData = data.prefix(max(0, maxBytes))
        let text = String(data: truncatedData, encoding: .utf8) ?? ""

        if data.count > truncatedData.count {
            return text + "\n\n…(truncated \(data.count - truncatedData.count) bytes)"
        }
        return text
    }

    private func handleWriteFile(arguments: [String: JSONValue]) async throws -> String {
        guard isFileWriteEnabled else {
            throw PermissionError.toolDisabled("File writing is disabled. Enable “File Write” in Clicky → Mac Tools.")
        }
        guard workspaceManager.hasWorkspaceFolderConfigured else {
            return "No workspace folder configured. In Clicky → Mac Tools, click Choose to select a folder."
        }

        let path = arguments["path"]?.stringValue ?? ""
        let content = arguments["content"]?.stringValue ?? ""
        let overwrite = arguments["overwrite"]?.boolValue ?? false

        let url = try workspaceManager.resolveUserPath(path)

        if FileManager.default.fileExists(atPath: url.path), !overwrite {
            return "Refused: file already exists and overwrite=false."
        }

        let approved = approvalPresenter.requestApproval(
            title: "Clicky wants to write a file",
            message: "Allow Clicky to write this file?",
            details: "\(url.path)\n\nBytes: \(content.utf8.count)"
        )
        guard approved else { throw PermissionError.deniedByUser }

        let parentURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        guard let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "LocalMacToolRunner", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode content as UTF-8.",
            ])
        }
        try contentData.write(to: url, options: [.atomic])

        return "Wrote \(content.utf8.count) bytes to \(path)"
    }

    private func handleShellRun(arguments: [String: JSONValue]) async throws -> String {
        guard isShellEnabled else {
            throw PermissionError.toolDisabled("Shell commands are disabled. Enable “Shell” in Clicky → Mac Tools.")
        }
        guard workspaceManager.hasWorkspaceFolderConfigured else {
            return "No workspace folder configured. In Clicky → Mac Tools, click Choose to select a folder."
        }

        let command = arguments["command"]?.stringValue ?? ""
        let timeoutSeconds = arguments["timeout_seconds"]?.intValue ?? 30

        let approved = approvalPresenter.requestApproval(
            title: "Clicky wants to run a command",
            message: "Allow Clicky to run this shell command?",
            details: command
        )
        guard approved else { throw PermissionError.deniedByUser }

        let workspaceURL = try workspaceManager.resolveUserPath(".")
        let result = try await runShellCommand(
            command: command,
            workingDirectoryURL: workspaceURL,
            timeoutSeconds: max(1, timeoutSeconds)
        )
        return result
    }

    private func handleMacOpen(arguments: [String: JSONValue]) async throws -> String {
        let target = arguments["target"]?.stringValue ?? ""
        let approved = approvalPresenter.requestApproval(
            title: "Clicky wants to open something",
            message: "Allow Clicky to open this target?",
            details: target
        )
        guard approved else { throw PermissionError.deniedByUser }

        if let url = URL(string: target), url.scheme != nil {
            NSWorkspace.shared.open(url)
            return "Opened URL: \(target)"
        }

        let fileURL = URL(fileURLWithPath: target)
        NSWorkspace.shared.open(fileURL)
        return "Opened path: \(target)"
    }

    private func handleFrontmostApp() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        let name = app?.localizedName ?? "unknown"
        let bundleIdentifier = app?.bundleIdentifier ?? "unknown"
        return "Frontmost app: \(name) (\(bundleIdentifier))"
    }

    private func handleLaunchApp(arguments: [String: JSONValue]) async throws -> String {
        let appName = arguments["app_name"]?.stringValue ?? ""
        let approved = approvalPresenter.requestApproval(
            title: "Clicky wants to open an app",
            message: "Allow Clicky to launch or activate this app?",
            details: appName
        )
        guard approved else { throw PermissionError.deniedByUser }

        if let appPath = NSWorkspace.shared.fullPath(forApplication: appName) {
            let appURL = URL(fileURLWithPath: appPath)
            let configuration = NSWorkspace.OpenConfiguration()
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return "Launched app: \(appName)"
        }

        let ok = NSWorkspace.shared.launchApplication(appName)
        return ok ? "Launched app: \(appName)" : "Failed to launch app: \(appName) (app not found)"
    }

    private func handleRevealInFinder(arguments: [String: JSONValue]) async throws -> String {
        let path = arguments["path"]?.stringValue ?? ""

        let approved = approvalPresenter.requestApproval(
            title: "Clicky wants to reveal a file in Finder",
            message: "Allow Clicky to reveal this path?",
            details: path
        )
        guard approved else { throw PermissionError.deniedByUser }

        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if workspaceManager.hasWorkspaceFolderConfigured {
            url = try workspaceManager.resolveUserPath(path)
        } else {
            return "No workspace folder configured, and the path was not absolute."
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        return "Revealed in Finder: \(url.path)"
    }

    private func handleClipboardGet() -> String {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            return text
        }
        return ""
    }

    private func handleClipboardSet(arguments: [String: JSONValue]) async throws -> String {
        let text = arguments["text"]?.stringValue ?? ""
        let approved = approvalPresenter.requestApproval(
            title: "Clicky wants to set your clipboard",
            message: "Allow Clicky to overwrite your clipboard?",
            details: "Characters: \(text.count)"
        )
        guard approved else { throw PermissionError.deniedByUser }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return "Clipboard updated."
    }

    private func handleShortcutsRun(arguments: [String: JSONValue]) async throws -> String {
        let name = arguments["name"]?.stringValue ?? ""
        let input = arguments["input"]?.stringValue

        let approved = approvalPresenter.requestApproval(
            title: "Clicky wants to run a Shortcut",
            message: "Allow Clicky to run this Shortcut?",
            details: input.map { "\(name)\n\nInput:\n\($0)" } ?? name
        )
        guard approved else { throw PermissionError.deniedByUser }

        return try await runShortcutsCLI(shortcutName: name, input: input)
    }

    private func handleAppleScriptRun(arguments: [String: JSONValue]) async throws -> String {
        guard isAppleScriptEnabled else {
            throw PermissionError.toolDisabled("AppleScript is disabled. Enable “AppleScript” in Clicky → Mac Tools.")
        }

        let script = arguments["script"]?.stringValue ?? ""
        let preview = String(script.prefix(800))

        let approved = approvalPresenter.requestApproval(
            title: "Clicky wants to run AppleScript",
            message: "Allow Clicky to run this AppleScript?",
            details: preview + (script.count > preview.count ? "\n…(truncated preview)" : "")
        )
        guard approved else { throw PermissionError.deniedByUser }

        return try await runAppleScript(script: script)
    }

    private func runAppleScript(script: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

                let combined = [
                    stdoutText.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderrText.trimmingCharacters(in: .whitespacesAndNewlines),
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

                let exitCode = process.terminationStatus
                let header = "Exit \(exitCode)"
                let output = combined.isEmpty ? header : "\(header)\n\(combined)"
                continuation.resume(returning: output)
            }
        }
    }

    private func runShortcutsCLI(shortcutName: String, input: String?) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")

        var arguments: [String] = ["run", shortcutName]
        if let input, !input.isEmpty {
            arguments += ["--input", input]
        }
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

                let combined = [
                    stdoutText.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderrText.trimmingCharacters(in: .whitespacesAndNewlines),
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

                let exitCode = process.terminationStatus
                let header = "Exit \(exitCode)"
                let output = combined.isEmpty ? header : "\(header)\n\(combined)"
                continuation.resume(returning: output)
            }
        }
    }

    private func runShellCommand(
        command: String,
        workingDirectoryURL: URL,
        timeoutSeconds: Int
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            func resumeOnce(_ result: Result<String, Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let timeoutTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutSeconds), repeats: false) { _ in
                if process.isRunning {
                    process.terminate()
                }
                resumeOnce(.success("Timed out after \(timeoutSeconds)s."))
            }

            process.terminationHandler = { _ in
                timeoutTimer.invalidate()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

                let combined = [
                    stdoutText.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderrText.trimmingCharacters(in: .whitespacesAndNewlines),
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

                let exitCode = process.terminationStatus
                let header = "Exit \(exitCode)"
                let output = combined.isEmpty ? header : "\(header)\n\(combined)"
                let truncatedOutput = String(output.prefix(60_000))
                let finalOutput = output.count > 60_000 ? truncatedOutput + "\n…(truncated)" : truncatedOutput
                resumeOnce(.success(finalOutput))
            }
        }
    }
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}
