import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileDropCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let allowedExtensions: [String]
    let pickDirectoriesAsBundle: Bool
    @Binding var fileURL: URL?

    @State private var isTargeted = false

    var body: some View {
        Group {
            if let url = fileURL {
                filledContent(url: url)
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 170)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isTargeted ? accent : (fileURL == nil ? Color.gray.opacity(0.30) : accent.opacity(0.45)),
                    style: StrokeStyle(
                        lineWidth: isTargeted ? 2.5 : 1,
                        dash: fileURL == nil && !isTargeted ? [6, 4] : []
                    )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { presentOpenPanel() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, validate(url: url) else { return false }
            fileURL = url
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .animation(.easeInOut(duration: 0.15), value: fileURL)
    }

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(accent)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Drop here or click to browse")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private func filledContent(url: URL) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(accent)
            Text(url.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(url.deletingLastPathComponent().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Button("Change") { presentOpenPanel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(role: .destructive) {
                    fileURL = nil
                } label: {
                    Text("Clear")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Choose \(title)"
        if pickDirectoriesAsBundle {
            // .icon files are bundle directories without a system UTType.
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.treatsFilePackagesAsDirectories = false
        } else {
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.application]
        }
        if panel.runModal() == .OK, let url = panel.url, validate(url: url) {
            fileURL = url
        }
    }

    private func validate(url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }
}
