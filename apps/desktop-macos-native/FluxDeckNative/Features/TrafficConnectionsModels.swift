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

struct TrafficTokenTrendSeries: Equatable {
    let modelName: String
    let bucketValues: [Int]
    let totalTokens: Int
}

struct TrafficTokenTrendBucketRow: Equatable {
    let modelName: String
    let totalTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let requestCount: Int
    let errorCount: Int
}

struct TrafficTokenTrendBucket: Equatable {
    let timestamp: String
    let totalTokens: Int
    let errorCount: Int
    let rows: [TrafficTokenTrendBucketRow]
}

struct TrafficTrendSummaryItem: Equatable {
    let title: String
    let value: String
}

struct TrafficAnalyticsModel {
    let locale: Locale
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
    let tokenTrendSeries: [TrafficTokenTrendSeries]
    let tokenTrendBuckets: [TrafficTokenTrendBucket]
    let tokenTrendSummaryItems: [TrafficTrendSummaryItem]

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
                title: L10n.string("traffic.kpi.requests_per_min", locale: locale),
                value: requestsPerMinuteText,
                detailRows: topGatewayStats.map {
                    TrafficKpiSupplementRow(
                        label: $0.gatewayID,
                        value: L10n.formatted(
                            "traffic.kpi.rpm_value",
                            locale: locale,
                            formatDecimal(requestsPerMinute(for: $0.requestCount, selectedPeriod: selectedPeriod))
                        )
                    )
                }
            ),
            TrafficKpiStripItem(
                title: L10n.string("traffic.kpi.success_rate", locale: locale),
                value: successRateText,
                detailRows: topGatewayStats.map {
                    TrafficKpiSupplementRow(
                        label: $0.gatewayID,
                        value: L10n.formatted(
                            "traffic.kpi.success_detail",
                            locale: locale,
                            Int64($0.successCount),
                            Int64($0.errorCount)
                        )
                    )
                }
            ),
            TrafficKpiStripItem(
                title: L10n.string("traffic.kpi.avg_latency", locale: locale),
                value: averageLatencyText,
                detailRows: topGatewayStats.map {
                    TrafficKpiSupplementRow(
                        label: $0.gatewayID,
                        value: L10n.durationMilliseconds($0.avgLatency, locale: locale)
                    )
                }
            ),
            TrafficKpiStripItem(
                title: L10n.string("traffic.kpi.total_tokens", locale: locale),
                value: totalTokensText,
                detailRows: [
                    TrafficKpiSupplementRow(label: L10n.string("traffic.kpi.input", locale: locale), value: formatInteger(totalInputTokens)),
                    TrafficKpiSupplementRow(label: L10n.string("traffic.kpi.output", locale: locale), value: formatInteger(totalOutputTokens)),
                    TrafficKpiSupplementRow(label: L10n.string("traffic.kpi.cached", locale: locale), value: formatInteger(totalCachedTokens))
                ]
            )
        ]
    }

    static func make(logs: [AdminLog], locale: Locale = .autoupdatingCurrent) -> TrafficAnalyticsModel {
        let totalRequests = logs.count
        let errorCount = logs.filter { $0.statusCode >= 400 || $0.error != nil }.count
        let successCount = max(totalRequests - errorCount, 0)
        let averageLatency = totalRequests > 0 ? logs.map(\.latencyMs).reduce(0, +) / totalRequests : 0

        let topGatewayID = groupedMostFrequentValue(logs.map(\.gatewayID)) ?? L10n.string("traffic.routing.none.gateway", locale: locale)
        let topProviderID = groupedMostFrequentValue(logs.map(\.providerID)) ?? L10n.string("traffic.routing.none.provider", locale: locale)

        return TrafficAnalyticsModel(
            locale: locale,
            totalRequests: totalRequests,
            errorCount: errorCount,
            successCount: successCount,
            averageLatencyText: L10n.durationMilliseconds(averageLatency, locale: locale),
            requestsPerMinuteText: "0.0",
            successRateText: totalRequests > 0 ? formatPercent(Double(successCount) / Double(totalRequests) * 100.0) : "0.0%",
            totalTokensText: "0",
            topGatewayID: topGatewayID,
            topProviderID: topProviderID,
            topModelName: groupedMostFrequentValue(logs.compactMap(\.model)) ?? L10n.string("traffic.routing.none.model", locale: locale),
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
            totalCachedTokens: logs.compactMap(\.cachedTokens).reduce(0, +),
            tokenTrendSeries: [],
            tokenTrendBuckets: [],
            tokenTrendSummaryItems: defaultTokenTrendSummaryItems(locale: locale)
        )
    }

    static func make(
        overview: AdminStatsOverview?,
        trend: AdminStatsTrend?,
        selectedPeriod: String,
        locale: Locale = .autoupdatingCurrent
    ) -> TrafficAnalyticsModel {
        guard let overview else {
            let tokenTrend = buildTokenTrend(from: trend, locale: locale)
            return TrafficAnalyticsModel(
                locale: locale,
                totalRequests: 0,
                errorCount: 0,
                successCount: 0,
                averageLatencyText: L10n.durationMilliseconds(0, locale: locale),
                requestsPerMinuteText: "0.0",
                successRateText: "0.0%",
                totalTokensText: "0",
                topGatewayID: L10n.string("traffic.routing.none.gateway", locale: locale),
                topProviderID: L10n.string("traffic.routing.none.provider", locale: locale),
                topModelName: L10n.string("traffic.routing.none.model", locale: locale),
                gatewayBreakdown: [],
                providerBreakdown: [],
                modelBreakdown: [],
                trendPoints: trend?.data ?? [],
                alerts: trend?.data.isEmpty == false ? [
                    TrafficAlert(
                        level: .info,
                        title: L10n.string("traffic.alert.overview_missing.title", locale: locale),
                        detail: L10n.string("traffic.alert.overview_missing.detail", locale: locale)
                    )
                ] : [],
                selectedPeriod: selectedPeriod,
                hasData: false,
                gatewayStatsForKpi: [],
                totalInputTokens: summedInputTokens(from: trend),
                totalOutputTokens: summedOutputTokens(from: trend),
                totalCachedTokens: summedCachedTokens(from: trend),
                tokenTrendSeries: tokenTrend.series,
                tokenTrendBuckets: tokenTrend.buckets,
                tokenTrendSummaryItems: tokenTrend.summaryItems
            )
        }

        let gatewayBreakdown = overview.byGateway.map {
            TrafficBreakdownRow(
                title: $0.gatewayID,
                requestCountText: L10n.formatted("traffic.breakdown.requests_value", locale: locale, Int64($0.requestCount)),
                latencyText: L10n.durationMilliseconds($0.avgLatency, locale: locale),
                errorText: L10n.formatted("traffic.breakdown.errors_value", locale: locale, Int64($0.errorCount)),
                tokenText: formatInteger($0.totalTokens)
            )
        }
        let providerBreakdown = overview.byProvider.map {
            TrafficBreakdownRow(
                title: $0.providerID,
                requestCountText: L10n.formatted("traffic.breakdown.requests_value", locale: locale, Int64($0.requestCount)),
                latencyText: L10n.durationMilliseconds($0.avgLatency, locale: locale),
                errorText: L10n.formatted("traffic.breakdown.errors_value", locale: locale, Int64($0.errorCount)),
                tokenText: formatInteger($0.totalTokens)
            )
        }
        let modelBreakdown = overview.byModel.map {
            TrafficBreakdownRow(
                title: $0.model,
                requestCountText: L10n.formatted("traffic.breakdown.requests_value", locale: locale, Int64($0.requestCount)),
                latencyText: L10n.durationMilliseconds($0.avgLatency, locale: locale),
                errorText: L10n.formatted("traffic.breakdown.errors_value", locale: locale, Int64($0.errorCount)),
                tokenText: formatInteger($0.totalTokens)
            )
        }

        let tokenTrend = buildTokenTrend(from: trend, locale: locale)

        return TrafficAnalyticsModel(
            locale: locale,
            totalRequests: overview.totalRequests,
            errorCount: overview.errorRequests,
            successCount: overview.successfulRequests,
            averageLatencyText: L10n.durationMilliseconds(averageLatency(from: overview.byGateway, fallback: trend?.data), locale: locale),
            requestsPerMinuteText: formatDecimal(overview.requestsPerMinute),
            successRateText: formatPercent(overview.successRate),
            totalTokensText: formatInteger(overview.totalTokens),
            topGatewayID: overview.byGateway.first?.gatewayID ?? L10n.string("traffic.routing.none.gateway", locale: locale),
            topProviderID: overview.byProvider.first?.providerID ?? L10n.string("traffic.routing.none.provider", locale: locale),
            topModelName: overview.byModel.first?.model ?? L10n.string("traffic.routing.none.model", locale: locale),
            gatewayBreakdown: gatewayBreakdown,
            providerBreakdown: providerBreakdown,
            modelBreakdown: modelBreakdown,
            trendPoints: trend?.data ?? [],
            alerts: buildAlerts(overview: overview, trend: trend, locale: locale),
            selectedPeriod: selectedPeriod,
            hasData: overview.totalRequests > 0,
            gatewayStatsForKpi: overview.byGateway,
            totalInputTokens: summedInputTokens(from: trend),
            totalOutputTokens: summedOutputTokens(from: trend),
            totalCachedTokens: overview.cachedTokens,
            tokenTrendSeries: tokenTrend.series,
            tokenTrendBuckets: tokenTrend.buckets,
            tokenTrendSummaryItems: tokenTrend.summaryItems
        )
    }

    private static let compactBreakdownLimit = 3
    private static let kpiGatewayLimit = 2
    fileprivate static let tokenTrendModelLimit = 4
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

