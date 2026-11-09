import SwiftUI
import LanternKit

struct ConversationPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let conversation = model.selectedConversation {
                MessageList(conversation: conversation)
                    .id(conversation.uid)
            } else if model.connection == .connected && model.models.isEmpty {
                NoModelsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(ConversationTitle.placeholder, systemImage: "lightbulb")
                } description: {
                    Text("Replies are written on this Mac by local models. Nothing leaves it.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ConnectionStatus()
            Composer()
        }
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
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("New Conversation", systemImage: "square.and.pencil") { model.newConversation() }
                    .help("Start a conversation with the default model (⌘N)")
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
            if let warning = model.attachmentLengthWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !model.draftAttachments.isEmpty { DraftAttachmentRow() }
            HStack(alignment: .bottom, spacing: Space.sm) {
            Button("Attach Files", systemImage: "paperclip") { model.chooseFiles() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Attach images, PDFs, or text files (⇧⌘A)")
                .frame(width: Space.xl)
                .padding(.vertical, Space.xs)

            ComposerField(text: $draft, height: $fieldHeight,
                          isEnabled: model.connection == .connected,
                          focusRequest: model.focusRequest, maxLines: 8, onSubmit: submit,
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

            if model.isWriting {
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
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: Radius.lg))
        .frame(maxWidth: Layout.column)
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.margin)
        .padding(.top, Space.sm)
        .frame(maxWidth: .infinity)
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
        Button {
            model.showingModelPicker.toggle()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "cpu")
                if let name = model.currentModelName {
                    ModelNameLabel(name: name)
                } else {
                    Text("No Models")
                }
            }
        }
        .disabled(model.isWriting || model.models.isEmpty)
        .help("Choose which model writes the next reply (⇧⌘M)")
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
