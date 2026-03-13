import SwiftUI

enum TopologyMetricMode: String, CaseIterable, Identifiable {
    case tokens = "Tokens"
    case requests = "Requests"

    var id: String { rawValue }
}

enum TopologyFlowMode: String, CaseIterable, Identifiable {
    case byModel = "By Model"
    case totalOnly = "Total Only"

    var id: String { rawValue }
}

struct TopologyCanvasSegmentModel: Identifiable {
    let id: String
    let title: String
    let totalTokens: Int
    let emphasisValue: Int
    let requestCount: Int
    let cachedTokens: Int
    let errorCount: Int
    let semanticColor: DesignTokens.SemanticColor
}

struct TopologyCanvasEdgeModel: Identifiable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    let routeText: String
    let totalTokens: Int
    let requestCount: Int
    let cachedTokens: Int
    let errorCount: Int
    let segments: [TopologyCanvasSegmentModel]
}

struct TopologyHotPathRow: Identifiable {
    let id: String
    let routeText: String
    let tokenText: String
    let requestText: String
    let topModelText: String
}

struct TopologyModelMixItem: Identifiable {
    let id: String
    let title: String
    let totalValue: Int
    let valueText: String
    let shareText: String
    let semanticColor: DesignTokens.SemanticColor
}

struct TopologyNodeCardModel: Hashable {
    let primaryMetricText: String
    let secondaryMetricText: String
    let tertiaryMetricText: String?

    static func make(node: TopologyNode) -> TopologyNodeCardModel {
        let tertiaryMetricText: String?
        if node.cachedTokens > 0 {
            tertiaryMetricText = "\(formatTopologyNumber(node.cachedTokens)) cached"
        } else if node.errorCount > 0 {
            tertiaryMetricText = "\(node.errorCount) err"
        } else {
            tertiaryMetricText = nil
        }

        return TopologyNodeCardModel(
            primaryMetricText: "\(formatTopologyNumber(node.totalTokens)) tok",
            secondaryMetricText: "\(formatTopologyNumber(node.requestCount)) req",
            tertiaryMetricText: tertiaryMetricText
        )
    }
}

struct TopologyCanvasNodeHoverSummary: Hashable {
    let topModelName: String
    let errorCount: Int
}

struct TopologyCanvasNodeSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let metricLine: String
    let detailLine: String
    let hoverSummary: TopologyCanvasNodeHoverSummary
    let anchorLineCount: Int
}

enum TopologyCanvasHoverTarget: Equatable {
    case node(nodeID: String)
    case segment(edgeID: String, segmentID: String)
}

struct TopologyCanvasTooltipPayload: Equatable {
    let title: String
    let rows: [String]
}

struct TopologyCanvasHoverState {
    let target: TopologyCanvasHoverTarget?
    let tooltip: TopologyCanvasTooltipPayload?
    let highlightedNodeIDs: Set<String>
    let highlightedEdgeIDs: Set<String>
    let highlightedSegmentID: String?
    let siblingEdgeID: String?
    let dimmedEdgeOpacity: Double
    let dimmedNodeOpacity: Double
    let siblingSegmentOpacity: Double

    static let idle = TopologyCanvasHoverState(
        target: nil,
        tooltip: nil,
        highlightedNodeIDs: [],
        highlightedEdgeIDs: [],
        highlightedSegmentID: nil,
        siblingEdgeID: nil,
        dimmedEdgeOpacity: 0.16,
        dimmedNodeOpacity: 0.38,
        siblingSegmentOpacity: 0.46
    )

    func edgeOpacity(edgeID: String, segmentID: String) -> Double {
        guard let target else {
            return 1
        }

        switch target {
        case .node:
            return highlightedEdgeIDs.contains(edgeID) ? 1 : dimmedEdgeOpacity
        case .segment:
            guard edgeID == siblingEdgeID else {
                return dimmedEdgeOpacity
            }
            return segmentID == highlightedSegmentID ? 1 : siblingSegmentOpacity
        }
    }

    func nodeOpacity(nodeID: String) -> Double {
        guard target != nil else {
            return 1
        }
        return highlightedNodeIDs.contains(nodeID) ? 1 : dimmedNodeOpacity
    }
}

