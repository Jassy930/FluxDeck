import Foundation

enum TrafficAlertLevel: String, Equatable {
    case info
    case warning
    case error
}

struct TrafficAlert: Equatable {
    let level: TrafficAlertLevel
    let title: String
    let detail: String
}

struct TrafficBreakdownRow: Equatable {
    let title: String
    let requestCountText: String
    let latencyText: String
    let errorText: String
    let tokenText: String
}

struct TrafficKpiStripItem: Equatable {
    let title: String
    let value: String
    let detailRows: [TrafficKpiSupplementRow]
}

struct TrafficKpiSupplementRow: Equatable {
    let label: String
    let value: String
}

struct TrafficAnalyticsModel {
    let totalRequests: Int
    let errorCount: Int
    let successCount: Int
    let averageLatencyText: String
    let requestsPerMinuteText: String
    let successRateText: String
    let totalTokensText: String
    let topGatewayID: String
    let topProviderID: String
    let topModelName: String
    let gatewayBreakdown: [TrafficBreakdownRow]
    let providerBreakdown: [TrafficBreakdownRow]
    let modelBreakdown: [TrafficBreakdownRow]
    let trendPoints: [AdminStatsTrendPoint]
    let alerts: [TrafficAlert]
    let selectedPeriod: String
    let hasData: Bool
    let gatewayStatsForKpi: [AdminGatewayStats]
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCachedTokens: Int

    var compactGatewayBreakdown: [TrafficBreakdownRow] {
        Array(gatewayBreakdown.prefix(Self.compactBreakdownLimit))
    }

    var compactProviderBreakdown: [TrafficBreakdownRow] {
        Array(providerBreakdown.prefix(Self.compactBreakdownLimit))
    }

    var compactModelBreakdown: [TrafficBreakdownRow] {
        Array(modelBreakdown.prefix(Self.compactBreakdownLimit))
    }

    var kpiStripItems: [TrafficKpiStripItem] {
        let topGatewayStats = Array(
            gatewayStatsForKpi
                .sorted { lhs, rhs in
                    if lhs.requestCount == rhs.requestCount {
                        return lhs.gatewayID < rhs.gatewayID
                    }
                    return lhs.requestCount > rhs.requestCount
                }
                .prefix(Self.kpiGatewayLimit)
        )

        return [
            TrafficKpiStripItem(
                title: "Requests / min",
                value: requestsPerMinuteText,
                detailRows: topGatewayStats.map {
                    TrafficKpiSupplementRow(
                        label: $0.gatewayID,
                        value: "\(formatDecimal(requestsPerMinute(for: $0.requestCount, selectedPeriod: selectedPeriod))) rpm"
                    )
                }
            ),
            TrafficKpiStripItem(
                title: "Success Rate",
                value: successRateText,
                detailRows: topGatewayStats.map {
                    TrafficKpiSupplementRow(
                        label: $0.gatewayID,
                        value: "\($0.successCount) ok / \($0.errorCount) err"
                    )
                }
            ),
            TrafficKpiStripItem(
                title: "Avg Latency",
                value: averageLatencyText,
                detailRows: topGatewayStats.map {
                    TrafficKpiSupplementRow(
                        label: $0.gatewayID,
                        value: "\($0.avgLatency) ms"
                    )
                }
            ),
            TrafficKpiStripItem(
                title: "Total Tokens",
                value: totalTokensText,
                detailRows: [
                    TrafficKpiSupplementRow(label: "Input", value: formatInteger(totalInputTokens)),
                    TrafficKpiSupplementRow(label: "Output", value: formatInteger(totalOutputTokens)),
                    TrafficKpiSupplementRow(label: "Cached", value: formatInteger(totalCachedTokens))
                ]
            )
        ]
    }

