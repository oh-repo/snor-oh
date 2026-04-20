import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Auto-route rules section for the Bucket settings tab. Rows expose an
/// enable toggle, condition label, target-bucket menu, and delete button.
/// The `[+ Add rule]` button opens a popover composer.
@MainActor
struct AutoRouteRulesSection: View {
    let manager: BucketManager

    @State private var showAddPopover: Bool = false

    var body: some View {
        Section("Auto-route rules") {
            if manager.settings.autoRouteRules.isEmpty {
                Text("No rules yet. Items always land in the active bucket.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.settings.autoRouteRules) { rule in
                    AutoRouteRuleRow(manager: manager, rule: rule)
                }
            }

            HStack {
                Spacer()
                Button { showAddPopover = true } label: {
                    Label("Add rule", systemImage: "plus")
                }
                .popover(isPresented: $showAddPopover, arrowEdge: .top) {
                    AutoRouteRuleComposer(manager: manager, isPresented: $showAddPopover)
                }
            }
        }
    }
}

// MARK: - Rule row

@MainActor
private struct AutoRouteRuleRow: View {
    let manager: BucketManager
    let rule: AutoRouteRule

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { _ in manager.toggleAutoRouteRule(id: rule.id) }
        )
    }

    private var targetName: String {
        manager.buckets.first { $0.id == rule.bucketID }?.name ?? "(missing)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            Text(AutoRouteLabels.describe(rule.condition))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Menu(targetName) {
                ForEach(manager.activeBuckets) { bucket in
                    Button {
                        var updated = rule
                        updated.bucketID = bucket.id
                        manager.updateAutoRouteRule(updated)
                    } label: {
                        Text(bucket.emoji.map { "\($0)  \(bucket.name)" } ?? bucket.name)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                manager.removeAutoRouteRule(id: rule.id)
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove rule")
        }
    }
}

// MARK: - Composer popover

@MainActor
private struct AutoRouteRuleComposer: View {
    let manager: BucketManager
    @Binding var isPresented: Bool

    enum ConditionType: String, CaseIterable, Identifiable {
        case frontmost, itemKind, sourceApp, urlHost
        var id: String { rawValue }
        var label: String {
            switch self {
            case .frontmost: return "Frontmost"
            case .itemKind: return "Kind"
            case .sourceApp: return "Source"
            case .urlHost: return "URL host"
            }
        }
    }

    @State private var type: ConditionType = .itemKind
    @State private var kindSelection: BucketItemKind = .image
    @State private var hostValue: String = ""
    @State private var appBundleID: String = ""
    @State private var appDisplayName: String = ""
    @State private var targetBucketID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New auto-route rule").font(.system(size: 12, weight: .semibold))

            Picker("When", selection: $type) {
                ForEach(ConditionType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            conditionInputs

            Divider()

            Picker("Into", selection: $targetBucketID) {
                ForEach(manager.activeBuckets) { b in
                    Text(b.emoji.map { "\($0)  \(b.name)" } ?? b.name).tag(Optional(b.id))
                }
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add", action: commit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommit)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(minWidth: 380, idealWidth: 420, maxWidth: 520)
        .onAppear { targetBucketID = manager.activeBucketID }
    }

    @ViewBuilder
    private var conditionInputs: some View {
        switch type {
        case .frontmost, .sourceApp:
            HStack {
                Text(appDisplayName.isEmpty ? "No app selected" : appDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(appDisplayName.isEmpty ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose App…") { pickApp() }.controlSize(.small)
            }
            if !appBundleID.isEmpty {
                Text(appBundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        case .itemKind:
            Picker("Kind", selection: $kindSelection) {
                ForEach(BucketItemKind.allCases, id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            .labelsHidden()
        case .urlHost:
            TextField("github.com", text: $hostValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }

    private var canCommit: Bool {
        guard targetBucketID != nil else { return false }
        switch type {
        case .frontmost, .sourceApp: return !appBundleID.isEmpty
        case .itemKind: return true
        case .urlHost: return !hostValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func commit() {
        guard let targetID = targetBucketID else { return }
        let condition: RouteCondition
        switch type {
        case .frontmost:
            guard !appBundleID.isEmpty else { return }
            condition = .frontmostApp(bundleID: appBundleID)
        case .itemKind:
            condition = .itemKind(kindSelection)
        case .sourceApp:
            guard !appBundleID.isEmpty else { return }
            condition = .sourceApp(bundleID: appBundleID)
        case .urlHost:
            let trimmed = hostValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            condition = .urlHost(trimmed)
        }
        manager.addAutoRouteRule(AutoRouteRule(bucketID: targetID, condition: condition, enabled: true))
        isPresented = false
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let appURL = panel.url else { return }
        let bundle = Bundle(url: appURL)
        let info = bundle?.infoDictionary
        appBundleID = bundle?.bundleIdentifier ?? ""
        appDisplayName = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Human-readable labels

enum AutoRouteLabels {
    static func describe(_ condition: RouteCondition) -> String {
        switch condition {
        case .frontmostApp(let id): return "When \(appName(for: id)) is frontmost"
        case .itemKind(let kind):   return "When item is \(kind.rawValue)"
        case .sourceApp(let id):    return "When dragged from \(appName(for: id))"
        case .urlHost(let host):    return "When URL host is \(host)"
        }
    }

    /// Best-effort display-name resolution for a bundle ID; falls back to
    /// the bundle ID string when the app isn't installed locally.
    private static func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let info = Bundle(url: url)?.infoDictionary {
            if let name = info["CFBundleDisplayName"] as? String { return name }
            if let name = info["CFBundleName"] as? String { return name }
        }
        return bundleID
    }
}
