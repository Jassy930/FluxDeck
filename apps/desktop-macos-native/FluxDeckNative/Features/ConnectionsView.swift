import SwiftUI

struct ConnectionsView: View {
    let model: ConnectionsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SurfaceCard(title: "Active Gateways") {
                        nodeList(model.activeGatewayIDs, emptyText: "No active gateways")
                    }

                    SurfaceCard(title: "Active Providers") {
                        nodeList(model.activeProviderIDs, emptyText: "No active providers")
                    }
                }

                SurfaceCard(title: "Models") {
                    nodeList(model.activeModels, emptyText: "No active models")
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func nodeList(_ items: [String], emptyText: String) -> some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    StatusPill(text: item, semanticColor: DesignTokens.statusColors.running)
                }
            }
        }
    }
}
