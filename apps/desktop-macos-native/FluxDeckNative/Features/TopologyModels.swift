import Foundation

enum TopologyHighlightMode: String, CaseIterable, Equatable, Identifiable {
    case top3 = "top3"
    case top5 = "top5"
    case all = "all"

    var id: String { rawValue }

    var titleKey: String {
        "topology.highlight.\(rawValue)"
    }

    var modelLimit: Int? {
        switch self {
        case .top3:
            return 3
        case .top5:
            return 5
        case .all:
            return nil
        }
    }
}

struct TopologyGraph {
    let columns: [TopologyColumn]
    let edges: [TopologyEdge]

    static func make(
        gateways: [AdminGateway],
        providers: [AdminProvider],
        logs: [AdminLog],
        locale: Locale = Locale(identifier: "en")
    ) -> TopologyGraph {
        let gatewayByID = Dictionary(uniqueKeysWithValues: gateways.map { ($0.id, $0) })
        let providerByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        let nodeStats = buildNodeStats(logs: logs, gateways: gateways)

        let entrypointNodes = Dictionary(grouping: gateways, by: entrypointNodeID(for:))
            .keys
            .sorted()
            .map { entrypointID in
                let firstGateway = gateways.first(where: { entrypointNodeID(for: $0) == entrypointID })!
                let stats = nodeStats[entrypointID] ?? .empty

                return TopologyNode(
                    id: entrypointID,
                    title: firstGateway.listenHost,
                    subtitle: "\(firstGateway.listenPort)",
                    totalTokens: stats.totalTokens,
                    requestCount: stats.requestCount,
                    cachedTokens: stats.cachedTokens,
                    errorCount: stats.errorCount
                )
        }

        let gatewayNodes = gateways.map { gateway in
            let stats = nodeStats[gateway.id] ?? .empty

            return TopologyNode(
                id: gateway.id,
                title: gateway.name,
                subtitle: "\(gateway.listenHost):\(gateway.listenPort)",
                totalTokens: stats.totalTokens,
                requestCount: stats.requestCount,
                cachedTokens: stats.cachedTokens,
                errorCount: stats.errorCount
            )
        }

        let providerIDs = Set(providers.map(\.id)).union(logs.map(\.providerID))
        let providerNodes = providerIDs.sorted().map { providerID in
            let stats = nodeStats[providerID] ?? .empty

            if let provider = providerByID[providerID] {
                return TopologyNode(
                    id: provider.id,
                    title: provider.name,
                    subtitle: provider.kind.uppercased(),
                    totalTokens: stats.totalTokens,
                    requestCount: stats.requestCount,
                    cachedTokens: stats.cachedTokens,
                    errorCount: stats.errorCount
                )
            }

            return TopologyNode(
                id: providerID,
                title: providerID,
                subtitle: L10n.string(L10n.topologyUnknownProvider, locale: locale),
                totalTokens: stats.totalTokens,
                requestCount: stats.requestCount,
                cachedTokens: stats.cachedTokens,
                errorCount: stats.errorCount
            )
        }

        var edges: [TopologyEdge] = []

        for gateway in gateways {
            let groupedLogs = logs.filter { $0.gatewayID == gateway.id }
            guard !groupedLogs.isEmpty else { continue }

            edges.append(
                makeEdge(
                    id: "entry:\(gateway.id)",
                    fromNodeID: entrypointNodeID(for: gateway),
                    toNodeID: gateway.id,
                    logs: groupedLogs
                )
            )
        }

        let providerEdgeLogs = Dictionary(grouping: logs) { log in
            "\(log.gatewayID)->\(log.providerID)"
        }

        for edgeID in providerEdgeLogs.keys.sorted() {
            guard let groupedLogs = providerEdgeLogs[edgeID], let first = groupedLogs.first else {
                continue
            }

            let gatewayID = gatewayByID[first.gatewayID]?.id ?? first.gatewayID
            edges.append(
                makeEdge(
                    id: edgeID,
                    fromNodeID: gatewayID,
                    toNodeID: first.providerID,
                    logs: groupedLogs
                )
            )
        }

        return TopologyGraph(
            columns: [
                TopologyColumn(titleKey: L10n.topologyColumnsEntrypoints, nodes: entrypointNodes),
                TopologyColumn(titleKey: L10n.topologyColumnsGateways, nodes: gatewayNodes),
                TopologyColumn(titleKey: L10n.topologyColumnsProviders, nodes: providerNodes)
            ],
            edges: edges
        )
    }

