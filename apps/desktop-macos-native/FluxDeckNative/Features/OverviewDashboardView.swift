import SwiftUI

struct OverviewDashboardView: View {
    @Environment(\.locale) private var locale

    let model: OverviewDashboardModel
    let isLoading: Bool
    let logs: [AdminLog]
    let onOpenAllLogs: () -> Void
    let onDrillDownLog: (AdminLog) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SurfaceCard(title: L10n.string("overview.section.running_status", locale: locale)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                StatusPill(
                                    text: L10n.formatted("overview.status.gateways", locale: locale, Int64(model.runningStatus.runningGatewayCount)),
                                    semanticColor: DesignTokens.statusColors.running
                                )
                                StatusPill(
                                    text: L10n.formatted("overview.status.errors", locale: locale, Int64(model.runningStatus.errorGatewayCount)),
                                    semanticColor: model.runningStatus.errorGatewayCount == 0 ? DesignTokens.statusColors.inactive : DesignTokens.statusColors.error
                                )
                            }

                            overviewMetricRow(label: L10n.string("overview.metric.connections", locale: locale), value: "\(model.runningStatus.connectionCount)")
                            overviewMetricRow(label: L10n.string("overview.metric.providers", locale: locale), value: "\(model.runningStatus.providerCount)")
                        }
                    }

                    SurfaceCard(title: L10n.string("overview.section.network_status", locale: locale)) {
                        VStack(alignment: .leading, spacing: 12) {
                            StatusPill(
                                text: L10n.overviewGatewayStatus(model.networkStatus.gatewayStatus, locale: locale),
                                semanticColor: model.networkStatus.gatewayStatus == .healthy ? DesignTokens.statusColors.running : DesignTokens.statusColors.warning
                            )
                            overviewMetricRow(label: L10n.string("overview.metric.internet", locale: locale), value: L10n.durationMilliseconds(model.networkStatus.internetLatencyMs, locale: locale))
                            overviewMetricRow(label: L10n.string("overview.metric.gateway", locale: locale), value: model.networkStatus.adminEndpointText)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    SurfaceCard(title: L10n.string("overview.section.traffic_summary", locale: locale)) {
                        VStack(alignment: .leading, spacing: 12) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                overviewMetricTile(label: L10n.string("overview.metric.total_requests", locale: locale), value: "\(model.trafficSummary.totalRequests)")
                                overviewMetricTile(label: L10n.string("overview.metric.successful", locale: locale), value: "\(model.trafficSummary.successCount)")
                                overviewMetricTile(label: L10n.string("overview.metric.errors", locale: locale), value: "\(model.trafficSummary.errorCount)")
                                overviewMetricTile(label: L10n.string("overview.metric.gateways", locale: locale), value: "\(model.runningStatus.runningGatewayCount)")
                            }
                        }
                    }
                    .frame(width: 432)

                    SurfaceCard(title: L10n.string("overview.section.recent_requests", locale: locale)) {
                        if isLoading && logs.isEmpty {
                            Text(L10n.string("overview.state.loading", locale: locale))
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else if logs.isEmpty {
                            Text(L10n.string("overview.state.empty", locale: locale))
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

                                            Text(L10n.durationMilliseconds(log.latencyMs, locale: locale))
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(DesignTokens.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                }

                                Button(L10n.string("overview.logs.open_all", locale: locale), action: onOpenAllLogs)
                                    .focusable(false)
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
