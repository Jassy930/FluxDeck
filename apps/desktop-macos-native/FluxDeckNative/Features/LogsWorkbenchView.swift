import SwiftUI

struct LogsWorkbenchExpansionState: Equatable {
    var expandedRequestID: String? = nil

    mutating func toggle(requestID: String) {
        expandedRequestID = expandedRequestID == requestID ? nil : requestID
    }

    mutating func reconcileVisibleLogs(_ logs: [AdminLog]) {
        guard let expandedRequestID else {
            return
        }
        if !logs.contains(where: { $0.requestID == expandedRequestID }) {
            self.expandedRequestID = nil
        }
    }

    mutating func resetForFilterChange() {
        expandedRequestID = nil
    }
}

struct LogStreamCardModel: Equatable {
    let requestID: String
    let routeText: String
    let modelText: String
    let summaryText: String
    let statusText: String
    let latencyText: String
    let createdAtText: String
    let protocolText: String
    let streamText: String
    let firstByteText: String
    let tokenText: String
    let errorStageText: String
    let errorTypeText: String
    let errorDetailText: String
    let usageText: String?
    let isFailure: Bool

    static func make(log: AdminLog) -> LogStreamCardModel {
        let routeText = "\(log.gatewayID) -> \(log.providerID)"
        let modelText = log.modelDisplayText
        let summaryText = log.errorSummaryText != "-" ? log.errorSummaryText : modelText

        return LogStreamCardModel(
            requestID: log.requestID,
            routeText: routeText,
            modelText: modelText,
            summaryText: summaryText,
            statusText: "\(log.statusCode)",
            latencyText: "\(log.latencyMs) ms",
            createdAtText: log.createdAt,
            protocolText: "\(log.inboundProtocol ?? "-") -> \(log.upstreamProtocol ?? "-")",
            streamText: log.stream ? "Streaming" : "Non-stream",
            firstByteText: log.firstByteMs.map { "\($0) ms" } ?? "-",
            tokenText: log.tokenBreakdownText,
            errorStageText: log.errorStage ?? "-",
            errorTypeText: log.errorType ?? "-",
            errorDetailText: log.error ?? "-",
            usageText: log.usageJSON,
            isFailure: log.statusCode >= 400 || log.error != nil
        )
    }
}

struct LogsWorkbenchView: View {
    let logs: [AdminLog]
    let hasMore: Bool
    let isLoading: Bool
    let isLoadingMore: Bool
    let error: String?
    let gatewayOptions: [String]
    let providerOptions: [String]
    let statusOptions: [String]
    @Binding var selectedGateway: String
    @Binding var selectedProvider: String
    @Binding var selectedStatus: String
    @Binding var errorsOnly: Bool
    let onClearFilters: () -> Void
    let onLoadMore: () -> Void

    @State private var expansionState = LogsWorkbenchExpansionState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterBar

                if let error {
                    SurfaceCard {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.statusColors.error.fill)
                    }
                }

                SurfaceCard(title: "Request Stream") {
                    if isLoading && logs.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                    } else if logs.isEmpty {
                        Text("No request logs match current filters.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(logs) { log in
                                    let model = LogStreamCardModel.make(log: log)
                                    Button {
                                        expansionState.toggle(requestID: log.requestID)
                                    } label: {
                                        logCard(model: model, isExpanded: expansionState.expandedRequestID == log.requestID)
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                }
                            }

                            if hasMore {
                                Button(action: onLoadMore) {
                                    HStack(spacing: 8) {
                                        if isLoadingMore {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Text(isLoadingMore ? "Loading…" : "Load More")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(DesignTokens.surfaceSecondary.opacity(0.85))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(DesignTokens.borderSubtle.opacity(0.45), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .disabled(isLoadingMore)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            expansionState.reconcileVisibleLogs(logs)
        }
        .onChange(of: logs.map(\.requestID)) { _ in
            expansionState.reconcileVisibleLogs(logs)
        }
        .onChange(of: selectedGateway) { _ in
            expansionState.resetForFilterChange()
        }
        .onChange(of: selectedProvider) { _ in
            expansionState.resetForFilterChange()
        }
        .onChange(of: selectedStatus) { _ in
            expansionState.resetForFilterChange()
        }
        .onChange(of: errorsOnly) { _ in
            expansionState.resetForFilterChange()
        }
    }

    private var filterBar: some View {
        SurfaceCard(title: "Log Filters") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Gateway", selection: $selectedGateway) {
                        ForEach(gatewayOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(providerOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Status", selection: $selectedStatus) {
                        ForEach(statusOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Only Errors", isOn: $errorsOnly)
                        .toggleStyle(.switch)
                }

                HStack {
                    StatusPill(
                        text: hasMore ? "Loaded \(logs.count) requests" : "Loaded \(logs.count)",
                        semanticColor: DesignTokens.statusColors.running
                    )
                    if hasMore {
                        Text("More available")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    Spacer()
                    Button("Clear Filters", action: onClearFilters)
                        .buttonStyle(.plain)
                        .focusable(false)
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func logCard(model: LogStreamCardModel, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                StatusPill(text: model.statusText, semanticColor: semanticColor(forFailure: model.isFailure, statusText: model.statusText))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.routeText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                            Text(model.modelText)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DesignTokens.textPrimary)
                            if model.summaryText != model.modelText {
                                Text(model.summaryText)
                                    .font(.caption)
                                    .foregroundStyle(model.isFailure ? DesignTokens.statusColors.error.fill : DesignTokens.textSecondary)
                                    .lineLimit(isExpanded ? nil : 2)
                            }
                        }

                        Spacer(minLength: 12)

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(model.latencyText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                            Text(model.createdAtText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(DesignTokens.textSecondary)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                    }
                }
            }

            if isExpanded {
                Divider()
                    .overlay(DesignTokens.borderSubtle.opacity(0.85))

                VStack(alignment: .leading, spacing: 10) {
                    detailRow(label: "Request ID", value: model.requestID, monospaced: true)
                    detailRow(label: "Protocol", value: model.protocolText)
                    detailRow(label: "Stream", value: model.streamText)
                    detailRow(label: "First Byte", value: model.firstByteText)
                    detailRow(label: "Tokens", value: model.tokenText)
                    detailRow(label: "Error Stage", value: model.errorStageText)
                    detailRow(label: "Error Type", value: model.errorTypeText)
                    detailRow(label: "Error", value: model.errorDetailText)

                    if let usageText = model.usageText, !usageText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Usage JSON")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                            Text(usageText)
                                .font(.caption.monospaced())
                                .foregroundStyle(DesignTokens.textPrimary)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(DesignTokens.surfacePrimary.opacity(0.82))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(DesignTokens.borderSubtle.opacity(0.6), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(model.isFailure ? DesignTokens.surfacePrimary.opacity(0.96) : DesignTokens.surfacePrimary.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorderColor(forFailure: model.isFailure), lineWidth: model.isFailure ? 1.4 : 1)
        )
    }

    private func detailRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 84, alignment: .leading)

            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func semanticColor(forFailure: Bool, statusText: String) -> DesignTokens.SemanticColor {
        if forFailure {
            return statusText.hasPrefix("4") ? DesignTokens.statusColors.warning : DesignTokens.statusColors.error
        }
        return DesignTokens.statusColors.running
    }

    private func cardBorderColor(forFailure: Bool) -> Color {
        forFailure ? DesignTokens.statusColors.error.fill.opacity(0.55) : DesignTokens.borderSubtle.opacity(0.9)
    }
}