struct TopologyCanvasStageLayout {
    let canvasPadding: CGFloat
    let topInset: CGFloat
    let rowPitch: CGFloat
    let nodeWidth: CGFloat
    let gatewayNodeWidth: CGFloat
    let nodeHeight: CGFloat
    let columnSpacing: CGFloat
    let minReadableBandWidth: CGFloat
    let maxRenderedBandWidth: CGFloat
    let bandGap: CGFloat
    let showsOuterPanel: Bool
    let showsCanvasBackground: Bool
    let showsCanvasBorder: Bool
    let showsColumnHeaders: Bool
    let showsColumnRails: Bool
    let showsNodeDetailLine: Bool

    static let sankey = TopologyCanvasStageLayout(
        canvasPadding: 22,
        topInset: 54,
        rowPitch: 96,
        nodeWidth: 150,
        gatewayNodeWidth: 170,
        nodeHeight: 58,
        columnSpacing: 28,
        minReadableBandWidth: 10,
        maxRenderedBandWidth: 34,
        bandGap: 3,
        showsOuterPanel: false,
        showsCanvasBackground: false,
        showsCanvasBorder: false,
        showsColumnHeaders: false,
        showsColumnRails: false,
        showsNodeDetailLine: false
    )

    func width(forColumnAt index: Int) -> CGFloat {
        index == 1 ? gatewayNodeWidth : nodeWidth
    }
}

struct TopologyControlStripLayout {
    let usesSingleLine: Bool
    let showsSectionTitles: Bool
    let usesSubtleVerticalDividers: Bool
    let groupCount: Int
    let groupSpacing: CGFloat
    let dividerOpacity: Double
    let dividerHeight: CGFloat

    static let sankey = TopologyControlStripLayout(
        usesSingleLine: true,
        showsSectionTitles: false,
        usesSubtleVerticalDividers: true,
        groupCount: 3,
        groupSpacing: 10,
        dividerOpacity: 0.34,
        dividerHeight: 20
    )
}

enum TopologyBandScale {
    static func readableWidth(
        value: Int,
        maxValue: Int,
        maxRenderedWidth: CGFloat,
        minReadableWidth: CGFloat
    ) -> CGFloat {
        guard value > 0 else {
            return minReadableWidth
        }

        let safeMax = max(maxValue, 1)
        let normalized = pow(CGFloat(value) / CGFloat(safeMax), 1.2)
        return max(minReadableWidth, normalized * maxRenderedWidth)
    }
}

struct TopologyCanvasScreenModel {
    let graph: TopologyGraph
    let canvasEdges: [TopologyCanvasEdgeModel]
    let nodeSummaries: [String: TopologyCanvasNodeSummary]
    let hotPaths: [TopologyHotPathRow]
    let modelMix: [TopologyModelMixItem]
    let summaryTitle: String
    let mixTitle: String
    let emptyStateText: String?
    private let nodeTooltipPayloads: [String: TopologyCanvasTooltipPayload]
    private let segmentTooltipPayloads: [String: TopologyCanvasTooltipPayload]
    private let nodeConnectedEdges: [String: Set<String>]
    private let nodeConnectedNodes: [String: Set<String>]

