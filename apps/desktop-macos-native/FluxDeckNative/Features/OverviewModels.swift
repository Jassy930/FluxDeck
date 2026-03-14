import Foundation

struct OverviewDashboardModel: Equatable {
    enum GatewayStatus: Equatable {
        case healthy
        case idle
    }

    struct RunningStatus: Equatable {
        let connectionCount: Int
        let providerCount: Int
        let runningGatewayCount: Int
        let errorGatewayCount: Int
    }

    struct NetworkStatus: Equatable {
        let internetLatencyMs: Int
        let adminEndpointText: String
        let gatewayStatus: GatewayStatus
    }

    struct TrafficSummary: Equatable {
        let totalRequests: Int
        let successCount: Int
        let errorCount: Int
    }

    let runningStatus: RunningStatus
    let networkStatus: NetworkStatus
    let trafficSummary: TrafficSummary

    static func make(
        providers: [AdminProvider],
        gateways: [AdminGateway],
        logs: [AdminLog],
        locale: Locale = Locale(identifier: "en")
    ) -> OverviewDashboardModel {
        let runningGatewayCount = gateways.filter { runtimeCategory(for: $0) == .running }.count
        let errorGatewayCount = gateways.filter { runtimeCategory(for: $0) == .error }.count
        let averageLatency = logs.isEmpty ? 0 : logs.map(\.latencyMs).reduce(0, +) / logs.count
        let successCount = logs.filter { (200..<400).contains($0.statusCode) && $0.error == nil }.count
        let errorCount = logs.count - successCount
        let adminEndpointText = gateways.first.map { "\($0.listenHost):\($0.listenPort)" } ?? L10n.string(L10n.overviewNetworkNoGateway, locale: locale)

        return OverviewDashboardModel(
            runningStatus: RunningStatus(
                connectionCount: logs.count,
                providerCount: providers.count,
                runningGatewayCount: runningGatewayCount,
                errorGatewayCount: errorGatewayCount
            ),
            networkStatus: NetworkStatus(
                internetLatencyMs: averageLatency,
                adminEndpointText: adminEndpointText,
                gatewayStatus: runningGatewayCount > 0 ? .healthy : .idle
            ),
            trafficSummary: TrafficSummary(
                totalRequests: logs.count,
                successCount: successCount,
                errorCount: errorCount
            )
        )
    }
}
