import SwiftUI

struct OverviewDashboardView: View {
    let model: OverviewDashboardModel
    let isLoading: Bool
    let logs: [AdminLog]
    let onOpenAllLogs: () -> Void
    let onDrillDownLog: (AdminLog) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SurfaceCard(title: "Running Status") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                StatusPill(text: "Gateways \(model.runningStatus.runningGatewayCountText)", semanticColor: DesignTokens.statusColors.running)
                                StatusPill(text: "Errors \(model.runningStatus.errorGatewayCountText)", semanticColor: model.runningStatus.errorGatewayCountText == "0" ? DesignTokens.statusColors.inactive : DesignTokens.statusColors.error)
                            }

                            overviewMetricRow(label: "Connections", value: model.runningStatus.connectionCountText)
                            overviewMetricRow(label: "Providers", value: model.runningStatus.providerCountText)
                        }
                    }

                    SurfaceCard(title: "Network Status") {
                        VStack(alignment: .leading, spacing: 12) {
                            StatusPill(text: model.networkStatus.gatewayStatusText, semanticColor: model.networkStatus.gatewayStatusText == "Healthy" ? DesignTokens.statusColors.running : DesignTokens.statusColors.warning)
                            overviewMetricRow(label: "Internet", value: model.networkStatus.internetLatencyText)
                            overviewMetricRow(label: "Gateway", value: model.networkStatus.adminEndpointText)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    SurfaceCard(title: "Traffic Summary") {
                        VStack(alignment: .leading, spacing: 12) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                overviewMetricTile(label: "Total Requests", value: model.trafficSummary.totalRequestsText)
                                overviewMetricTile(label: "Successful", value: model.trafficSummary.successCountText)
                                overviewMetricTile(label: "Errors", value: model.trafficSummary.errorCountText)
                                overviewMetricTile(label: "Gateways", value: model.runningStatus.runningGatewayCountText)
                            }
                        }
                    }
                    .frame(width: 432)

                    SurfaceCard(title: "Recent Requests") {
                        if isLoading && logs.isEmpty {
                            Text("Loading overview...")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else if logs.isEmpty {
                            Text("No recent traffic yet.")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(logs.prefix(4)) { log in
                                    Button {
                                        onDrillDownLog(log)
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(log.gatewayID)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(DesignTokens.textPrimary)
                                                Text(log.providerID)
                                                    .font(.caption)
                                                    .foregroundStyle(DesignTokens.textSecondary)
                                            }

                                            Spacer(minLength: 12)

                                            Text("\(log.latencyMs) ms")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(DesignTokens.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button("Open All Logs", action: onOpenAllLogs)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(DesignTokens.textPrimary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
    }

    private func overviewMetricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }

    private func overviewMetricTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
