#if os(iOS)
// Runs published "AI Flows with LangChain" for an app user — parity with the
// Blazor AIFlowComponent: flow picker (or a fixed flowId), an input form
// generated from the flow's state channels, live streamed progress,
// human-in-the-loop approval, result rendering, and run history.

import SwiftUI
import WildwoodCore

public struct AIFlowComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let settings: AIFlowSettings
    private let onRunCompleted: ((AIFlowRunResult) -> Void)?

    @State private var model: WildwoodAIFlowModel?

    public init(
        settings: AIFlowSettings = AIFlowSettings(),
        onRunCompleted: ((AIFlowRunResult) -> Void)? = nil
    ) {
        self.settings = settings
        self.onRunCompleted = onRunCompleted
    }

    public var body: some View {
        Group {
            if let model {
                AIFlowView(model: model, settings: settings)
            } else {
                LoadingSpinnerView(label: "Loading flows…")
            }
        }
        .task {
            guard model == nil, let client = requireClient(client, component: "AIFlowComponent") else { return }
            let created = WildwoodAIFlowModel(client: client, settings: settings)
            created.onRunCompleted = onRunCompleted
            model = created
            await created.loadFlows()
        }
    }
}

// MARK: - Flow UI

private struct AIFlowView: View {
    @Bindable var model: WildwoodAIFlowModel
    let settings: AIFlowSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.title).font(.title3.weight(.bold))

            if model.isLoadingFlows {
                LoadingSpinnerView(label: "Loading flows…")
            } else if model.flows.isEmpty {
                ContentUnavailableView(
                    "No flows available",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("No published flows are available for this app.")
                )
            } else {
                flowPicker

                if let flow = model.selectedFlow {
                    if !flow.description.isEmpty {
                        Text(flow.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    inputForm(flow)
                    actions
                }
            }

            if !model.errorMessage.isEmpty {
                ErrorBannerView(message: model.errorMessage) { model.errorMessage = "" }
            }

            if settings.showLiveProgress, model.isRunning, let node = model.activeNode {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Running \(node)…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.streamText.isEmpty {
                outputBlock(label: "Output", text: model.streamText)
            }

            if let interrupt = model.pendingInterrupt {
                interruptPanel(interrupt)
            }

            if let result = model.result, model.pendingInterrupt == nil {
                resultBlock(result)
            }

            if settings.showRunHistory, !model.history.isEmpty {
                historyBlock
            }

            if settings.showDebugInfo, !model.debugEvents.isEmpty {
                debugBlock
            }
        }
    }

    @ViewBuilder private var flowPicker: some View {
        if settings.showFlowPicker, (settings.flowId ?? "").isEmpty {
            Picker("Flow", selection: Binding(
                get: { model.selectedFlowId ?? "" },
                set: { model.selectFlow(id: $0.isEmpty ? nil : $0) }
            )) {
                Text("Choose a flow…").tag("")
                ForEach(model.flows) { flow in
                    Text(flow.name).tag(flow.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isRunning)
        }
    }

    @ViewBuilder private func inputForm(_ flow: AIFlow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(flow.inputFields) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(field.name, text: Binding(
                        get: { model.input(for: field.name) },
                        set: { model.setInput($0, for: field.name) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.isRunning)
                }
            }
            if flow.inputFields.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input (JSON)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.rawInput)
                        .font(.callout.monospaced())
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                        .disabled(model.isRunning)
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if model.isRunning {
            Button(role: .destructive) {
                model.cancel()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                model.run()
            } label: {
                Text(settings.runLabel).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private func interruptPanel(_ payload: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Human review needed", systemImage: "person.fill.questionmark")
                .font(.subheadline.weight(.semibold))

            ScrollView {
                Text(payload)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)

            if model.isEditingResume {
                Text("Edited resume value (JSON) — leave blank to approve as-is")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.resumeEditValue)
                    .font(.caption.monospaced())
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                HStack {
                    Button("Resume with edit") { model.submitResumeEdit() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { model.cancelResumeEdit() }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
                .disabled(model.isRunning)
            } else {
                HStack {
                    Button("Approve") { model.approve() }
                        .buttonStyle(.borderedProminent)
                    Button("Edit & resume") { model.startResumeEdit() }
                        .buttonStyle(.bordered)
                    Button("Reject", role: .destructive) { model.reject() }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
                .disabled(model.isRunning)
            }
        }
        .padding()
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func resultBlock(_ result: AIFlowRunResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Result — \(result.status)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor(result.status))
                if result.totalTokens > 0 {
                    Text("· \(result.totalTokens) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage = result.errorMessage, !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage)
            } else if let output = result.outputJson, !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 260)
                .padding(8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Run history (this conversation)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.history) { run in
                HStack(spacing: 8) {
                    Text(run.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(run.status))
                        .frame(minWidth: 76, alignment: .leading)
                    if let createdAt = run.createdAt {
                        Text(createdAt.formatted(date: .numeric, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(historyMeta(run))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error = run.errorMessage, !error.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel(error)
                    }
                    Spacer()
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var debugBlock: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.debugEvents.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
    }

    @ViewBuilder private func outputBlock(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 260)
            .padding(8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func historyMeta(_ run: AIFlowRunSummary) -> String {
        var meta = "\(run.totalTokens) tokens"
        if let ms = run.durationMs {
            let seconds = (Double(ms) / 1000.0).formatted(.number.precision(.fractionLength(1)))
            meta += " · \(seconds)s"
        }
        return meta
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "succeeded": return .green
        case "failed": return .red
        case "interrupted": return .orange
        default: return .gray
        }
    }
}
#endif
