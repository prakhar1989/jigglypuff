import SwiftUI
import AppKit

/// Searchable transcription history window
public struct HistoryView: View {
    @ObservedObject var history = HistoryManager.shared
    @ObservedObject var settings = SettingsStore.shared
    @State private var searchText = ""
    @State private var selectedFilter: String = "All"
    @State private var copiedItemId: UUID? = nil

    public init() {}

    private var filteredItems: [TranscriptionItem] {
        history.items.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.text.localizedCaseInsensitiveContains(searchText) ||
                (item.targetAppName?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesFilter = selectedFilter == "All" || item.mode == selectedFilter
            return matchesSearch && matchesFilter
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search dictations...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)

                Picker("Filter", selection: $selectedFilter) {
                    Text("All Modes").tag("All")
                    ForEach(DictationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.displayName)
                    }
                }
                .frame(width: 160)

                Spacer()

                if !history.items.isEmpty {
                    Button(action: { history.clearAll() }) {
                        Text("Clear All")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // List Content
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    if !settings.saveHistory && history.items.isEmpty {
                        Text("History Saving Disabled")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("New dictations are not being saved. You can re-enable history in Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    } else {
                        Text(history.items.isEmpty ? "No dictations yet" : "No matching dictations")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Use ⌥ Space to dictate anywhere.")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredItems) { item in
                            historyCard(for: item)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    private func historyCard(for item: TranscriptionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // App and Timestamp
                if let app = item.targetAppName {
                    Label(app, systemImage: "app.dashed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text("•")
                    .foregroundColor(.secondary)

                Text(formattedDate(item.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                // Mode Badge
                Text(item.mode)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)

                // Duration
                Text(String(format: "%.1fs", item.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(item.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button(action: {
                    copyToClipboard(item: item)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedItemId == item.id ? "checkmark" : "doc.on.doc")
                        Text(copiedItemId == item.id ? "Copied!" : "Copy")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    history.delete(item: item)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
    }

    private func copyToClipboard(item: TranscriptionItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        copiedItemId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.copiedItemId == item.id {
                self.copiedItemId = nil
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