    static func make(
        graph: TopologyGraph,
        metricMode: TopologyMetricMode,
        flowMode: TopologyFlowMode,
        highlightMode: TopologyHighlightMode
    ) -> TopologyCanvasScreenModel {
        let highlightedGraph = graph.applyingHighlightMode(highlightMode)
        let sourceEdges = summaryEdges(from: highlightedGraph)
        let nodeLookup = buildNodeLookup(from: highlightedGraph)
        let colorLookup = buildModelColorLookup(from: sourceEdges)
        let canvasEdges = highlightedGraph.edges.map { edge in
            let routeText = routeText(for: edge, nodeLookup: nodeLookup)
            return TopologyCanvasEdgeModel(
                id: edge.id,
                fromNodeID: edge.fromNodeID,
                toNodeID: edge.toNodeID,
                routeText: routeText,
                totalTokens: edge.totalTokens,
                requestCount: edge.requestCount,
                cachedTokens: edge.cachedTokens,
                errorCount: edge.errorCount,
                segments: displaySegments(
                    for: edge,
                    metricMode: metricMode,
                    flowMode: flowMode,
                    colorLookup: colorLookup
                )
            )
        }

        let hotPaths = sourceEdges
            .sorted { lhs, rhs in
                if lhs.totalTokens == rhs.totalTokens {
                    return lhs.id < rhs.id
                }
                return lhs.totalTokens > rhs.totalTokens
            }
            .prefix(4)
            .map { edge in
                TopologyHotPathRow(
                    id: edge.id,
                    routeText: routeText(for: edge, nodeLookup: nodeLookup),
                    tokenText: "\(formatTopologyNumber(edge.totalTokens)) tok",
                    requestText: "\(formatTopologyNumber(edge.requestCount)) req",
                    topModelText: "Top model \(edge.segments.first?.modelName ?? "unknown")"
                )
            }

        let modelMix = buildModelMix(from: sourceEdges, colorLookup: colorLookup)
        let nodeSummaries = buildNodeSummaries(from: highlightedGraph, edges: canvasEdges)
        let nodeTooltipPayloads = buildNodeTooltipPayloads(from: highlightedGraph, edges: canvasEdges, nodeLookup: nodeLookup)
        let segmentTooltipPayloads = buildSegmentTooltipPayloads(from: canvasEdges)
        let nodeConnectedEdges = buildNodeConnectedEdges(from: canvasEdges)
        let nodeConnectedNodes = buildNodeConnectedNodes(from: canvasEdges)
        let emptyStateText = highlightedGraph.edges.isEmpty ? "No active token routes yet." : nil

        return TopologyCanvasScreenModel(
            graph: highlightedGraph,
            canvasEdges: canvasEdges,
            nodeSummaries: nodeSummaries,
            hotPaths: hotPaths,
            modelMix: modelMix,
            summaryTitle: "Hot Paths",
            mixTitle: "Model Mix",
            emptyStateText: emptyStateText,
            nodeTooltipPayloads: nodeTooltipPayloads,
            segmentTooltipPayloads: segmentTooltipPayloads,
            nodeConnectedEdges: nodeConnectedEdges,
            nodeConnectedNodes: nodeConnectedNodes
        )
    }

    func hoverPayload(for target: TopologyCanvasHoverTarget) -> TopologyCanvasTooltipPayload? {
        switch target {
        case let .node(nodeID):
            return nodeTooltipPayloads[nodeID]
        case let .segment(_, segmentID):
            return segmentTooltipPayloads[segmentID]
        }
    }

    func hoverState(for target: TopologyCanvasHoverTarget?) -> TopologyCanvasHoverState {
        guard let target else {
            return .idle
        }

        switch target {
        case let .node(nodeID):
            guard let tooltip = nodeTooltipPayloads[nodeID] else {
                return .idle
            }

            return TopologyCanvasHoverState(
                target: target,
                tooltip: tooltip,
                highlightedNodeIDs: nodeConnectedNodes[nodeID, default: Set([nodeID])].union(Set([nodeID])),
                highlightedEdgeIDs: nodeConnectedEdges[nodeID, default: Set<String>()],
                highlightedSegmentID: nil,
                siblingEdgeID: nil,
                dimmedEdgeOpacity: 0.16,
                dimmedNodeOpacity: 0.38,
                siblingSegmentOpacity: 0.46
            )

        case let .segment(edgeID, segmentID):
            guard
                let tooltip = segmentTooltipPayloads[segmentID],
                let edge = canvasEdges.first(where: { $0.id == edgeID })
            else {
                return .idle
            }

            return TopologyCanvasHoverState(
                target: target,
                tooltip: tooltip,
                highlightedNodeIDs: Set([edge.fromNodeID, edge.toNodeID]),
                highlightedEdgeIDs: Set([edgeID]),
                highlightedSegmentID: segmentID,
                siblingEdgeID: edgeID,
                dimmedEdgeOpacity: 0.16,
                dimmedNodeOpacity: 0.38,
                siblingSegmentOpacity: 0.46
            )
        }
    }

    private static func summaryEdges(from graph: TopologyGraph) -> [TopologyEdge] {
        let providerEdges = graph.edges.filter { !$0.fromNodeID.hasPrefix("entrypoint:") }
        return providerEdges.isEmpty ? graph.edges : providerEdges
    }

    private static func buildNodeLookup(from graph: TopologyGraph) -> [String: TopologyNode] {
        graph.columns
            .flatMap(\.nodes)
            .reduce(into: [String: TopologyNode]()) { partialResult, node in
                partialResult[node.id] = node
            }
    }

