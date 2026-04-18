import SwiftUI

/// First-launch setup wizard.
/// Shown when ~/.snor-oh/setup-done does not exist.
/// Steps: Welcome → Installing → Done.

// MARK: - Setup Model (class for stable reference in async closures)

@Observable
final class SetupModel {
    var step: SetupWizard.Step = .welcome
    var setupLog: [SetupLogEntry] = []
    var error: String?

    struct SetupLogEntry: Identifiable {
        let id = UUID()
        let message: String
    }

    func runSetup() {
        step = .installing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            MCPInstaller.installServer()
            DispatchQueue.main.async { self?.setupLog.append(.init(message: "MCP server installed")) }

            MCPInstaller.installShellHooks()
            DispatchQueue.main.async { self?.setupLog.append(.init(message: "Shell hooks installed")) }

            ClaudeHooks.setup()
            DispatchQueue.main.async { self?.setupLog.append(.init(message: "Claude Code hooks configured")) }

            MCPInstaller.registerServer()
            DispatchQueue.main.async { self?.setupLog.append(.init(message: "MCP server registered")) }

            // Write setup-done marker only if we got here
            let home = FileManager.default.homeDirectoryForCurrentUser
            let marker = home.appendingPathComponent(".snor-oh/setup-done")
            let dir = marker.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: marker.path, contents: nil)

            DispatchQueue.main.async {
                self?.setupLog.append(.init(message: "Setup complete"))
                self?.step = .done
            }
        }
    }
}

// MARK: - Setup Wizard View

struct SetupWizard: View {
    @State private var model = SetupModel()
    let onComplete: () -> Void

    enum Step: Int, CaseIterable {
        case welcome
        case installing
        case done
    }

    var body: some View {
        VStack(spacing: 20) {
            switch model.step {
            case .welcome:
                welcomeView
            case .installing:
                installingView
            case .done:
                doneView
            }
        }
        .frame(width: 400, height: 300)
        .padding(24)
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "pawprint.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Welcome to snor-oh!")
                .font(.title.bold())

            Text("Your desktop mascot will react to terminal and Claude Code activity. Let's set things up.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Spacer()

            Button("Get Started") {
                model.runSetup()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Installing

    private var installingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Setting up...")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.setupLog) { entry in
                    Label(entry.message, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All Set!")
                .font(.title.bold())

            Text("snor-oh is ready. Open a terminal and start coding — your mascot will react to your activity.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Spacer()

            Button("Done") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
