import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        NavigationStack {
            Form {
                if let viewModel {
                    syncSection(viewModel)
                    conflictSection(viewModel)
                    serverSection(viewModel)
                    storageSection(viewModel)
                }
            }
            .navigationTitle("Settings")
            .task {
                if viewModel == nil {
                    viewModel = SettingsViewModel(
                        repository: dependencies.repository,
                        imageCache: dependencies.imageCache,
                        syncEngine: dependencies.syncEngine
                    )
                }
                await viewModel?.refresh()
            }
        }
    }

    @ViewBuilder
    private func syncSection(_ viewModel: SettingsViewModel) -> some View {
        Section("Sync Status") {
            HStack {
                Text("Pending changes")
                Spacer()
                Text("\(viewModel.pendingCount)")
                    .foregroundStyle(.secondary)
            }
            Button("Sync Now") {
                viewModel.syncNow()
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await viewModel.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private func conflictSection(_ viewModel: SettingsViewModel) -> some View {
        Section {
            Picker(
                "Conflict Strategy",
                selection: Binding(get: { viewModel.mergeStrategy }, set: { viewModel.mergeStrategy = $0 })
            ) {
                ForEach(MergeStrategy.allCases) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            Text(viewModel.mergeStrategy.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Conflict Resolution")
        } footer: {
            Text("Applies the next time an item you edited offline conflicts with a server-side change.")
        }
    }

    @ViewBuilder
    private func serverSection(_ viewModel: SettingsViewModel) -> some View {
        Section {
            TextField(
                "Server URL",
                text: Binding(get: { viewModel.serverURLText }, set: { viewModel.serverURLText = $0 })
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .onSubmit { viewModel.validateAndSaveURL() }
            if let error = viewModel.urlError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button("Save Server URL") { viewModel.validateAndSaveURL() }
        } header: {
            Text("Mock API Server")
        } footer: {
            Text(
                "Use http://localhost:3000 in the Simulator, or http://<your Mac's IP>:3000 on a physical device — "
                + "see README for setup instructions."
            )
        }
    }

    @ViewBuilder
    private func storageSection(_ viewModel: SettingsViewModel) -> some View {
        Section("Storage") {
            HStack {
                Text("Image Cache")
                Spacer()
                Text(formattedBytes(viewModel.diskUsageBytes))
                    .foregroundStyle(.secondary)
            }
            Button("Clear Image Cache", role: .destructive) {
                viewModel.clearImageCache()
            }
        }
    }

    private func formattedBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