    private static func displaySegments(
        for edge: TopologyEdge,
        metricMode: TopologyMetricMode,
        flowMode: TopologyFlowMode,
        colorLookup: [String: DesignTokens.SemanticColor]
    ) -> [TopologyCanvasSegmentModel] {
        switch flowMode {
        case .byModel:
            return edge.segments.compactMap { segment in
                let emphasisValue = emphasisValue(for: segment, metricMode: metricMode)
                guard emphasisValue > 0 else {
                    return nil
                }

                return TopologyCanvasSegmentModel(
                    id: segment.id,
                    title: segment.modelName,
                    totalTokens: segment.totalTokens,
                    emphasisValue: emphasisValue,
                    requestCount: segment.requestCount,
                    cachedTokens: segment.cachedTokens,
                    errorCount: segment.errorCount,
                    semanticColor: colorLookup[segment.modelName] ?? DesignTokens.topologyModelColor(for: segment.modelName, rankedIndex: nil)
                )
            }

        case .totalOnly:
            let emphasisValue = metricMode == .tokens ? edge.totalTokens : edge.requestCount
            guard emphasisValue > 0 else {
                return []
            }

            return [
                TopologyCanvasSegmentModel(
                    id: "\(edge.id)#total",
                    title: "Total",
                    totalTokens: edge.totalTokens,
                    emphasisValue: emphasisValue,
                    requestCount: edge.requestCount,
                    cachedTokens: edge.cachedTokens,
                    errorCount: edge.errorCount,
                    semanticColor: DesignTokens.statusColors.running
                )
            ]
        }
    }

    private static func emphasisValue(for segment: TopologyEdgeSegment, metricMode: TopologyMetricMode) -> Int {
        switch metricMode {
        case .tokens:
            return segment.totalTokens
        case .requests:
            return segment.requestCount
        }
    }

    private static func buildModelMix(
        from edges: [TopologyEdge],
        colorLookup: [String: DesignTokens.SemanticColor]
    ) -> [TopologyModelMixItem] {
        let aggregate = edges
            .flatMap(\.segments)
            .reduce(into: [String: Int]()) { partialResult, segment in
                partialResult[segment.modelName, default: 0] += segment.totalTokens
            }

        let total = max(aggregate.values.reduce(0, +), 1)

        return aggregate
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map { item in
                TopologyModelMixItem(
                    id: item.key,
                    title: item.key,
                    totalValue: item.value,
                    valueText: "\(formatTopologyNumber(item.value)) tok",
                    shareText: formatTopologyPercent(Double(item.value) / Double(total)),
                    semanticColor: colorLookup[item.key] ?? DesignTokens.topologyModelColor(for: item.key, rankedIndex: nil)
                )
            }
    }

    private static func buildModelColorLookup(from edges: [TopologyEdge]) -> [String: DesignTokens.SemanticColor] {
        let rankedModels = edges
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

        var colorLookup: [String: DesignTokens.SemanticColor] = [:]
        var rankedIndex = 0

        for item in rankedModels {
            if item.key == "Other" || item.key == "unknown" {
                colorLookup[item.key] = DesignTokens.topologyModelColor(for: item.key, rankedIndex: nil)
                continue
            }

            colorLookup[item.key] = DesignTokens.topologyModelColor(for: item.key, rankedIndex: rankedIndex)
            rankedIndex += 1
        }

        return colorLookup
    }

    private static func buildNodeSummaries(
        from graph: TopologyGraph,
        edges: [TopologyCanvasEdgeModel]
    ) -> [String: TopologyCanvasNodeSummary] {
        graph.columns
            .flatMap(\.nodes)
            .reduce(into: [String: TopologyCanvasNodeSummary]()) { partialResult, node in
                let relatedSegments = edges
                    .filter { $0.fromNodeID == node.id || $0.toNodeID == node.id }
                    .flatMap(\.segments)
                    .sorted { lhs, rhs in
                        if lhs.totalTokens == rhs.totalTokens {
                            return lhs.title < rhs.title
                        }
                        return lhs.totalTokens > rhs.totalTokens
                    }
                let topModelName = relatedSegments.first?.title ?? "unknown"
                let detailComponents = [
                    node.cachedTokens > 0 ? "\(formatTopologyNumber(node.cachedTokens)) cached" : nil,
                    node.errorCount > 0 ? "\(node.errorCount) err" : nil
                ].compactMap { $0 }
                let detailLine = detailComponents.isEmpty ? node.subtitle : detailComponents.joined(separator: " · ")

                partialResult[node.id] = TopologyCanvasNodeSummary(
                    id: node.id,
                    title: node.title,
                    subtitle: node.subtitle,
                    metricLine: "\(formatTopologyNumber(node.totalTokens)) tok · \(formatTopologyNumber(node.requestCount)) req",
                    detailLine: detailLine,
                    hoverSummary: TopologyCanvasNodeHoverSummary(
                        topModelName: topModelName,
                        errorCount: node.errorCount
                    ),
                    anchorLineCount: 3
                )
            }
    }

