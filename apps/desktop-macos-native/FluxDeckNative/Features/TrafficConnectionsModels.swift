import Foundation

struct TrafficAnalyticsModel {
    let totalRequests: Int
    let errorCount: Int
    let successCount: Int
    let averageLatencyText: String
    let topGatewayID: String
    let topProviderID: String

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
            topGatewayID: topGatewayID,
            topProviderID: topProviderID
        )
    }
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
