import SwiftUI

struct TopologyCanvasView: View {
    let graph: TopologyGraph

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SurfaceCard(title: "Topology Canvas") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Entrypoints · Gateways · Providers")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)

                        TopologyCanvas(graph: graph)
                            .frame(height: canvasHeight)
                    }
                }

                SurfaceCard(title: "Route Summary") {
                    if graph.edges.isEmpty {
                        Text("No active routes yet.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(graph.edges) { edge in
                                HStack(spacing: 10) {
                                    StatusPill(text: edgeTitle(edge.fromNodeID), semanticColor: DesignTokens.statusColors.running)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(DesignTokens.textSecondary)
                                    StatusPill(text: edgeTitle(edge.toNodeID), semanticColor: DesignTokens.statusColors.warning)
                                    Spacer()
                                    Text("\(edge.requestCount) req")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var canvasHeight: CGFloat {
        CGFloat(max(graph.columns.map { $0.nodes.count }.max() ?? 1, 1)) * 76 + 56
    }

    private func edgeTitle(_ id: String) -> String {
        graph.columns
            .flatMap(\ .nodes)
            .first(where: { $0.id == id })?
            .title ?? id
    }
}

private struct TopologyCanvas: View {
    let graph: TopologyGraph

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    let points = nodePoints(in: size)

                    for edge in graph.edges {
                        guard let from = points[edge.fromNodeID], let to = points[edge.toNodeID] else {
                            continue
                        }

                        var path = Path()
                        path.move(to: from)
                        path.addCurve(
                            to: to,
                            control1: CGPoint(x: (from.x + to.x) / 2, y: from.y),
                            control2: CGPoint(x: (from.x + to.x) / 2, y: to.y)
                        )

                        context.stroke(
                            path,
                            with: .color(DesignTokens.statusColors.running.fill.opacity(0.55)),
                            style: StrokeStyle(lineWidth: CGFloat(min(max(edge.requestCount, 2), 8)), lineCap: .round)
                        )
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    ForEach(Array(graph.columns.enumerated()), id: \.offset) { index, column in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(column.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.textSecondary)

                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(column.nodes) { node in
                                    TopologyNodeCard(node: node)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func nodePoints(in size: CGSize) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        let columnWidth = size.width / CGFloat(max(graph.columns.count, 1))

        for (columnIndex, column) in graph.columns.enumerated() {
            let centerX = columnWidth * (CGFloat(columnIndex) + 0.5)

            for (nodeIndex, node) in column.nodes.enumerated() {
                let centerY = 52 + CGFloat(nodeIndex) * 72 + 28
                result[node.id] = CGPoint(x: centerX, y: centerY)
            }
        }

        return result
    }
}

private struct TopologyNodeCard: View {
    let node: TopologyNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
            Text(node.subtitle)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceSecondary.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