    static func make(logs: [AdminLog]) -> TrafficAnalyticsModel {
        let totalRequests = logs.count
        let errorCount = logs.filter { $0.statusCode >= 400 || $0.error != nil }.count
        let successCount = max(totalRequests - errorCount, 0)
        let averageLatency = totalRequests > 0 ? logs.map(\.latencyMs).reduce(0, +) / totalRequests : 0

        let topGatewayID = groupedMostFrequentValue(logs.map(\.gatewayID)) ?? "No gateway"
        let topProviderID = groupedMostFrequentValue(logs.map(\.providerID)) ?? "No provider"

        return TrafficAnalyticsModel(
            totalRequests: totalRequests,
            errorCount: errorCount,
            successCount: successCount,
            averageLatencyText: "\(averageLatency) ms",
            requestsPerMinuteText: "0.0",
            successRateText: totalRequests > 0 ? formatPercent(Double(successCount) / Double(totalRequests) * 100.0) : "0.0%",
            totalTokensText: "0",
            topGatewayID: topGatewayID,
            topProviderID: topProviderID,
            topModelName: groupedMostFrequentValue(logs.compactMap(\.model)) ?? "No model",
            gatewayBreakdown: [],
            providerBreakdown: [],
            modelBreakdown: [],
            trendPoints: [],
            alerts: [],
            selectedPeriod: "logs",
            hasData: totalRequests > 0,
            gatewayStatsForKpi: [],
            totalInputTokens: logs.compactMap(\.inputTokens).reduce(0, +),
            totalOutputTokens: logs.compactMap(\.outputTokens).reduce(0, +),
            totalCachedTokens: logs.compactMap(\.cachedTokens).reduce(0, +)
        )
    }

    static func make(
        overview: AdminStatsOverview?,
        trend: AdminStatsTrend?,
        selectedPeriod: String
    ) -> TrafficAnalyticsModel {
        guard let overview else {
            return TrafficAnalyticsModel(
                totalRequests: 0,
                errorCount: 0,
                successCount: 0,
                averageLatencyText: "0 ms",
                requestsPerMinuteText: "0.0",
                successRateText: "0.0%",
                totalTokensText: "0",
                topGatewayID: "No gateway",
                topProviderID: "No provider",
                topModelName: "No model",
                gatewayBreakdown: [],
                providerBreakdown: [],
                modelBreakdown: [],
                trendPoints: trend?.data ?? [],
                alerts: trend?.data.isEmpty == false ? [TrafficAlert(level: .info, title: "No overview data", detail: "Trend points are available but overview statistics are missing.")] : [],
                selectedPeriod: selectedPeriod,
                hasData: false,
                gatewayStatsForKpi: [],
                totalInputTokens: summedInputTokens(from: trend),
                totalOutputTokens: summedOutputTokens(from: trend),
                totalCachedTokens: summedCachedTokens(from: trend)
            )
        }

        let gatewayBreakdown = overview.byGateway.map {
            TrafficBreakdownRow(
                title: $0.gatewayID,
                requestCountText: "\($0.requestCount) req",
                latencyText: "\($0.avgLatency) ms",
                errorText: "\($0.errorCount) errors",
                tokenText: formatInteger($0.totalTokens)
            )
        }
        let providerBreakdown = overview.byProvider.map {
            TrafficBreakdownRow(
                title: $0.providerID,
                requestCountText: "\($0.requestCount) req",
                latencyText: "\($0.avgLatency) ms",
                errorText: "\($0.errorCount) errors",
                tokenText: formatInteger($0.totalTokens)
            )
        }
        let modelBreakdown = overview.byModel.map {
            TrafficBreakdownRow(
                title: $0.model,
                requestCountText: "\($0.requestCount) req",
                latencyText: "\($0.avgLatency) ms",
                errorText: "\($0.errorCount) errors",
                tokenText: formatInteger($0.totalTokens)
            )
        }

        return TrafficAnalyticsModel(
            totalRequests: overview.totalRequests,
            errorCount: overview.errorRequests,
            successCount: overview.successfulRequests,
            averageLatencyText: "\(averageLatency(from: overview.byGateway, fallback: trend?.data)) ms",
            requestsPerMinuteText: formatDecimal(overview.requestsPerMinute),
            successRateText: formatPercent(overview.successRate),
            totalTokensText: formatInteger(overview.totalTokens),
            topGatewayID: overview.byGateway.first?.gatewayID ?? "No gateway",
            topProviderID: overview.byProvider.first?.providerID ?? "No provider",
            topModelName: overview.byModel.first?.model ?? "No model",
            gatewayBreakdown: gatewayBreakdown,
            providerBreakdown: providerBreakdown,
            modelBreakdown: modelBreakdown,
            trendPoints: trend?.data ?? [],
            alerts: buildAlerts(overview: overview, trend: trend),
            selectedPeriod: selectedPeriod,
            hasData: overview.totalRequests > 0,
            gatewayStatsForKpi: overview.byGateway,
            totalInputTokens: summedInputTokens(from: trend),
            totalOutputTokens: summedOutputTokens(from: trend),
            totalCachedTokens: overview.cachedTokens
        )
    }

