import SwiftUI

struct TrafficAnalyticsView: View {
    let model: TrafficAnalyticsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SurfaceCard(title: "Traffic KPIs") {
                        VStack(alignment: .leading, spacing: 14) {
                            metricRow(label: "Total Requests", value: "\(model.totalRequests)")
                            metricRow(label: "Errors", value: "\(model.errorCount)")
                            metricRow(label: "Average Latency", value: model.averageLatencyText)
                        }
                    }

                    SurfaceCard(title: "Distribution") {
                        VStack(alignment: .leading, spacing: 12) {
                            StatusPill(text: "Top Gateway: \(model.topGatewayID)", semanticColor: DesignTokens.statusColors.running)
                            StatusPill(text: "Top Provider: \(model.topProviderID)", semanticColor: DesignTokens.statusColors.warning)
                            metricRow(label: "Successful", value: "\(model.successCount)")
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }
}
