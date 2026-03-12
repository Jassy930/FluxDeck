import Foundation
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

struct LogDetailItem: Equatable {
    let label: String
    let value: String
    let monospaced: Bool

    init(label: String, value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
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
    let displayTimeText: String
    let protocolText: String
    let streamText: String
    let firstByteText: String
    let tokenText: String
    let secondaryMetaText: String
    let metaBadges: [String]
    let errorStageText: String
    let errorTypeText: String
    let errorDetailText: String
    let usageText: String?
    let executionDetails: [LogDetailItem]
    let diagnosticsDetails: [LogDetailItem]
    let isFailure: Bool

    static func make(log: AdminLog) -> LogStreamCardModel {
        let routeText = "\(log.gatewayID) -> \(log.providerID)"
        let modelText = log.modelDisplayText
        let summaryText = log.errorSummaryText != "-" ? log.errorSummaryText : modelText
        let protocolText = "\(log.inboundProtocol ?? "-") -> \(log.upstreamProtocol ?? "-")"
        let streamText = log.stream ? "Streaming" : "Non-stream"
        let firstByteText = log.firstByteMs.map { "\($0) ms" } ?? "-"
        let tokenText = log.tokenBreakdownText
        let compactTokenText = compactTokenSummary(log: log)
        let displayTimeText = compactDisplayTime(log.createdAt)
        let usageText = nonEmpty(log.usageJSON)

        let executionDetails = [
            LogDetailItem(label: "Request ID", value: log.requestID, monospaced: true),
            LogDetailItem(label: "Protocol", value: protocolText),
            LogDetailItem(label: "Stream", value: streamText),
            LogDetailItem(label: "First Byte", value: firstByteText)
        ]

        let diagnosticsDetails = [
            LogDetailItem(label: "Tokens", value: tokenText),
            LogDetailItem(label: "Error Stage", value: log.errorStage ?? "-"),
            LogDetailItem(label: "Error Type", value: log.errorType ?? "-"),
            LogDetailItem(label: "Error", value: log.error ?? "-")
        ]

        return LogStreamCardModel(
            requestID: log.requestID,
            routeText: routeText,
            modelText: modelText,
            summaryText: summaryText,
            statusText: "\(log.statusCode)",
            latencyText: "\(log.latencyMs) ms",
            createdAtText: log.createdAt,
            displayTimeText: displayTimeText,
            protocolText: protocolText,
            streamText: streamText,
            firstByteText: firstByteText,
            tokenText: tokenText,
            secondaryMetaText: compactTokenText,
            metaBadges: ["\(log.latencyMs) ms", displayTimeText, protocolText, streamText],
            errorStageText: log.errorStage ?? "-",
            errorTypeText: log.errorType ?? "-",
            errorDetailText: log.error ?? "-",
            usageText: usageText,
            executionDetails: executionDetails,
            diagnosticsDetails: diagnosticsDetails,
            isFailure: log.statusCode >= 400 || log.error != nil
        )
    }

    private static func compactTokenSummary(log: AdminLog) -> String {
        var parts: [String] = []

        if let inputTokens = log.inputTokens {
            parts.append("\(shortMetric(inputTokens)) in")
        }
        if let outputTokens = log.outputTokens {
            parts.append("\(shortMetric(outputTokens)) out")
        }
        if let cachedTokens = log.cachedTokens {
            parts.append("\(shortMetric(cachedTokens)) c")
        }
        if parts.isEmpty, let totalTokens = log.totalTokens {
            parts.append("\(shortMetric(totalTokens)) total")
        }

        return parts.isEmpty ? "Tok -" : "Tok " + parts.joined(separator: " / ")
    }

    private static func shortMetric(_ value: Int) -> String {
        guard value >= 1000 else {
            return "\(value)"
        }

        let abbreviated = (Double(value) / 100).rounded() / 10
        let text = abbreviated.rounded(.towardZero) == abbreviated ? String(format: "%.0f", abbreviated) : String(format: "%.1f", abbreviated)
        return "\(text)k"
    }

    private static func compactDisplayTime(_ value: String) -> String {
        if let date = iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value) {
            return clockFormatter.string(from: date)
        }
        return value
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
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

                requestStreamPanel
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                panelHeader("Log Filters")
                Spacer()
                compactMetaTag(
                    text: hasMore ? "Loaded \(logs.count) requests" : "Loaded \(logs.count)",
                    tint: DesignTokens.statusColors.running.fill.opacity(0.24)
                )
                if hasMore {
                    compactMetaTag(text: "More available")
                }
            }

