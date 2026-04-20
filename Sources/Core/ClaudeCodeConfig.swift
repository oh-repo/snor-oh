import Foundation

// MARK: - Data Models

struct ClaudePlugin: Identifiable {
    let id: String
    let name: String
    let marketplace: String
    let version: String
    let installPath: String
    let installedAt: String
    let skills: [String]
    var isEnabled: Bool
}

struct ClaudeSkill: Identifiable {
    let id: String
    let name: String
    let description: String
    let path: URL
    let isSymlink: Bool
}

struct ClaudeCommand: Identifiable {
    let id: String
    let name: String
    let description: String
    let path: URL
}

struct ClaudeMCPServer: Identifiable {
    let id: String
    let name: String
    let command: String?
    let args: [String]
    let url: String?
    let env: [String: String]
    let serverType: String   // "stdio" or "http"
    let source: String
}

struct ProjectMCPGroup: Identifiable {
    let id: String
    let projectPath: String
    let projectName: String
    let servers: [ClaudeMCPServer]
}

struct ClaudeHookEntry: Identifiable {
    let id: UUID
    let event: String
    let matcher: String
    let command: String
    let timeout: Int?
    let isAsync: Bool
    let statusMessage: String?
}

struct HookEventGroup {
    let event: String
    let hooks: [ClaudeHookEntry]
}

// MARK: - Config Manager

@Observable
final class ClaudeCodeConfigManager {
    var plugins: [ClaudePlugin] = []
    var skills: [ClaudeSkill] = []
    var commands: [ClaudeCommand] = []
    var mcpServers: [ClaudeMCPServer] = []
    var projectMCPServers: [ProjectMCPGroup] = []
    var hooks: [ClaudeHookEntry] = []

    private let fm = FileManager.default