    private static let compactBreakdownLimit = 3
    private static let kpiGatewayLimit = 2
}

struct ConnectionsModel {
    let activeGatewayIDs: [String]
    let activeProviderIDs: [String]
    let activeModels: [String]

    static func make(logs: [AdminLog]) -> ConnectionsModel {
        ConnectionsModel(
            activeGatewayIDs: Array(Set(logs.map(\.gatewayID))).sorted(),
            activeProviderIDs: Array(Set(logs.map(\.providerID))).sorted(),
            activeModels: Array(Set(logs.compactMap(\.model))).sorted()
        )
    }
}

private func groupedMostFrequentValue(_ values: [String]) -> String? {
    Dictionary(grouping: values, by: { $0 })
        .max { lhs, rhs in
            if lhs.value.count == rhs.value.count {
                return lhs.key > rhs.key
            }
            return lhs.value.count < rhs.value.count
        }?
        .key
}

private func averageLatency(from gatewayStats: [AdminGatewayStats], fallback trend: [AdminStatsTrendPoint]?) -> Int {
    if !gatewayStats.isEmpty {
        return gatewayStats.map(\.avgLatency).reduce(0, +) / gatewayStats.count
    }
    guard let trend, !trend.isEmpty else {
        return 0
    }
    return trend.map(\.avgLatency).reduce(0, +) / trend.count
}

private func buildAlerts(overview: AdminStatsOverview, trend: AdminStatsTrend?) -> [TrafficAlert] {
    var alerts: [TrafficAlert] = []

    if overview.errorRequests > 0 {
        alerts.append(
            TrafficAlert(
                level: .error,
                title: "Request errors detected",
                detail: "\(overview.errorRequests) requests failed in the selected period."
            )
        )
    }

    if overview.byGateway.contains(where: { $0.avgLatency >= 1000 }) {
        alerts.append(
            TrafficAlert(
                level: .warning,
                title: "Latency elevated",
                detail: "One or more gateways are averaging above 1000 ms."
            )
        )
    }

    if overview.totalRequests == 0 {
        alerts.append(
            TrafficAlert(
                level: .info,
                title: "No traffic yet",
                detail: "No requests were recorded in the selected period."
            )
        )
    } else if let trend, trend.data.last?.requestCount == 0 {
        alerts.append(
            TrafficAlert(
                level: .info,
                title: "Latest bucket is idle",
                detail: "The most recent trend bucket shows no traffic."
            )
        )
    }

    return alerts
}

private func formatDecimal(_ value: Double) -> String {
    String(format: "%.1f", value)
}

private func formatPercent(_ value: Double) -> String {
    "\(formatDecimal(value))%"
}

private func formatInteger(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

private func periodMinutes(for selectedPeriod: String) -> Double {
    switch selectedPeriod {
    case "1h":
        return 60
    case "6h":
        return 360
    case "24h":
        return 1_440
    default:
        return 60
    }
}

private func requestsPerMinute(for requestCount: Int, selectedPeriod: String) -> Double {
    let minutes = periodMinutes(for: selectedPeriod)
    guard minutes > 0 else {
        return 0
    }
    return Double(requestCount) / minutes
}

private func summedInputTokens(from trend: AdminStatsTrend?) -> Int {
    trend?.data.map(\.inputTokens).reduce(0, +) ?? 0
}

private func summedOutputTokens(from trend: AdminStatsTrend?) -> Int {
    trend?.data.map(\.outputTokens).reduce(0, +) ?? 0
}

private func summedCachedTokens(from trend: AdminStatsTrend?) -> Int {
    trend?.data.map(\.cachedTokens).reduce(0, +) ?? 0
}