    private static func buildNodeTooltipPayloads(
        from graph: TopologyGraph,
        edges: [TopologyCanvasEdgeModel],
        nodeLookup: [String: TopologyNode]
    ) -> [String: TopologyCanvasTooltipPayload] {
        buildNodeSummaries(from: graph, edges: edges)
            .reduce(into: [String: TopologyCanvasTooltipPayload]()) { partialResult, item in
                guard let node = nodeLookup[item.key] else {
                    return
                }

                partialResult[item.key] = TopologyCanvasTooltipPayload(
                    title: item.value.title,
                    rows: [
                        "\(formatTopologyNumber(node.totalTokens)) tok",
                        "\(formatTopologyNumber(node.requestCount)) req",
                        "Top model \(item.value.hoverSummary.topModelName)",
                        "\(item.value.hoverSummary.errorCount) err"
                    ]
                )
            }
    }

    private static func buildSegmentTooltipPayloads(
        from edges: [TopologyCanvasEdgeModel]
    ) -> [String: TopologyCanvasTooltipPayload] {
        edges
            .flatMap { edge in
                edge.segments.map { segment in
                    (
                        segment.id,
                        TopologyCanvasTooltipPayload(
                            title: edge.routeText,
                            rows: [
                                "Model \(segment.title)",
                                "\(formatTopologyNumber(segment.totalTokens)) tok",
                                "\(formatTopologyNumber(segment.requestCount)) req",
                                "\(formatTopologyNumber(segment.cachedTokens)) cached",
                                "\(segment.errorCount) err"
                            ]
                        )
                    )
                }
            }
            .reduce(into: [String: TopologyCanvasTooltipPayload]()) { partialResult, item in
                partialResult[item.0] = item.1
            }
    }

    private static func buildNodeConnectedEdges(from edges: [TopologyCanvasEdgeModel]) -> [String: Set<String>] {
        edges.reduce(into: [String: Set<String>]()) { partialResult, edge in
            partialResult[edge.fromNodeID, default: Set<String>()].insert(edge.id)
            partialResult[edge.toNodeID, default: Set<String>()].insert(edge.id)
        }
    }

    private static func buildNodeConnectedNodes(from edges: [TopologyCanvasEdgeModel]) -> [String: Set<String>] {
        edges.reduce(into: [String: Set<String>]()) { partialResult, edge in
            partialResult[edge.fromNodeID, default: Set<String>()].insert(edge.toNodeID)
            partialResult[edge.toNodeID, default: Set<String>()].insert(edge.fromNodeID)
        }
    }

    private static func routeText(
        for edge: TopologyEdge,
        nodeLookup: [String: TopologyNode]
    ) -> String {
        let fromTitle = nodeLookup[edge.fromNodeID]?.title ?? edge.fromNodeID
        let toTitle = nodeLookup[edge.toNodeID]?.title ?? edge.toNodeID
        return "\(fromTitle) -> \(toTitle)"
    }
}

struct TopologyCanvasView: View {
    let graph: TopologyGraph

    @State private var metricMode: TopologyMetricMode = .tokens
    @State private var flowMode: TopologyFlowMode = .byModel
    @State private var highlightMode: TopologyHighlightMode = .top5
    @State private var hoverTarget: TopologyCanvasHoverTarget?

    private let stageLayout = TopologyCanvasStageLayout.sankey
    private let controlStripLayout = TopologyControlStripLayout.sankey

    private var screenModel: TopologyCanvasScreenModel {
        TopologyCanvasScreenModel.make(
            graph: graph,
            metricMode: metricMode,
            flowMode: flowMode,
            highlightMode: highlightMode
        )
    }

    private var hoverState: TopologyCanvasHoverState {
        screenModel.hoverState(for: hoverTarget)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Topology")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        Text("Sankey flow with inline model density and hover diagnostics.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }

                    Spacer()