    func applyingHighlightMode(_ highlightMode: TopologyHighlightMode) -> TopologyGraph {
        guard let modelLimit = highlightMode.modelLimit else {
            return self
        }

        let highlightedModels = Set(
            edges
                .flatMap(\.segments)
                .reduce(into: [String: Int]()) { partialResult, segment in
                    partialResult[segment.modelName, default: 0] += segment.totalTokens
                }
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.key < rhs.key
                    }
                    return lhs.value > rhs.value
                }
                .prefix(modelLimit)
                .map(\.key)
        )

        return TopologyGraph(
            columns: columns,
            edges: edges.map { $0.applyingHighlightedModels(highlightedModels) }
        )
    }

    private static func buildNodeStats(logs: [AdminLog], gateways: [AdminGateway]) -> [String: TopologyAggregate] {
        var result: [String: TopologyAggregate] = [:]
        let gatewayByID = Dictionary(uniqueKeysWithValues: gateways.map { ($0.id, $0) })

        for log in logs {
            let aggregate = TopologyAggregate(log: log)

            if let gateway = gatewayByID[log.gatewayID] {
                result[entrypointNodeID(for: gateway), default: .empty].merge(aggregate)
            }

            result[log.gatewayID, default: .empty].merge(aggregate)
            result[log.providerID, default: .empty].merge(aggregate)
        }

        return result
    }

    private static func makeEdge(id: String, fromNodeID: String, toNodeID: String, logs: [AdminLog]) -> TopologyEdge {
        var aggregate = TopologyAggregate.empty
        var segmentAggregates: [String: TopologyAggregate] = [:]

        for log in logs {
            let logAggregate = TopologyAggregate(log: log)
            aggregate.merge(logAggregate)
            segmentAggregates[modelName(for: log), default: .empty].merge(logAggregate)
        }

        let segments = segmentAggregates.map { modelName, value in
            TopologyEdgeSegment(
                id: "\(id)#\(modelName)",
                modelName: modelName,
                totalTokens: value.totalTokens,
                requestCount: value.requestCount,
                cachedTokens: value.cachedTokens,
                errorCount: value.errorCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalTokens == rhs.totalTokens {
                return lhs.modelName < rhs.modelName
            }
            return lhs.totalTokens > rhs.totalTokens
        }

        return TopologyEdge(
            id: id,
            fromNodeID: fromNodeID,
            toNodeID: toNodeID,
            totalTokens: aggregate.totalTokens,
            requestCount: aggregate.requestCount,
            cachedTokens: aggregate.cachedTokens,
            errorCount: aggregate.errorCount,
            segments: segments
        )
    }

    private static func modelName(for log: AdminLog) -> String {
        if let modelEffective = normalized(log.modelEffective) {
            return modelEffective
        }
        if let model = normalized(log.model) {
            return model
        }
        return "unknown"
    }

    private static func entrypointNodeID(for gateway: AdminGateway) -> String {
        "entrypoint:\(gateway.listenHost):\(gateway.listenPort)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct TopologyColumn: Identifiable {
    let id = UUID()
    let titleKey: String
    let nodes: [TopologyNode]
}

struct TopologyNode: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let totalTokens: Int
    let requestCount: Int
    let cachedTokens: Int
    let errorCount: Int
}

struct TopologyEdgeSegment: Identifiable, Hashable {
    let id: String
    let modelName: String
    let totalTokens: Int
    let requestCount: Int
    let cachedTokens: Int
    let errorCount: Int
}

struct TopologyEdge: Identifiable, Hashable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    let totalTokens: Int
    let requestCount: Int
    let cachedTokens: Int
    let errorCount: Int
    let segments: [TopologyEdgeSegment]

    func applyingHighlightedModels(_ highlightedModels: Set<String>) -> TopologyEdge {
        var visibleSegments: [TopologyEdgeSegment] = []
        var otherAggregate = TopologyAggregate.empty

        for segment in segments {
            if highlightedModels.contains(segment.modelName) {
                visibleSegments.append(segment)
            } else {
                otherAggregate.merge(
                    TopologyAggregate(
                        totalTokens: segment.totalTokens,
                        requestCount: segment.requestCount,
                        cachedTokens: segment.cachedTokens,
                        errorCount: segment.errorCount
                    )
                )
            }
        }

        if otherAggregate.requestCount > 0 {
            visibleSegments.append(
                TopologyEdgeSegment(
                    id: "\(id)#Other",
                    modelName: "Other",
                    totalTokens: otherAggregate.totalTokens,
                    requestCount: otherAggregate.requestCount,
                    cachedTokens: otherAggregate.cachedTokens,
                    errorCount: otherAggregate.errorCount
                )
            )
        }

        return TopologyEdge(
            id: id,
            fromNodeID: fromNodeID,
            toNodeID: toNodeID,
            totalTokens: totalTokens,
            requestCount: requestCount,
            cachedTokens: cachedTokens,
            errorCount: errorCount,
            segments: visibleSegments.sorted { lhs, rhs in
                if lhs.modelName == "Other" {
                    return false
                }
                if rhs.modelName == "Other" {
                    return true
                }
                if lhs.totalTokens == rhs.totalTokens {
                    return lhs.modelName < rhs.modelName
                }
                return lhs.totalTokens > rhs.totalTokens
            }
        )
    }
}

private struct TopologyAggregate: Hashable {
    var totalTokens: Int
    var requestCount: Int
    var cachedTokens: Int
    var errorCount: Int

    static let empty = TopologyAggregate(totalTokens: 0, requestCount: 0, cachedTokens: 0, errorCount: 0)

    init(totalTokens: Int, requestCount: Int, cachedTokens: Int, errorCount: Int) {
        self.totalTokens = totalTokens
        self.requestCount = requestCount
        self.cachedTokens = cachedTokens
        self.errorCount = errorCount
    }

    init(log: AdminLog) {
        totalTokens = log.totalTokens ?? Self.fallbackTokens(for: log)
        requestCount = 1
        cachedTokens = log.cachedTokens ?? 0
        errorCount = log.statusCode >= 400 || log.error != nil ? 1 : 0
    }

    mutating func merge(_ other: TopologyAggregate) {
        totalTokens += other.totalTokens
        requestCount += other.requestCount
        cachedTokens += other.cachedTokens
        errorCount += other.errorCount
    }

    private static func fallbackTokens(for log: AdminLog) -> Int {
        (log.inputTokens ?? 0) + (log.outputTokens ?? 0)
    }
}
