import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: LogoLiquifyModel
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            cardsRow
            actionRow
            statusBlock
            if showLog {
                logBlock
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: showLog)
        .animation(.easeInOut(duration: 0.18), value: model.status)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Logo Liquify")
                    .font(.title.weight(.semibold))
                Text("Drop in a Liquid-Glass .icon and a .app — get a re-iconed, re-signed copy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var cardsRow: some View {
        HStack(spacing: 14) {
            FileDropCard(
                title: "Icon",
                subtitle: "An Icon Composer .icon bundle",
                systemImage: "app.gift",
                accent: .green,
                allowedExtensions: ["icon"],
                pickDirectoriesAsBundle: true,
                fileURL: $model.iconURL
            )
            FileDropCard(
                title: "App",
                subtitle: "The macOS .app to modify",
                systemImage: "app.dashed",
                accent: .pink,
                allowedExtensions: ["app"],
                pickDirectoriesAsBundle: false,
                fileURL: $model.appURL
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.start() }
            } label: {
                Label("Apply Icon & Re-sign", systemImage: "checkmark.seal.fill")
                    .frame(minWidth: 220)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStart)
            .keyboardShortcut(.return, modifiers: [.command])

            if case .working = model.status {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }

            Spacer()

            Button {
                showLog.toggle()
            } label: {
                Label(showLog ? "Hide Log" : "Show Log",
                      systemImage: showLog ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch model.status {
        case .idle:
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                Text("Pick an .icon and an .app to begin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .working(let line):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background.secondary)
            )
        case .readyToSave(let staged):
            VStack(alignment: .leading, spacing: 10) {
                Label("Ready to save", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text("Modified app is staged at:\n\(staged.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button {
                        presentSavePanel(staged: staged)
                    } label: {
                        Label("Save Modified App…", systemImage: "tray.and.arrow.down")
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Button("Reveal Staged") {
                        NSWorkspace.shared.activateFileViewerSelecting([staged])
                    }
                    .controlSize(.large)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.10))
            )
        case .saved(let dest):
            VStack(alignment: .leading, spacing: 10) {
                Label("Saved", systemImage: "tray.full.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text(dest.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([dest])
                    }
                    Button("Start Over") {
                        model.resetAll()
                    }
                }
                .controlSize(.large)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.10))
            )
        case .error(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Label("Failed", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.10))
            )
        }
    }

    private var logBlock: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.logLines.isEmpty {
                        Text("(no output yet)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(model.logLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.05))
            )
            .onChange(of: model.logLines.count) { _, count in
                if count > 0 {
                    withAnimation(.linear(duration: 0.05)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func presentSavePanel(staged: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.application]
        panel.nameFieldStringValue = staged.lastPathComponent
        panel.directoryURL = model.appURL?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        panel.title = "Save Modified App"
        panel.prompt = "Save"
        if panel.runModal() == .OK, let dest = panel.url {
            Task { await model.saveStaged(to: dest) }
        }
    }
}
