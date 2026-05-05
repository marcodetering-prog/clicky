import AppKit
import Foundation

enum ActiveBrowserURLDetector {
    static func getFrontmostBrowserActiveTabURLString() -> String? {
        // Best-effort. If the user hasn't granted Apple Events automation permissions,
        // this will fail and we'll just return nil.
        let script = """
        tell application "System Events"
          set frontApp to name of first application process whose frontmost is true
        end tell

        if frontApp is "Google Chrome" then
          tell application "Google Chrome"
            return URL of active tab of front window
          end tell
        end if

        if frontApp is "Arc" then
          tell application "Arc"
            return URL of active tab of front window
          end tell
        end if

        if frontApp is "Brave Browser" then
          tell application "Brave Browser"
            return URL of active tab of front window
          end tell
        end if

        if frontApp is "Chromium" then
          tell application "Chromium"
            return URL of active tab of front window
          end tell
        end if

        if frontApp is "Microsoft Edge" then
          tell application "Microsoft Edge"
            return URL of active tab of front window
          end tell
        end if

        if frontApp is "Safari" then
          tell application "Safari"
            return URL of front document
          end tell
        end if

        return ""
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error {
            print("🌐 ActiveBrowserURLDetector error: \(error)")
            return nil
        }

        let urlString = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !urlString.isEmpty else { return nil }
        return urlString
    }
}

