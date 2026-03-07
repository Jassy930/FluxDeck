import Foundation

struct OverviewDashboardModel: Equatable {
    struct RunningStatus: Equatable {
        let connectionCountText: String
        let providerCountText: String
        let runningGatewayCountText: String
        let errorGatewayCountText: String
    }

    struct NetworkStatus: Equatable {
        let internetLatencyText: String
        let adminEndpointText: String
        let gatewayStatusText: String
    }

    struct TrafficSummary: Equatable {
        let totalRequestsText: String
        let successCountText: String
        let errorCountText: String
    }

    let runningStatus: RunningStatus
    let networkStatus: NetworkStatus
    let trafficSummary: TrafficSummary

    static func make(
        providers: [AdminProvider],
        gateways: [AdminGateway],
        logs: [AdminLog]
    ) -> OverviewDashboardModel {
        let runningGatewayCount = gateways.filter { runtimeCategory(for: $0) == .running }.count
        let errorGatewayCount = gateways.filter { runtimeCategory(for: $0) == .error }.count
        let averageLatency = logs.isEmpty ? 0 : logs.map(\.latencyMs).reduce(0, +) / logs.count
        let successCount = logs.filter { (200..<400).contains($0.statusCode) && $0.error == nil }.count
        let errorCount = logs.count - successCount
        let adminEndpointText = gateways.first.map { "\($0.listenHost):\($0.listenPort)" } ?? "No gateway"

        return OverviewDashboardModel(
            runningStatus: RunningStatus(
                connectionCountText: "\(logs.count)",
                providerCountText: "\(providers.count)",
                runningGatewayCountText: "\(runningGatewayCount)",
                errorGatewayCountText: "\(errorGatewayCount)"
            ),
            networkStatus: NetworkStatus(
                internetLatencyText: "\(averageLatency) ms",
                adminEndpointText: adminEndpointText,
                gatewayStatusText: runningGatewayCount > 0 ? "Healthy" : "Idle"
            ),
            trafficSummary: TrafficSummary(
                totalRequestsText: "\(logs.count)",
                successCountText: "\(successCount)",
                errorCountText: "\(errorCount)"
            )
        )
    }
}