    private var claudeDir: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }
    private var settingsURL: URL {
        claudeDir.appendingPathComponent("settings.json")
    }
    private var globalClaudeJSON: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    func loadAll() {
        loadPlugins()
        loadSkills()
        loadCommands()
        loadMCPServers()
        loadHooks()
    }

    // MARK: - Computed

    var hookEvents: [HookEventGroup] {
        let grouped = Dictionary(grouping: hooks, by: \.event)
        return grouped.keys.sorted().map { HookEventGroup(event: $0, hooks: grouped[$0]!) }
    }

    func isOwnHook(_ hook: ClaudeHookEntry) -> Bool {
        ClaudeHooks.isSnorOhCommand(hook.command)
            || hook.command.contains("snor-oh")
            || hook.command.contains("snoroh")
    }

    /// Human-readable label: prefer statusMessage, then parse known patterns.
    func hookLabel(_ hook: ClaudeHookEntry) -> String {
        if let msg = hook.statusMessage, !msg.isEmpty { return msg }
        let cmd = hook.command
        if ClaudeHooks.isSnorOhCommand(cmd) {
            if cmd.contains("state=busy") { return "Track session as busy" }
            if cmd.contains("state=idle") { return "Track session as idle" }
            return "Session tracking"
        }
        if cmd.contains("gitnexus") { return "GitNexus hook" }
        let clean = cmd
            .replacingOccurrences(of: " > /dev/null 2>&1 || true", with: "")
            .replacingOccurrences(of: " 2>/dev/null", with: "")
        let line = clean.components(separatedBy: "\n").first ?? clean
        return line.count > 80 ? String(line.prefix(77)) + "..." : line
    }

    func commandContent(for command: ClaudeCommand) -> String? {
        try? String(contentsOf: command.path, encoding: .utf8)
    }

    // MARK: - Plugins

    private func loadPlugins() {
        let url = claudeDir
            .appendingPathComponent("plugins")
            .appendingPathComponent("installed_plugins.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dict = json["plugins"] as? [String: Any] else {
            plugins = []; return
        }

        let enabled = readEnabledPlugins()
        plugins = dict.compactMap { key, value in
            guard let entries = value as? [[String: Any]], let first = entries.first else { return nil }
            let parts = key.split(separator: "@", maxSplits: 1)
            let installPath = first["installPath"] as? String ?? ""
            let pluginSkills: [String]
            if !installPath.isEmpty {
                let skillsDir = URL(fileURLWithPath: installPath).appendingPathComponent("skills")
                pluginSkills = (try? fm.contentsOfDirectory(atPath: skillsDir.path))?
                    .filter { name in
                        guard !name.hasPrefix(".") else { return false }
                        var isDir: ObjCBool = false
                        return fm.fileExists(
                            atPath: skillsDir.appendingPathComponent(name).path,
                            isDirectory: &isDir
                        ) && isDir.boolValue
                    }
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    ?? []
            } else {
                pluginSkills = []
            }
            return ClaudePlugin(
                id: key,
                name: String(parts.first ?? Substring(key)),
                marketplace: parts.count > 1 ? String(parts[1]) : "",
                version: first["version"] as? String ?? "",
                installPath: installPath,
                installedAt: first["installedAt"] as? String ?? "",
                skills: pluginSkills,
                isEnabled: enabled[key] ?? true
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func readEnabledPlugins() -> [String: Bool] {
        readSettingsJSON()["enabledPlugins"] as? [String: Bool] ?? [:]
    }

    func togglePlugin(_ plugin: ClaudePlugin) {
        guard let idx = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        plugins[idx].isEnabled.toggle()
        var settings = readSettingsJSON()
        var ep = settings["enabledPlugins"] as? [String: Bool] ?? [:]
        ep[plugin.id] = plugins[idx].isEnabled
        settings["enabledPlugins"] = ep
        writeJSON(settings, to: settingsURL)
    }

    // MARK: - Skills

    private func loadSkills() {
        let dir = claudeDir.appendingPathComponent("skills")
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { skills = []; return }

        skills = entries.compactMap { entry -> ClaudeSkill? in
            guard !entry.lastPathComponent.hasPrefix(".") else { return nil }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            let skillMD = entry.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMD.path) else { return nil }
            let content = (try? String(contentsOf: skillMD, encoding: .utf8)) ?? ""
            let meta = parseFrontmatter(content)
            let attrs = try? fm.attributesOfItem(atPath: entry.path)
            let isLink = (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
            return ClaudeSkill(
                id: entry.lastPathComponent,
                name: meta["name"] ?? entry.lastPathComponent,
                description: meta["description"] ?? "",
                path: entry,
                isSymlink: isLink
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func deleteSkill(_ skill: ClaudeSkill) {
        try? fm.removeItem(at: skill.path)
        skills.removeAll { $0.id == skill.id }
    }

    // MARK: - Commands

    private func loadCommands() {
        let dir = claudeDir.appendingPathComponent("commands")
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { commands = []; return }

        commands = entries.compactMap { entry -> ClaudeCommand? in
            guard entry.pathExtension == "md" else { return nil }
            let content = (try? String(contentsOf: entry, encoding: .utf8)) ?? ""
            let meta = parseFrontmatter(content)
            let filename = entry.deletingPathExtension().lastPathComponent
            return ClaudeCommand(
                id: filename,
                name: meta["name"] ?? filename,
                description: meta["description"] ?? "",
                path: entry
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func deleteCommand(_ command: ClaudeCommand) {
        try? fm.removeItem(at: command.path)
        commands.removeAll { $0.id == command.id }
    }

    // MARK: - MCP Servers

    private func loadMCPServers() {
        // Global servers from ~/.claude/settings.json and ~/.claude.json
        var globalResult: [ClaudeMCPServer] = []
        loadMCPFrom(settingsURL, source: "global", into: &globalResult)
        loadMCPFrom(globalClaudeJSON, source: "global", into: &globalResult)
        mcpServers = globalResult.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        // Per-project: read project list from ~/.claude.json, scan .claude/mcp.json
        projectMCPServers = []
        let globalJSON = readJSON(from: globalClaudeJSON)
        guard let projects = globalJSON["projects"] as? [String: Any] else { return }

        for (path, pconfig) in projects {
            var found: [String: ClaudeMCPServer] = [:]  // dedup by name

            // Source 1: ~/.claude.json projects[path].mcpServers
            if let pcfg = pconfig as? [String: Any],
               let servers = pcfg["mcpServers"] as? [String: Any] {
                for (name, cfg) in servers {
                    guard let c = cfg as? [String: Any] else { continue }
                    found[name] = makeMCPServer(name: name, config: c, source: path)
                }
            }

            // Source 2: <project>/.claude/mcp.json
            let mcpFile = URL(fileURLWithPath: path)
                .appendingPathComponent(".claude")
                .appendingPathComponent("mcp.json")
            if let json = readJSONIfExists(from: mcpFile),
               let servers = json["mcpServers"] as? [String: Any] {
                for (name, cfg) in servers where found[name] == nil {
                    guard let c = cfg as? [String: Any] else { continue }
                    found[name] = makeMCPServer(name: name, config: c, source: path)
                }
            }

            guard !found.isEmpty else { continue }
            let sorted = found.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            projectMCPServers.append(ProjectMCPGroup(
                id: path,
                projectPath: path,
                projectName: URL(fileURLWithPath: path).lastPathComponent,
                servers: sorted
            ))
        }
        projectMCPServers.sort {
            $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending
        }
    }

    private func loadMCPFrom(_ url: URL, source: String, into result: inout [ClaudeMCPServer]) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return }
        for (name, cfg) in servers {
            guard let config = cfg as? [String: Any] else { continue }
            result.append(makeMCPServer(name: name, config: config, source: source))
        }
    }

    private func makeMCPServer(name: String, config: [String: Any], source: String) -> ClaudeMCPServer {
        let hasURL = config["url"] as? String != nil
        return ClaudeMCPServer(
            id: "\(source):\(name)",
            name: name,
            command: config["command"] as? String,
            args: config["args"] as? [String] ?? [],
            url: config["url"] as? String,
            env: config["env"] as? [String: String] ?? [:],
            serverType: hasURL ? "http" : "stdio",
            source: source
        )
    }

    func addMCPServer(name: String, config: [String: Any], target: String) {
        let url = target == "global" ? globalClaudeJSON : settingsURL
        var json = readJSON(from: url)
        var servers = json["mcpServers"] as? [String: Any] ?? [:]
        servers[name] = config
        json["mcpServers"] = servers
        writeJSON(json, to: url)
        loadMCPServers()
    }

    func removeMCPServer(_ server: ClaudeMCPServer, projectPath: String? = nil) {
        if let projectPath {
            // Remove from ~/.claude.json projects[path].mcpServers
            var globalJSON = readJSON(from: globalClaudeJSON)
            if var projects = globalJSON["projects"] as? [String: Any],
               var project = projects[projectPath] as? [String: Any],
               var servers = project["mcpServers"] as? [String: Any] {
                servers.removeValue(forKey: server.name)
                project["mcpServers"] = servers
                projects[projectPath] = project
                globalJSON["projects"] = projects
                writeJSON(globalJSON, to: globalClaudeJSON)
            }
            // Also remove from <project>/.claude/mcp.json
            let mcpFile = URL(fileURLWithPath: projectPath)
                .appendingPathComponent(".claude")
                .appendingPathComponent("mcp.json")
            if var json = readJSONIfExists(from: mcpFile),
               var servers = json["mcpServers"] as? [String: Any] {
                servers.removeValue(forKey: server.name)
                json["mcpServers"] = servers
                writeJSON(json, to: mcpFile)
            }
        } else {
            // Remove from both global locations
            for url in [globalClaudeJSON, settingsURL] {
                var json = readJSON(from: url)
                if var servers = json["mcpServers"] as? [String: Any],
                   servers[server.name] != nil {
                    servers.removeValue(forKey: server.name)
                    json["mcpServers"] = servers
                    writeJSON(json, to: url)
                }
            }
        }
        loadMCPServers()
    }

    // MARK: - Hooks

    private func loadHooks() {
        guard let hooksDict = readSettingsJSON()["hooks"] as? [String: Any] else {
            hooks = []; return
        }
        var result: [ClaudeHookEntry] = []
        for (event, value) in hooksDict {
            guard let matchers = value as? [[String: Any]] else { continue }
            for matcherEntry in matchers {
                let matcher = matcherEntry["matcher"] as? String ?? ""
                guard let hooksList = matcherEntry["hooks"] as? [[String: Any]] else { continue }
                for hook in hooksList {
                    result.append(ClaudeHookEntry(
                        id: UUID(),
                        event: event,
                        matcher: matcher,
                        command: hook["command"] as? String ?? "",
                        timeout: hook["timeout"] as? Int,
                        isAsync: hook["async"] as? Bool ?? false,
                        statusMessage: hook["statusMessage"] as? String
                    ))
                }
            }
        }
        hooks = result
    }

    func addHook(event: String, matcher: String, command: String,
                 timeout: Int?, isAsync: Bool, statusMessage: String?) {
        hooks.append(ClaudeHookEntry(
            id: UUID(), event: event, matcher: matcher,
            command: command, timeout: timeout,
            isAsync: isAsync, statusMessage: statusMessage
        ))
        saveHooks()
    }

    func removeHook(_ hook: ClaudeHookEntry) {
        hooks.removeAll { $0.id == hook.id }
        saveHooks()
    }

    private func saveHooks() {
        var settings = readSettingsJSON()
        var hooksDict: [String: Any] = [:]

        var byEvent: [String: [ClaudeHookEntry]] = [:]
        for h in hooks { byEvent[h.event, default: []].append(h) }

        for (event, entries) in byEvent {
            var byMatcher: [String: [ClaudeHookEntry]] = [:]
            for e in entries { byMatcher[e.matcher, default: []].append(e) }

            hooksDict[event] = byMatcher.map { matcher, hookEntries -> [String: Any] in
                var entry: [String: Any] = [
                    "hooks": hookEntries.map { h -> [String: Any] in
                        var d: [String: Any] = ["type": "command", "command": h.command]
                        if let t = h.timeout { d["timeout"] = t }
                        if h.isAsync { d["async"] = true }
                        if let s = h.statusMessage { d["statusMessage"] = s }
                        return d
                    }
                ]
                if !matcher.isEmpty { entry["matcher"] = matcher }
                return entry
            }
        }

        settings["hooks"] = hooksDict.isEmpty ? nil : hooksDict
        writeJSON(settings, to: settingsURL)
    }

    // MARK: - JSON Helpers

    private func readSettingsJSON() -> [String: Any] {
        readJSON(from: settingsURL)
    }

    private func readJSON(from url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private func readJSONIfExists(from url: URL) -> [String: Any]? {
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private func writeJSON(_ json: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func parseFrontmatter(_ content: String) -> [String: String] {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var meta: [String: String] = [:]
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if let idx = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                meta[key] = value
            }
        }
        return meta
    }
}
