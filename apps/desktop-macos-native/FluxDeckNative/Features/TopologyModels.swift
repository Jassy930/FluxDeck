import Foundation

struct TopologyGraph {
    let columns: [TopologyColumn]
    let edges: [TopologyEdge]

    static func make(gateways: [AdminGateway], providers: [AdminProvider], logs: [AdminLog]) -> TopologyGraph {
        let entrypointNodes = gateways.map { gateway in
            TopologyNode(
                id: "entrypoint:\(gateway.listenHost):\(gateway.listenPort)",
                title: gateway.listenHost,
                subtitle: "\(gateway.listenPort)"
            )
        }

        let gatewayNodes = gateways.map { gateway in
            TopologyNode(
                id: gateway.id,
                title: gateway.name,
                subtitle: "\(gateway.listenHost):\(gateway.listenPort)"
            )
        }

        let providerIDsInUse = Set(logs.map(\ .providerID))
        let providerNodes = providers
            .filter { providerIDsInUse.isEmpty || providerIDsInUse.contains($0.id) }
            .map { provider in
                TopologyNode(
                    id: provider.id,
                    title: provider.name,
                    subtitle: provider.kind.uppercased()
                )
            }

        var edges: [TopologyEdge] = []

        for gateway in gateways {
            let requestCount = logs.filter { $0.gatewayID == gateway.id }.count
            guard requestCount > 0 else { continue }

            edges.append(
                TopologyEdge(
                    id: "entry:\(gateway.id)",
                    fromNodeID: "entrypoint:\(gateway.listenHost):\(gateway.listenPort)",
                    toNodeID: gateway.id,
                    requestCount: requestCount
                )
            )
        }

        let providerEdgeCounts = Dictionary(grouping: logs) { log in
            "\(log.gatewayID)->\(log.providerID)"
        }

        for key in providerEdgeCounts.keys.sorted() {
            guard let groupedLogs = providerEdgeCounts[key],
                  let first = groupedLogs.first else {
                continue
            }

            edges.append(
                TopologyEdge(
                    id: key,
                    fromNodeID: first.gatewayID,
                    toNodeID: first.providerID,
                    requestCount: groupedLogs.count
                )
            )
        }

        return TopologyGraph(
            columns: [
                TopologyColumn(title: "Entrypoints", nodes: entrypointNodes),
                TopologyColumn(title: "Gateways", nodes: gatewayNodes),
                TopologyColumn(title: "Providers", nodes: providerNodes)
            ],
            edges: edges
        )
    }
}

struct TopologyColumn: Identifiable {
    let id = UUID()
    let title: String
    let nodes: [TopologyNode]
}

struct TopologyNode: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

struct TopologyEdge: Identifiable, Hashable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    let requestCount: Int
}