            ViewThatFits(in: .horizontal) {
                toolbarControlsRow
                toolbarControlsFallback
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.surfaceSecondary.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.borderSubtle.opacity(0.7), lineWidth: 1)
        )
    }

    private var requestStreamPanel: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader("Request Stream")

                if isLoading && logs.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else if logs.isEmpty {
                    Text("No request logs match current filters.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(logs) { log in
                                let model = LogStreamCardModel.make(log: log)
                                logCard(
                                    model: model,
                                    isExpanded: expansionState.expandedRequestID == log.requestID
                                ) {
                                    expansionState.toggle(requestID: log.requestID)
                                }
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
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DesignTokens.surfacePrimary.opacity(0.86))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DesignTokens.borderSubtle.opacity(0.55), lineWidth: 1)
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
    }

    private func logCard(model: LogStreamCardModel, isExpanded: Bool, onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryHeader(model: model, isExpanded: isExpanded, onToggle: onToggle)

            if isExpanded {
                Divider()
                    .overlay(DesignTokens.borderSubtle.opacity(0.75))

                VStack(alignment: .leading, spacing: 12) {
                    detailSection(title: "Execution", items: model.executionDetails)
                    detailSection(title: "Diagnostics", items: model.diagnosticsDetails)

                    if let usageText = model.usageText {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Usage JSON")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.textSecondary)

                            Text(usageText)
                                .font(.caption.monospaced())
                                .foregroundStyle(DesignTokens.textPrimary)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DesignTokens.surfacePrimary.opacity(0.84))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DesignTokens.borderSubtle.opacity(0.55), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isExpanded ? DesignTokens.surfacePrimary.opacity(0.94) : DesignTokens.surfacePrimary.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorderColor(forFailure: model.isFailure), lineWidth: model.isFailure ? 1.2 : 1)
        )
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(model.isFailure ? DesignTokens.statusColors.error.fill.opacity(0.82) : DesignTokens.borderSubtle.opacity(0.42))
                .frame(width: model.isFailure ? 3 : 1.5)
                .padding(.vertical, 8)
                .padding(.leading, 4)
        }
    }

    private var toolbarControlsRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            compactMenuPicker(title: "Gateway", selection: $selectedGateway, options: gatewayOptions)
            compactMenuPicker(title: "Provider", selection: $selectedProvider, options: providerOptions)
            compactMenuPicker(title: "Status", selection: $selectedStatus, options: statusOptions)

            Toggle("Only Errors", isOn: $errorsOnly)
                .toggleStyle(.switch)
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.bottom, 6)

            Spacer(minLength: 12)

            clearFiltersButton
                .padding(.bottom, 4)
        }
    }

    private var toolbarControlsFallback: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                compactMenuPicker(title: "Gateway", selection: $selectedGateway, options: gatewayOptions)
                compactMenuPicker(title: "Provider", selection: $selectedProvider, options: providerOptions)
            }

            HStack(alignment: .bottom, spacing: 10) {
                compactMenuPicker(title: "Status", selection: $selectedStatus, options: statusOptions)

                Toggle("Only Errors", isOn: $errorsOnly)
                    .toggleStyle(.switch)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.bottom, 6)

                Spacer(minLength: 12)

                clearFiltersButton
                    .padding(.bottom, 4)
            }
        }
    }

    private var clearFiltersButton: some View {
        Button("Clear Filters", action: onClearFilters)
            .buttonStyle(.plain)
            .focusable(false)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.88))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DesignTokens.borderSubtle.opacity(0.55), lineWidth: 1)
            )
    }

    private func summaryHeader(model: LogStreamCardModel, isExpanded: Bool, onToggle: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            compactStatusPill(model.statusText, semanticColor: semanticColor(forFailure: model.isFailure, statusText: model.statusText))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.routeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)

                    Text(model.summaryText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(model.isFailure ? DesignTokens.statusColors.error.fill : DesignTokens.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(2)

                    if model.summaryText != model.modelText {
                        Text(model.modelText)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }

                ViewThatFits(in: .horizontal) {
                    compactMetaRow(model: model)
                    compactMetaFallback(model: model)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    private func compactMetaRow(model: LogStreamCardModel) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(model.secondaryMetaText)
                .font(.caption2.monospaced())
                .foregroundStyle(DesignTokens.textPrimary.opacity(0.94))
                .lineLimit(1)
                .layoutPriority(2)

            ForEach(model.metaBadges, id: \.self) { badge in
                compactMetaTag(text: badge, tint: badgeTint(for: badge, isFailure: model.isFailure))
            }
        }
    }

    private func compactMetaFallback(model: LogStreamCardModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.secondaryMetaText)
                .font(.caption2.monospaced())
                .foregroundStyle(DesignTokens.textPrimary.opacity(0.94))
                .lineLimit(1)

            HStack(spacing: 8) {
                compactMetaTag(text: model.metaBadges[0], tint: badgeTint(for: model.metaBadges[0], isFailure: model.isFailure))
                compactMetaTag(text: model.metaBadges[1], tint: badgeTint(for: model.metaBadges[1], isFailure: model.isFailure))
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                compactMetaTag(text: model.metaBadges[2], tint: badgeTint(for: model.metaBadges[2], isFailure: model.isFailure))
                compactMetaTag(text: model.metaBadges[3], tint: badgeTint(for: model.metaBadges[3], isFailure: model.isFailure))
                Spacer(minLength: 0)
            }
        }
    }

    private func panelHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func compactMenuPicker(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DesignTokens.textSecondary)

            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DesignTokens.borderSubtle.opacity(0.55), lineWidth: 1)
            )
        }
        .frame(minWidth: 132)
    }

    private func compactMetaTag(text: String, tint: Color = DesignTokens.borderSubtle.opacity(0.34)) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(DesignTokens.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
    }

    private func compactStatusPill(_ text: String, semanticColor: DesignTokens.SemanticColor) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(semanticColor.fill)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(DesignTokens.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(semanticColor.glow)
        .overlay(
            Capsule()
                .stroke(semanticColor.fill.opacity(0.35), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private func detailSection(title: String, items: [LogDetailItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.textSecondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 150), spacing: 10, alignment: .leading),
                    GridItem(.flexible(minimum: 150), spacing: 10, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(items, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignTokens.textSecondary)

                        Text(item.value)
                            .font(item.monospaced ? .caption.monospaced() : .caption.weight(.medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignTokens.surfacePrimary.opacity(0.78))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DesignTokens.borderSubtle.opacity(0.45), lineWidth: 1)
                    )
                }
            }
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

    private func badgeTint(for badge: String, isFailure: Bool) -> Color {
        if badge == "Streaming" {
            return DesignTokens.statusColors.running.glow
        }
        if badge == "Non-stream" {
            return DesignTokens.borderSubtle.opacity(0.32)
        }
        if badge.hasSuffix(" ms") {
            return isFailure ? DesignTokens.statusColors.error.glow : DesignTokens.borderSubtle.opacity(0.34)
        }
        if badge.contains("->") {
            return DesignTokens.borderSubtle.opacity(0.28)
        }
        return DesignTokens.borderSubtle.opacity(0.34)
    }
}
