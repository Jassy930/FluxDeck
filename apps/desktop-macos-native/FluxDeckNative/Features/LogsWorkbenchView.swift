import SwiftUI

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

    @State private var selectedRequestID: String?

    private var selectedLog: AdminLog? {
        if let selectedRequestID {
            return logs.first(where: { $0.requestID == selectedRequestID })
        }
        return logs.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                if let error {
                    SurfaceCard {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.statusColors.error.fill)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    SurfaceCard(title: "Requests") {
                        if isLoading && logs.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                        } else if logs.isEmpty {
                            Text("No request logs match current filters.")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(logs) { log in
                                        Button {
                                            selectedRequestID = log.requestID
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(log.requestID)
                                                        .font(.caption.monospaced())
                                                        .foregroundStyle(DesignTokens.textPrimary)
                                                    Text("\(log.gatewayID) → \(log.providerID)")
                                                        .font(.caption2)
                                                        .foregroundStyle(DesignTokens.textSecondary)
                                                }
                                                Spacer()
                                                Text("\(log.statusCode)")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(statusColor(for: log.statusCode))
                                            }
                                            .padding(.horizontal, 2)
                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
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
                    .frame(maxWidth: .infinity)

                    SurfaceCard(title: "Details") {
                        if let selectedLog {
                            let detail = LogDetailCardModel.make(log: selectedLog)
                            VStack(alignment: .leading, spacing: 10) {
                                detailRow(label: "Request", value: detail.requestID)
                                detailRow(label: "Route", value: detail.routeText)
                                detailRow(label: "Model", value: detail.modelText)
                                detailRow(label: "Status", value: detail.statusText)
                                detailRow(label: "Latency", value: detail.latencyText)
                                detailRow(label: "Error", value: detail.errorText)
                                detailRow(label: "Created", value: detail.createdAtText)
                            }
                        } else {
                            Text("Select a request to inspect details.")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .onChange(of: logs.map(\.requestID)) { ids in
            if let selectedRequestID, !ids.contains(selectedRequestID) {
                self.selectedRequestID = ids.first
            } else if self.selectedRequestID == nil {
                self.selectedRequestID = ids.first
            }
        }
        .onAppear {
            selectedRequestID = selectedRequestID ?? logs.first?.requestID
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }

    private func statusColor(for statusCode: Int) -> Color {
        switch statusCode {
        case 200..<300:
            return DesignTokens.statusColors.running.fill
        case 400..<500:
            return DesignTokens.statusColors.warning.fill
        case 500..<600:
            return DesignTokens.statusColors.error.fill
        default:
            return DesignTokens.textSecondary
        }
    }
}