                    topologyControlStrip
                        .frame(maxWidth: 500)
                }

                if let emptyStateText = screenModel.emptyStateText {
                    emptyStateCard(text: emptyStateText)
                } else {
                    TopologyCanvas(
                        graph: screenModel.graph,
                        edges: screenModel.canvasEdges,
                        nodeSummaries: screenModel.nodeSummaries,
                        hoverState: hoverState,
                        stageLayout: stageLayout
                    ) { nextTarget in
                        hoverTarget = nextTarget
                    }
                    .frame(height: canvasHeight)
                }

                HStack(alignment: .top, spacing: 16) {
                    SurfaceCard(title: screenModel.summaryTitle) {
                        if screenModel.hotPaths.isEmpty {
                            Text(screenModel.emptyStateText ?? "No active routes yet.")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(screenModel.hotPaths) { row in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(row.routeText)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(DesignTokens.textPrimary)

                                        HStack(spacing: 10) {
                                            summaryMetricPill(text: row.tokenText, semanticColor: DesignTokens.statusColors.running)
                                            summaryMetricPill(text: row.requestText, semanticColor: DesignTokens.statusColors.warning)
                                            summaryMetricPill(text: row.topModelText, semanticColor: DesignTokens.statusColors.inactive)
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(DesignTokens.surfaceSecondary.opacity(0.88))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    SurfaceCard(title: screenModel.mixTitle) {
                        if screenModel.modelMix.isEmpty {
                            Text(screenModel.emptyStateText ?? "No model composition yet.")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                mixBar(items: screenModel.modelMix)

                                ForEach(screenModel.modelMix) { item in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(item.semanticColor.fill)
                                            .frame(width: 8, height: 8)
                                        Text(item.title)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(DesignTokens.textPrimary)
                                        Spacer()
                                        Text(item.shareText)
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.textSecondary)
                                        Text(item.valueText)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(DesignTokens.textPrimary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 320, alignment: .topLeading)
                }
            }
            .padding(20)
        }
    }

    private var topologyControlStrip: some View {
        HStack(alignment: .center, spacing: controlStripLayout.groupSpacing) {
            topologyControlGroup(accessibilityLabel: "Metric") {
                Picker("Metric", selection: $metricMode) {
                    ForEach(TopologyMetricMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if controlStripLayout.usesSubtleVerticalDividers {
                topologyControlDivider
            }

            topologyControlGroup(accessibilityLabel: "Flow") {
                Picker("Flow", selection: $flowMode) {
                    ForEach(TopologyFlowMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if controlStripLayout.usesSubtleVerticalDividers {
                topologyControlDivider
            }

            topologyControlGroup(accessibilityLabel: "Highlight") {
                Picker("Highlight", selection: $highlightMode) {
                    Text("Top 3").tag(TopologyHighlightMode.top3)
                    Text("Top 5").tag(TopologyHighlightMode.top5)
                    Text("All").tag(TopologyHighlightMode.all)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var topologyControlDivider: some View {
        Rectangle()
            .fill(DesignTokens.borderSubtle.opacity(controlStripLayout.dividerOpacity))
            .frame(width: 1, height: controlStripLayout.dividerHeight)
    }

    private func topologyControlGroup<Content: View>(
        accessibilityLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if controlStripLayout.showsSectionTitles {
                Text(accessibilityLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            content()
                .labelsHidden()
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private func summaryMetricPill(text: String, semanticColor: DesignTokens.SemanticColor) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(semanticColor.glow.opacity(0.8))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(semanticColor.fill.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
    }

    private func mixBar(items: [TopologyModelMixItem]) -> some View {
        GeometryReader { geometry in
            let total = max(items.reduce(0) { $0 + $1.totalValue }, 1)

            HStack(spacing: 2) {
                ForEach(items) { item in
                    Rectangle()
                        .fill(item.semanticColor.fill.opacity(0.82))
                        .frame(width: max(CGFloat(item.totalValue) / CGFloat(total) * geometry.size.width, 8))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(height: 10)
    }

    private func emptyStateCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Awaiting traffic")
                .font(.headline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text(text)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canvasHeight: CGFloat {
        CGFloat(max(screenModel.graph.columns.map { $0.nodes.count }.max() ?? 1, 1) - 1) * stageLayout.rowPitch + 186
    }
}

private struct TopologyCanvas: View {
    let graph: TopologyGraph
    let edges: [TopologyCanvasEdgeModel]
    let nodeSummaries: [String: TopologyCanvasNodeSummary]
    let hoverState: TopologyCanvasHoverState
    let stageLayout: TopologyCanvasStageLayout
    let onHoverTargetChanged: (TopologyCanvasHoverTarget?) -> Void

    var body: some View {
        GeometryReader { geometry in
            let columnWidths = resolvedColumnWidths()
            let columnGap = resolvedColumnGap(in: geometry.size, columnWidths: columnWidths)
            let points = nodePoints(in: geometry.size, columnWidths: columnWidths, columnGap: columnGap)
            let bandRegions = buildBandRegions(points: points)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for region in bandRegions {
                        let fillOpacity = hoverState.edgeOpacity(edgeID: region.edgeID, segmentID: region.segmentID)
                        let centerOpacity = min(fillOpacity + 0.18, 1)

                        context.fill(
                            region.path,
                            with: .color(region.semanticColor.fill.opacity(region.isTotal ? 0.16 * fillOpacity : 0.22 * fillOpacity))
                        )
                        context.stroke(
                            region.centerPath,
                            with: .color(region.semanticColor.fill.opacity(region.isTotal ? 0.68 * centerOpacity : 0.82 * centerOpacity)),
                            style: StrokeStyle(lineWidth: max(region.thickness * 0.36, 2), lineCap: .round)
                        )
                    }
                }

                HStack(alignment: .top, spacing: columnGap) {
                    ForEach(Array(graph.columns.enumerated()), id: \.offset) { index, column in
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(column.nodes) { node in
                                if let summary = nodeSummaries[node.id] {
                                    TopologyNodeAnchor(
                                        node: node,
                                        summary: summary,
                                        width: columnWidths[index],
                                        opacity: hoverState.nodeOpacity(nodeID: node.id),
                                        showsDetailLine: stageLayout.showsNodeDetailLine
                                    ) { isHovering in
                                        onHoverTargetChanged(isHovering ? .node(nodeID: node.id) : nil)
                                    }
                                }
                            }
                        }
                        .frame(width: columnWidths[index], alignment: .topLeading)
                        .overlay(alignment: .topLeading) {
                            if stageLayout.showsColumnRails {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(DesignTokens.topologyRail)
                                    .frame(width: columnWidths[index], height: max(geometry.size.height - 80, 120))
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if stageLayout.showsColumnHeaders {
                                Text(column.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .offset(y: -24)
                            }
                        }
                        .padding(.top, stageLayout.showsColumnHeaders ? 24 : 0)
                    }
                }
                .padding(.horizontal, stageLayout.canvasPadding)
                .padding(.top, stageLayout.showsColumnHeaders ? 18 : 6)

                ForEach(bandRegions) { region in
                    TopologyBandHoverRegion(region: region)
                        .fill(Color.white.opacity(0.001))
                        .contentShape(TopologyBandHoverRegion(region: region))
                        .onHover { isHovering in
                            onHoverTargetChanged(
                                isHovering ? .segment(edgeID: region.edgeID, segmentID: region.segmentID) : nil
                            )
                        }
                }

                if let tooltip = hoverState.tooltip {
                    TopologyTooltipCard(payload: tooltip)
                        .frame(width: 220)
                        .padding(18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
    }

    private func resolvedColumnWidths() -> [CGFloat] {
        graph.columns.enumerated().map { index, _ in
            stageLayout.width(forColumnAt: index)
        }
    }

    private func resolvedColumnGap(in size: CGSize, columnWidths: [CGFloat]) -> CGFloat {
        guard graph.columns.count > 1 else {
            return 0
        }

        let usedWidth = columnWidths.reduce(0, +)
        let availableGap = (size.width - stageLayout.canvasPadding * 2 - usedWidth) / CGFloat(graph.columns.count - 1)
        return max(stageLayout.columnSpacing, availableGap)
    }

    private func nodePoints(
        in size: CGSize,
        columnWidths: [CGFloat],
        columnGap: CGFloat
    ) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        var xCursor = stageLayout.canvasPadding

        for (columnIndex, column) in graph.columns.enumerated() {
            let centerX = xCursor + columnWidths[columnIndex] / 2

            for (nodeIndex, node) in column.nodes.enumerated() {
                let centerY = stageLayout.topInset + CGFloat(nodeIndex) * stageLayout.rowPitch + stageLayout.nodeHeight / 2
                result[node.id] = CGPoint(x: centerX, y: centerY)
            }

            xCursor += columnWidths[columnIndex] + columnGap
        }

        return result
    }

    private func buildBandRegions(points: [String: CGPoint]) -> [TopologyBandRegion] {
        let maxEmphasis = max(edges.flatMap(\.segments).map(\.emphasisValue).max() ?? 1, 1)

        var regions: [TopologyBandRegion] = []

        for edge in edges {
            guard let from = points[edge.fromNodeID], let to = points[edge.toNodeID] else {
                continue
            }

            let segmentHeights = edge.segments.map {
                TopologyBandScale.readableWidth(
                    value: $0.emphasisValue,
                    maxValue: maxEmphasis,
                    maxRenderedWidth: stageLayout.maxRenderedBandWidth,
                    minReadableWidth: stageLayout.minReadableBandWidth
                )
            }
            let totalHeight = segmentHeights.reduce(0, +) + CGFloat(max(edge.segments.count - 1, 0)) * stageLayout.bandGap
            var cursor = -totalHeight / 2

            for (index, segment) in edge.segments.enumerated() {
                let thickness = segmentHeights[index]
                let startTop = cursor
                let startBottom = cursor + thickness
                let path = bandPath(
                    from: from,
                    to: to,
                    topOffset: startTop,
                    bottomOffset: startBottom
                )
                let centerPath = centerCurve(
                    from: from,
                    to: to,
                    offset: cursor + thickness / 2
                )

                regions.append(
                    TopologyBandRegion(
                        id: segment.id,
                        edgeID: edge.id,
                        segmentID: segment.id,
                        path: path,
                        centerPath: centerPath,
                        thickness: thickness,
                        semanticColor: segment.semanticColor,
                        isTotal: segment.title == "Total"
                    )
                )

                cursor += thickness + stageLayout.bandGap
            }
        }

        return regions
    }

    private func centerCurve(from: CGPoint, to: CGPoint, offset: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: from.x, y: from.y + offset))
        path.addCurve(
            to: CGPoint(x: to.x, y: to.y + offset),
            control1: CGPoint(x: from.x + (to.x - from.x) * 0.42, y: from.y + offset),
            control2: CGPoint(x: to.x - (to.x - from.x) * 0.42, y: to.y + offset)
        )
        return path
    }

    private func bandPath(from: CGPoint, to: CGPoint, topOffset: CGFloat, bottomOffset: CGFloat) -> Path {
        let startTop = CGPoint(x: from.x, y: from.y + topOffset)
        let endTop = CGPoint(x: to.x, y: to.y + topOffset)
        let startBottom = CGPoint(x: from.x, y: from.y + bottomOffset)
        let endBottom = CGPoint(x: to.x, y: to.y + bottomOffset)

        let c1x = from.x + (to.x - from.x) * 0.42
        let c2x = to.x - (to.x - from.x) * 0.42

        var path = Path()
        path.move(to: startTop)
        path.addCurve(
            to: endTop,
            control1: CGPoint(x: c1x, y: startTop.y),
            control2: CGPoint(x: c2x, y: endTop.y)
        )
        path.addLine(to: endBottom)
        path.addCurve(
            to: startBottom,
            control1: CGPoint(x: c2x, y: endBottom.y),
            control2: CGPoint(x: c1x, y: startBottom.y)
        )
        path.closeSubpath()
        return path
    }
}

private struct TopologyBandRegion: Identifiable {
    let id: String
    let edgeID: String
    let segmentID: String
    let path: Path
    let centerPath: Path
    let thickness: CGFloat
    let semanticColor: DesignTokens.SemanticColor
    let isTotal: Bool
}

private struct TopologyBandHoverRegion: Shape {
    let region: TopologyBandRegion

    func path(in rect: CGRect) -> Path {
        region.path
    }
}

private struct TopologyNodeAnchor: View {
    let node: TopologyNode
    let summary: TopologyCanvasNodeSummary
    let width: CGFloat
    let opacity: Double
    let showsDetailLine: Bool
    let onHoverChanged: (Bool) -> Void

    private var accentColor: DesignTokens.SemanticColor {
        node.errorCount > 0 ? DesignTokens.statusColors.warning : DesignTokens.statusColors.running
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(accentColor.fill)
                    .frame(width: 8, height: 8)
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(summary.subtitle)
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(1)

            Text(summary.metricLine)
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)

            if showsDetailLine {
                Text(summary.detailLine)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width - 8, alignment: .leading)
        .background(DesignTokens.topologyAnchorFill.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(opacity)
        .onHover(perform: onHoverChanged)
    }
}

private struct TopologyTooltipCard: View {
    let payload: TopologyCanvasTooltipPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(payload.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.textSecondary)

            ForEach(payload.rows, id: \.self) { row in
                Text(row)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
        }
        .padding(12)
        .background(DesignTokens.topologyTooltipBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private func formatTopologyNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func formatTopologyPercent(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100.0)
}
