import SwiftUI
import LanternKit

struct ConversationPage: View {
    @Environment(AppModel.self) private var model

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A new conversation: the message box sits in the middle, under the greeting.
    /// Ollama couldn't be started because it isn't on this Mac.
    private var needsOllama: Bool { model.connection == .failed && !AppModel.ollamaInstalled }
    private var needsModel: Bool { model.connection == .connected && model.models.isEmpty }

    private var isHome: Bool {
        model.selectedConversation == nil && !needsModel && !needsOllama
    }

    var body: some View {
        // One message box that moves, rather than two, so what you've typed stays put:
        // on a new conversation the space above and below it centers it, and once the
        // conversation starts that space collapses and the box glides to the bottom.
        VStack(spacing: 0) {
            if let conversation = model.selectedConversation {
                MessageList(conversation: conversation)
                    .id(conversation.uid)
                    .transition(.opacity)
            } else if needsOllama {
                GetOllamaView()
            } else if needsModel {
                FirstModelView()
            } else {
                // Flexible room above the greeting; the room below the buttons matches it.
                Color.clear
                    .frame(minHeight: Space.section, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        WelcomeView()
                            .padding(.bottom, Space.xl)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
            }
            if !needsOllama && !(needsModel && model.selectedConversation == nil) {
                ConnectionStatus()
                Composer()
                    // Its glass would show through the dimmed window around Settings.
                    .opacity(model.showingSettings ? 0 : 1)
            }
            if isHome {
                StarterRow()
                    .transition(.opacity)
                // Equal room above and below, plus a little more below, sits the group just above center.
                Color.clear
                    .frame(minHeight: Space.section, maxHeight: .infinity)
                    .padding(.bottom, Space.section * 2)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: isHome)
        .gridArea("conversation", inset: 0)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.addFiles(urls) }
            return !urls.isEmpty
        }
        .navigationTitle(model.selectedConversation?.title ?? ConversationTitle.placeholder)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ModelPickerButton()
            }
            if let conversation = model.selectedConversation {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Share…") { model.share(conversation) }
                        Divider()
                        Button("Copy as Markdown") { model.copyMarkdown(of: conversation) }
                        Button("Save as Markdown…") { model.saveMarkdown(of: conversation) }
                        Button("Save as PDF…") { model.savePDF(of: conversation) }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .menuIndicator(.hidden)
                    .help("Share this conversation, or save it as a PDF or Markdown")
                }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("New Conversation", systemImage: "square.and.pencil") { model.newConversation() }
                    .help("Start a new conversation (⌘N)")
            }
        }
    }
}