private func buildAlerts(overview: AdminStatsOverview, trend: AdminStatsTrend?, locale: Locale) -> [TrafficAlert] {
    var alerts: [TrafficAlert] = []

    if overview.errorRequests > 0 {
        alerts.append(
            TrafficAlert(
                level: .error,
                title: L10n.string("traffic.alert.request_errors.title", locale: locale),
                detail: L10n.formatted("traffic.alert.request_errors.detail", locale: locale, Int64(overview.errorRequests))
            )
        )
    }

    if overview.byGateway.contains(where: { $0.avgLatency >= 1000 }) {
        alerts.append(
            TrafficAlert(
                level: .warning,
                title: L10n.string("traffic.alert.latency_elevated.title", locale: locale),
                detail: L10n.string("traffic.alert.latency_elevated.detail", locale: locale)
            )
        )
    }

    if overview.totalRequests == 0 {
        alerts.append(
            TrafficAlert(
                level: .info,
                title: L10n.string("traffic.alert.no_traffic.title", locale: locale),
                detail: L10n.string("traffic.alert.no_traffic.detail", locale: locale)
            )
        )
    } else if let trend, trend.data.last?.requestCount == 0 {
        alerts.append(
            TrafficAlert(
                level: .info,
                title: L10n.string("traffic.alert.latest_bucket_idle.title", locale: locale),
                detail: L10n.string("traffic.alert.latest_bucket_idle.detail", locale: locale)
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

private func defaultTokenTrendSummaryItems(locale: Locale) -> [TrafficTrendSummaryItem] {
    [
        TrafficTrendSummaryItem(title: L10n.string("traffic.summary.peak_total_tokens", locale: locale), value: "0"),
        TrafficTrendSummaryItem(title: L10n.string("traffic.summary.top_model_share", locale: locale), value: L10n.string("traffic.summary.no_model", locale: locale)),
        TrafficTrendSummaryItem(title: L10n.string("traffic.summary.peak_bucket_errors", locale: locale), value: "0")
    ]
}

private func buildTokenTrend(
    from trend: AdminStatsTrend?,
    locale: Locale
) -> (
    series: [TrafficTokenTrendSeries],
    buckets: [TrafficTokenTrendBucket],
    summaryItems: [TrafficTrendSummaryItem]
) {
    guard let trend, !trend.data.isEmpty else {
        return ([], [], defaultTokenTrendSummaryItems(locale: locale))
    }

    let modelTotals = trend.data.reduce(into: [String: Int]()) { partialResult, point in
        for bucket in point.byModel {
            partialResult[bucket.model, default: 0] += bucket.totalTokens
        }
    }

    let topModelNames = modelTotals
        .sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        .prefix(TrafficAnalyticsModel.tokenTrendModelLimit)
        .map(\.key)

    let topModelNameSet = Set(topModelNames)
    let includesOther = modelTotals.keys.contains { !topModelNameSet.contains($0) }
    let otherTokenTrendLabel = L10n.string("traffic.label.other", locale: locale)
    let otherTokenTrendKey = "__other__"
    let seriesKeys = topModelNames + (includesOther ? [otherTokenTrendKey] : [])
    var seriesValues: [String: [Int]] = Dictionary(uniqueKeysWithValues: seriesKeys.map { ($0, [Int]()) })
    var buckets: [TrafficTokenTrendBucket] = []

    for point in trend.data {
        var aggregatedRows: [String: TrafficTokenTrendBucketRow] = [:]

        for bucket in point.byModel {
            let rowKey = topModelNameSet.contains(bucket.model) ? bucket.model : otherTokenTrendKey
            let displayName = tokenTrendDisplayName(
                for: rowKey,
                originalModelName: bucket.model,
                otherLabel: otherTokenTrendLabel,
                locale: locale
            )
            let existing = aggregatedRows[rowKey] ?? TrafficTokenTrendBucketRow(
                modelName: displayName,
                totalTokens: 0,
                inputTokens: 0,
                outputTokens: 0,
                cachedTokens: 0,
                requestCount: 0,
                errorCount: 0
            )
            aggregatedRows[rowKey] = TrafficTokenTrendBucketRow(
                modelName: displayName,
                totalTokens: existing.totalTokens + bucket.totalTokens,
                inputTokens: existing.inputTokens + bucket.inputTokens,
                outputTokens: existing.outputTokens + bucket.outputTokens,
                cachedTokens: existing.cachedTokens + bucket.cachedTokens,
                requestCount: existing.requestCount + bucket.requestCount,
                errorCount: existing.errorCount + bucket.errorCount
            )
        }

        for key in seriesKeys {
            seriesValues[key, default: []].append(aggregatedRows[key]?.totalTokens ?? 0)
        }

        let rows = aggregatedRows.values
            .filter { $0.totalTokens > 0 }
            .sorted { lhs, rhs in
                if lhs.totalTokens == rhs.totalTokens {
                    return lhs.modelName < rhs.modelName
                }
                return lhs.totalTokens > rhs.totalTokens
            }

        buckets.append(
            TrafficTokenTrendBucket(
                timestamp: point.timestamp,
                totalTokens: rows.map(\.totalTokens).reduce(0, +),
                errorCount: point.errorCount,
                rows: rows
            )
        )
    }

    let series = seriesKeys.map { key in
        let bucketValues = seriesValues[key] ?? []
        return TrafficTokenTrendSeries(
            modelName: tokenTrendDisplayName(for: key, originalModelName: key, otherLabel: otherTokenTrendLabel, locale: locale),
            bucketValues: bucketValues,
            totalTokens: bucketValues.reduce(0, +)
        )
    }

    let peakTotalTokens = buckets.map(\.totalTokens).max() ?? 0
    let peakBucketErrors = buckets.map(\.errorCount).max() ?? 0
    let overallTotalTokens = buckets.map(\.totalTokens).reduce(0, +)
    let topModelShareValue: String
    if let topModelName = topModelNames.first,
       let topModelTotal = modelTotals[topModelName],
       overallTotalTokens > 0 {
        topModelShareValue = "\(topModelName) \(formatPercent(Double(topModelTotal) / Double(overallTotalTokens) * 100.0))"
    } else {
        topModelShareValue = L10n.string("traffic.summary.no_model", locale: locale)
    }

    return (
        series,
        buckets,
        [
            TrafficTrendSummaryItem(title: L10n.string("traffic.summary.peak_total_tokens", locale: locale), value: formatInteger(peakTotalTokens)),
            TrafficTrendSummaryItem(title: L10n.string("traffic.summary.top_model_share", locale: locale), value: topModelShareValue),
            TrafficTrendSummaryItem(title: L10n.string("traffic.summary.peak_bucket_errors", locale: locale), value: String(peakBucketErrors))
        ]
    )
}

private func tokenTrendDisplayName(
    for key: String,
    originalModelName: String,
    otherLabel: String,
    locale: Locale
) -> String {
    if key == "__other__" {
        return otherLabel
    }
    if originalModelName == otherLabel {
        return L10n.string(L10n.trafficLabelOtherModel, locale: locale)
    }
    return originalModelName
}
