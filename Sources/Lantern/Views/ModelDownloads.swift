import AppKit
import LanternKit
import SwiftUI

/// One model you can download: what it's good for, its size, whether it suits this Mac, and a Download button
/// that turns into progress with Cancel.
struct ModelDownloadRow: View {
    let item: CatalogModel
    var divider = true
    @Environment(AppModel.self) private var model

    private var fit: CatalogFit { ModelCatalog.fit(item, totalMemory: model.totalMemory) }
    private var size: String { ByteCountFormatter.string(fromByteCount: item.downloadBytes, countStyle: .file) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(item.title)
                        Text(item.name).font(.callout).foregroundStyle(.tertiary)
                    }
                    Text(item.summary).foregroundStyle(.secondary)
                    if let error = model.downloadErrors[item.name] {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Label(fit.label, systemImage: fit == .good ? "checkmark.circle" : fit == .tight ? "exclamationmark.circle" : "xmark.circle")
                            .font(.callout)
                            .foregroundStyle(fit == .good ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.vertical, Space.md)
            if divider { Divider() }
        }
    }

    @ViewBuilder private var trailing: some View {
        if let progress = model.downloads[item.name] {
            VStack(alignment: .trailing, spacing: Space.xs) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction).frame(width: 160)
                } else {
                    ProgressView().controlSize(.small).frame(width: 160)
                }
                HStack(spacing: Space.sm) {
                    Text(progress.totalBytes > 0
                         ? "\(ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file))"
                         : progress.step)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Cancel") { model.cancelDownload(item.name) }
                }
            }
        } else if model.isInstalled(item.name) {
            Label("Installed", systemImage: "checkmark")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .trailing, spacing: Space.xs) {
                Button(model.downloadErrors[item.name] == nil ? "Download" : "Try Again") { model.download(item.name) }
                    .disabled(model.connection != .connected)
                    .help("Download \(item.title) (\(size)) through Ollama")
                Text(size).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// Settings > Models: the catalog, with the models that suit this Mac first, and any other Ollama model by name.
struct GetMoreModelsSection: View {
    @Environment(AppModel.self) private var model
    @State private var otherName = ""

    private var sorted: [CatalogModel] {
        let order: [CatalogFit] = [.good, .tight, .tooBig]
        return ModelCatalog.models.enumerated().sorted { a, b in
            let fa = order.firstIndex(of: ModelCatalog.fit(a.element, totalMemory: model.totalMemory)) ?? 0
            let fb = order.firstIndex(of: ModelCatalog.fit(b.element, totalMemory: model.totalMemory)) ?? 0
            return fa == fb ? a.offset < b.offset : fa < fb
        }.map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Get More Models").font(.title3)
                Text("Free, from Ollama's library").foregroundStyle(.secondary)
            }
            .padding(.top, Space.section)
            .padding(.bottom, Space.sm)
            ForEach(sorted) { item in ModelDownloadRow(item: item) }
            SettingRow(title: "Any other model",
                       description: "Type a name from ollama.com/library, like mistral:7b.", divider: false) {
                HStack(spacing: Space.sm) {
                    TextField("Model name", text: $otherName, prompt: Text("name:tag"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(downloadOther)
                    if let progress = model.downloads[otherName.trimmingCharacters(in: .whitespaces)] {
                        Text(progress.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? progress.step)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Button("Download", action: downloadOther)
                            .disabled(otherName.trimmingCharacters(in: .whitespaces).isEmpty || model.connection != .connected)
                    }
                }
            }
            if let error = model.downloadErrors[otherName.trimmingCharacters(in: .whitespaces)] {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func downloadOther() {
        let name = otherName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        model.download(name)
    }
}

/// The first screen without models: the one that suits this Mac, ready to download, and the full list in Settings.
struct FirstModelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pick = ModelCatalog.recommended(totalMemory: model.totalMemory) ?? ModelCatalog.models.last { _ in true }
        VStack(spacing: Space.xl) {
            BrandMark().frame(width: 48, height: 48)
            VStack(spacing: Space.sm) {
                Text("Get your first model").font(TextStyle.display)
                Text("Models run on your Mac. This one suits your \(ByteCountFormatter.string(fromByteCount: model.totalMemory, countStyle: .memory)) of memory.")
                    .foregroundStyle(.secondary)
            }
            if let pick {
                ModelDownloadRow(item: pick, divider: false)
                    .padding(.horizontal, Space.xl)
                    .padding(.vertical, Space.sm)
                    .background(.fill.quinary, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .frame(maxWidth: 560)
            }
            Button("See All Models") { model.showModels() }
                .buttonStyle(.borderless)
        }
        .multilineTextAlignment(.center)
        .padding(Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// When Ollama isn't on this Mac: what it is, where to get it, and Local Mind notices once it's installed.
struct GetOllamaView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Space.xl) {
            BrandMark().frame(width: 48, height: 48)
            VStack(spacing: Space.sm) {
                Text("Local Mind runs on Ollama").font(TextStyle.display)
                Text("Ollama is a free app that runs AI models on your Mac. Install it, open it once, and come back here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            }
            HStack(spacing: Space.md) {
                Button("Download Ollama") { NSWorkspace.shared.open(AppModel.ollamaDownloadPage) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("I've Installed It") { Task { await model.connect() } }
                    .controlSize(.large)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Checks again every few seconds, so installing Ollama is enough.
        .task {
            while !Task.isCancelled, model.connection != .connected {
                try? await Task.sleep(for: .seconds(4))
                if AppModel.ollamaInstalled || model.connection == .failed { await model.connect() }
            }
        }
    }
}
