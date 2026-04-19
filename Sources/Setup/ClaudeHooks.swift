import Foundation

/// Configures Claude Code hooks in ~/.claude/settings.json so Claude activity
/// triggers snor-oh status updates (busy on tool use, idle on stop/session events).
enum ClaudeHooks {

    private static let aniMarker = "127.0.0.1:1234"
    private static let busyCmd = #"curl -s --max-time 1 "http://127.0.0.1:1234/status?pid=$PPID&state=busy&type=task&cwd=$PWD" > /dev/null 2>&1 || true"#
    private static let idleCmd = #"curl -s --max-time 1 "http://127.0.0.1:1234/status?pid=$PPID&state=idle&cwd=$PWD" > /dev/null 2>&1 || true"#

    /// Install Claude Code hooks if not already present.
    static func setup() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude")
        let settingsURL = claudeDir.appendingPathComponent("settings.json")

        // Load or create settings — bail if file exists but can't be parsed
        var settings: [String: Any]
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            guard let data = try? Data(contentsOf: settingsURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[setup] could not parse settings.json — skipping hook setup to avoid data loss")
                return
            }
            settings = json
        } else {
            try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            settings = [:]
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var added = 0

        added += addHook(to: &hooks, event: "PreToolUse", command: busyCmd)
        added += addHook(to: &hooks, event: "UserPromptSubmit", command: busyCmd)
        added += addHook(to: &hooks, event: "Stop", command: idleCmd)
        added += addHook(to: &hooks, event: "SessionStart", command: idleCmd)
        added += addHook(to: &hooks, event: "SessionEnd", command: idleCmd)

        guard added > 0 else {
            print("[setup] all claude hooks already present")
            return
        }

        settings["hooks"] = hooks

        // Write back
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            print("[setup] claude hooks written to \(settingsURL.path)")
        } catch {
            print("[setup] failed to write claude settings: \(error)")
        }
    }

    /// Migrate existing hooks:
    /// 1. Update outdated commands (pid=0 → $PPID, add cwd=$PWD)
    /// 2. Move snor-oh hooks out of restrictive matchers into their own empty-matcher entry
    static func migrate() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home.appendingPathComponent(".claude/settings.json")

        guard let data = try? Data(contentsOf: settingsURL),
              let content = String(data: data, encoding: .utf8) else { return }

        guard content.contains(aniMarker) else { return }

        guard var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }

        var patched = false
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }

            // Collect snor-oh commands to move into their own entry
            var snorohCmds: [String] = []

            for i in entries.indices {
                let matcher = entries[i]["matcher"] as? String ?? ""
                guard let hooksList = entries[i]["hooks"] as? [[String: Any]] else { continue }

                var updated: [[String: Any]] = []
                for hook in hooksList {
                    guard let cmd = hook["command"] as? String,
                          cmd.contains(aniMarker) else {
                        updated.append(hook)
                        continue
                    }

                    // Update outdated commands
                    var newCmd = cmd
                    if cmd.contains("pid=0") || !cmd.contains("cwd=") {
                        newCmd = cmd.contains("state=busy") ? busyCmd : idleCmd
                    }

                    if !matcher.isEmpty {
                        // Hook is in a restrictive matcher — move it out
                        snorohCmds.append(newCmd)
                        patched = true
                    } else if newCmd != cmd {
                        // In empty matcher, just update the command
                        var h = hook
                        h["command"] = newCmd
                        updated.append(h)
                        patched = true
                    } else {
                        updated.append(hook)
                    }
                }
                entries[i]["hooks"] = updated
            }

            // Remove empty entries
            entries.removeAll { entry in
                guard let hooksList = entry["hooks"] as? [[String: Any]] else { return true }
                return hooksList.isEmpty
            }

            // Add snor-oh hooks in their own empty-matcher entry
            if !snorohCmds.isEmpty {
                // Check if an empty-matcher snor-oh entry already exists
                let hasEmpty = entries.contains { entry in
                    let matcher = entry["matcher"] as? String ?? ""
                    guard matcher.isEmpty else { return false }
                    guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
                    return hooksList.contains { ($0["command"] as? String)?.contains(aniMarker) == true }
                }
                if !hasEmpty {
                    let hooksArray = snorohCmds.map { cmd -> [String: Any] in
                        ["type": "command", "command": cmd]
                    }
                    entries.append(["matcher": "", "hooks": hooksArray])
                }
            }

            hooks[event] = entries
        }

        guard patched else { return }

        settings["hooks"] = hooks
        if let newData = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? newData.write(to: settingsURL, options: .atomic)
            print("[setup] migrated claude hooks: fixed matchers and commands")
        }
    }

    // MARK: - Private

    /// Returns 1 if a hook was added, 0 if already present.
    @discardableResult
    private static func addHook(to hooks: inout [String: Any], event: String, command: String) -> Int {
        var entries = hooks[event] as? [[String: Any]] ?? []

        // Check if snor-oh hook already exists in any entry
        let hasHook = entries.contains { entry in
            guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
            return hooksList.contains { h in
                (h["command"] as? String)?.contains(aniMarker) == true
            }
        }

        if hasHook {
            return 0
        }

        // Always create a separate entry with empty matcher (= all tools).
        // Never append to existing entries that may have restrictive matchers
        // (e.g., "Grep|Glob|Bash" from gitnexus).
        entries.append([
            "matcher": "",
            "hooks": [["type": "command", "command": command]]
        ])

        hooks[event] = entries
        print("[setup] added claude hook for \(event)")
        return 1
    }
}