/// Shows while Ollama is starting or can't be reached.
private struct ConnectionStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.connection {
            case .connected, .connecting:
                EmptyView()
            case .starting:
                Label {
                    Text("Starting Ollama…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: Layout.column, alignment: .leading)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.sm)
            case .failed:
                HStack(spacing: Space.md) {
                    Label("Unable to start Ollama. Open Ollama from Applications, then try again.",
                          systemImage: "exclamationmark.triangle")
                    Spacer(minLength: Space.sm)
                    Button("Try Again") { Task { await model.connect() } }
                        .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: Layout.column)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.sm)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The field where you write a message, with Send and Stop.
private struct Composer: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var fieldHeight: CGFloat = Space.lg

    private var canSend: Bool {
        model.connection == .connected && model.currentModelName != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let notice = model.attachmentNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let warning = model.memoryWarning, warning.surface == .main {
                MemoryWarningView(warning: warning) {
                    if model.send(draft, skipMemoryCheck: true) { draft = "" }
                }
            }
            if let warning = model.attachmentLengthWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.isQueued(model.selection) {
                Label("Sends as soon as the reply in your other chat finishes", systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.replies.isWriting, !(model.selectedConversation.map(model.isWriting(in:)) ?? false) {
                Label("Another chat is replying. A message you send here waits its turn.", systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !model.draftAttachments.isEmpty { DraftAttachmentRow() }
            HStack(alignment: .bottom, spacing: Space.md) {
            Button("Attach Files", systemImage: "paperclip") { model.chooseFiles() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Attach images, PDFs, or text files (⇧⌘A)")
                .frame(width: Space.xl)
                .padding(.vertical, Space.xs)

            ComposerField(text: $draft, height: $fieldHeight,
                          isEnabled: model.connection == .connected,
                          focusRequest: model.focusRequest, mayTakeFocus: { model.renamingID == nil }, maxLines: 8, onSubmit: submit,
                          onPasteFiles: { urls in Task { await model.addFiles(urls) } },
                          onPasteImage: { data in Task { await model.addPastedImage(data) } },
                          onMoveConversation: { model.selectAdjacentConversation(by: $0) })
                .frame(height: fieldHeight)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Ask anything")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.vertical, Space.xs)
                .gridProbe("message-field", area: "conversation", edge: nil)

            if model.selectedConversation.map(model.isWriting(in:)) ?? false {
                Button("Stop", systemImage: "stop.fill") { model.stop() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .keyboardShortcut(.cancelAction)
                    .help("End this reply and keep its text so far (⎋)")
            } else {
                Button("Send", systemImage: "arrow.up") { submit() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!canSend)
                    .help("Send this message to the model (↩)")
            }
            }
        }
        .padding(Space.md)
        // The composer floats over the conversation, so it gets Liquid Glass.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.lg))
        .frame(maxWidth: Layout.column)
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.margin)
        .padding(.top, Space.sm)
        .frame(maxWidth: .infinity)
        .onChange(of: model.selection) { old, new in
            draft = model.swapDraft(leaving: old, text: draft, opening: new)
        }
        .onChange(of: model.prefill) {
            guard let text = model.prefill else { return }
            draft = text
            model.prefill = nil
            model.focusRequest += 1
        }
        .onChange(of: model.composerResetRequest) {
            draft = ""
            model.draftAttachments = []
        }
    }

    private func submit() {
        if model.send(draft) { draft = "" }
    }
}

/// The toolbar control that shows and changes the model.
private struct ModelPickerButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let name = model.currentModelName
        let memory = model.loaded.first { $0.name == name }?.memory
        Button {
            model.showingModelPicker.toggle()
        } label: {
            // The aperture and the name share one center line; a long name is cut in the middle,
            // which keeps both its family and its size readable.
            HStack(alignment: .center, spacing: Space.sm) {
                // Open when this model is in memory and replies start at once.
                Image(nsImage: ApertureIcon.image(memory != nil ? .open : .closed))
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(memory != nil ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
                Text(name.map(model.displayName) ?? "No Models")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200)
                    .fixedSize(horizontal: name.map(model.displayName)?.count ?? 0 < 22, vertical: false)
            }
            // Room inside the pill, so the aperture and the name don't touch its edge.
            .padding(.horizontal, Space.xs)
        }
        .disabled(model.isWriting || model.models.isEmpty)
        .help(memory.map { "In memory (\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))), so replies start at once. Click to choose another model (⇧⌘M)." }
              ?? "Not in memory yet. It loads when you send. Click to choose another model (⇧⌘M).")
        .popover(isPresented: $model.showingModelPicker, arrowEdge: .bottom) {
            ModelPicker()
        }
    }
}

private struct ModelPicker: View {
    @Environment(AppModel.self) private var model
    @State private var highlighted: String?
    @FocusState private var isFocused: Bool

    /// Rows are 24 tall, plus 12 for a renamed model's second line.
    private var pickerHeight: CGFloat {
        let shown = model.models.prefix(8)
        return CGFloat(shown.count) * 24 + CGFloat(shown.filter { model.modelNicknames[$0.name] != nil }.count) * 12 + 24
    }

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            Button {
                model.showingModelPicker = false
                model.showModels()
            } label: {
                Label("Manage Models…", systemImage: "cpu")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.lg)
            .frame(height: 36)
            .help("See every model, test them, and set the default (⇧⌘L)")
        }
    }

    private var list: some View {
        List(model.models, selection: $highlighted) { item in
            HStack(spacing: Space.sm) {
                Image(systemName: "checkmark")
                    .opacity(item.name == model.currentModelName ? 1 : 0)
                    .accessibilityHidden(true)
                ModelNameLabel(name: item.name)
                Spacer(minLength: Space.md)
                Text(item.size, format: .byteCount(style: .file))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.chooseModel(item.name) }
            .tag(item.name)
        }
        .focused($isFocused)
        .onKeyPress(.return) {
            if let highlighted { model.chooseModel(highlighted) }
            return .handled
        }
        .frame(width: 320, height: pickerHeight) // grid: ok computed from the rows
        .onAppear {
            highlighted = model.currentModelName
            isFocused = true
        }
    }
}
