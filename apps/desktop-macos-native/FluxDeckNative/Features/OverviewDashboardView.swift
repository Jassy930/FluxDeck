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
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                StatusPill(text: "Gateways \(model.runningStatus.runningGatewayCountText)", semanticColor: DesignTokens.statusColors.running)
                                StatusPill(text: "Errors \(model.runningStatus.errorGatewayCountText)", semanticColor: model.runningStatus.errorGatewayCountText == "0" ? DesignTokens.statusColors.inactive : DesignTokens.statusColors.error)
                            }

                            overviewMetricRow(label: "Connections", value: model.runningStatus.connectionCountText)
                            overviewMetricRow(label: "Providers", value: model.runningStatus.providerCountText)
                        }
                    }

                    SurfaceCard(title: "Network Status") {
                        VStack(alignment: .leading, spacing: 14) {
                            StatusPill(text: model.networkStatus.gatewayStatusText, semanticColor: model.networkStatus.gatewayStatusText == "Healthy" ? DesignTokens.statusColors.running : DesignTokens.statusColors.warning)
                            overviewMetricRow(label: "Internet", value: model.networkStatus.internetLatencyText)
                            overviewMetricRow(label: "Gateway", value: model.networkStatus.adminEndpointText)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SurfaceCard(title: "Traffic Summary") {
                        VStack(alignment: .leading, spacing: 14) {
                            overviewMetricRow(label: "Total Requests", value: model.trafficSummary.totalRequestsText)
                            overviewMetricRow(label: "Successful", value: model.trafficSummary.successCountText)
                            overviewMetricRow(label: "Errors", value: model.trafficSummary.errorCountText)
                        }
                    }

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
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(log.gatewayID)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(DesignTokens.textPrimary)
                                                Text(log.providerID)
                                                    .font(.caption)
                                                    .foregroundStyle(DesignTokens.textSecondary)
                                            }

                                            Spacer()

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
                }
            }
            .padding(20)
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
}
