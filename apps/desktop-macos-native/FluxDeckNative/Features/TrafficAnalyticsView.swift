import SwiftUI

struct TrafficAnalyticsView: View {
    let model: TrafficAnalyticsModel
    let isLoading: Bool
    let error: String?
    let lastRefreshedAt: Date?
    let selectedPeriod: String
    let onSelectPeriod: (String) -> Void
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                monitorHeaderCard

                if let error {
                    SurfaceCard {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DesignTokens.statusColors.error.fill)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Failed to load traffic monitor")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                        }
                    }
                }

                if isLoading && !model.hasData {
                    SurfaceCard(title: "Traffic Monitor") {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading real-time traffic statistics...")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                } else {
                    if !model.hasData {
                        emptyStateCard
                    }
                    kpiStrip
                    trendSection
                    breakdownSection

                    if !model.alerts.isEmpty {
                        alertsSection
                    }
                }
            }
            .padding(12)
        }
    }

    private var monitorHeaderCard: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Traffic Monitor")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary)

                        if let lastRefreshedAt {
                            Text("Updated \(Self.refreshFormatter.string(from: lastRefreshedAt))")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }

                    Text("Live request throughput, latency and failure distribution.")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    ForEach(Self.trafficPeriods, id: \.self) { period in
                        periodButton(period)
                    }
                }

                Button(action: onRefresh) {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        Text("Refresh")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignTokens.surfacePrimary.opacity(0.96))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isLoading)
            }
        }
    }

    private var kpiStrip: some View {
        ViewThatFits(in: .horizontal) {
            SurfaceCard {
                HStack(spacing: 0) {
                    ForEach(Array(model.kpiStripItems.enumerated()), id: \.offset) { index, item in
                        kpiStripSegment(item)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if index < model.kpiStripItems.count - 1 {
                            Rectangle()
                                .fill(DesignTokens.borderSubtle.opacity(0.85))
                                .frame(width: 1, height: 54)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(model.kpiStripItems, id: \.title) { item in
                    SurfaceCard {
                        kpiStripSegment(item)
                    }
                }
            }
        }
    }

    private var trendSection: some View {
        HStack(alignment: .top, spacing: 12) {
            SurfaceCard(title: "Traffic Trend") {
                VStack(alignment: .leading, spacing: 10) {
                    if model.trendPoints.isEmpty {
                        Text("No trend buckets available for \(selectedPeriod).")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    } else {
                        TrafficTrendChart(points: model.trendPoints)
                            .frame(height: 144)

                        HStack(spacing: 8) {
                            trendSummaryPill(
                                title: "Peak Req",
                                value: "\(peakRequestCount)"
                            )
                            trendSummaryPill(
                                title: "Peak Latency",
                                value: "\(peakLatency) ms"
                            )
                            trendSummaryPill(
                                title: "Total Errors",
                                value: "\(trendErrorCount)"
                            )
                        }
                    }
                }
            }

            SurfaceCard(title: "Routing Summary") {
                VStack(alignment: .leading, spacing: 12) {
                    StatusPill(
                        text: "Top Gateway: \(model.topGatewayID)",
                        semanticColor: DesignTokens.statusColors.running
                    )
                    StatusPill(
                        text: "Top Provider: \(model.topProviderID)",
                        semanticColor: DesignTokens.statusColors.warning
                    )
                    StatusPill(
                        text: "Top Model: \(model.topModelName)",
                        semanticColor: DesignTokens.statusColors.inactive
                    )

                    Divider()
                        .overlay(DesignTokens.borderSubtle)

                    metricRow(label: "Requests", value: "\(model.totalRequests)")
                    metricRow(label: "Errors", value: "\(model.errorCount)")
                    metricRow(label: "Period", value: selectedPeriod.uppercased())
                }
            }
            .frame(width: 248)
        }
    }

    private var breakdownSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            breakdownCard(title: "By Gateway", rows: model.compactGatewayBreakdown)
            breakdownCard(title: "By Provider", rows: model.compactProviderBreakdown)
            breakdownCard(title: "By Model", rows: model.compactModelBreakdown)
        }
    }

    private var alertsSection: some View {
        SurfaceCard(title: "Alerts") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(model.alerts.enumerated()), id: \.offset) { _, alert in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(alertSemanticColor(alert.level).fill)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                            Text(alert.detail)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }

                        Spacer()

                        Text(alert.level.rawValue.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(alertSemanticColor(alert.level).fill)
                    }

                    if alert.title != model.alerts.last?.title {
                        Divider()
                            .overlay(DesignTokens.borderSubtle.opacity(0.8))
                    }
                }
            }
        }
    }

    private var emptyStateCard: some View {
        SurfaceCard(title: "Traffic Monitor") {
            VStack(alignment: .leading, spacing: 8) {
                Text("No traffic recorded for \(selectedPeriod).")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Once gateways start serving requests, this page will show throughput, latency, token usage and error alerts.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
    }

    private var peakRequestCount: Int {
        model.trendPoints.map(\.requestCount).max() ?? 0
    }

    private var peakLatency: Int {
        model.trendPoints.map(\.avgLatency).max() ?? 0
    }

    private var trendErrorCount: Int {
        model.trendPoints.map(\.errorCount).reduce(0, +)
    }

    private func periodButton(_ period: String) -> some View {
        Button {
            onSelectPeriod(period)
        } label: {
            Text(period.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selectedPeriod == period ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(selectedPeriod == period ? DesignTokens.surfaceSecondary : DesignTokens.surfacePrimary.opacity(0.9))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(selectedPeriod == period ? DesignTokens.textPrimary.opacity(0.18) : DesignTokens.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func kpiStripSegment(_ item: TrafficKpiStripItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)
            Text(item.value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    private func trendSummaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.surfacePrimary.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.borderSubtle, lineWidth: 1)
        )
    }

    private func breakdownCard(title: String, rows: [TrafficBreakdownRow]) -> some View {
        SurfaceCard(title: title) {
            if rows.isEmpty {
                Text("No dimension data in this period.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows, id: \.title) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                            HStack {
                                Text(row.requestCountText)
                                Spacer()
                                Text(row.latencyText)
                            }
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)

                            HStack {
                                Text(row.errorText)
                                Spacer()
                                Text(row.tokenText)
                            }
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)
                        }

                        if row.title != rows.last?.title {
                            Divider()
                                .overlay(DesignTokens.borderSubtle.opacity(0.8))
                        }
                    }
                }
            }
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }

    private func alertSemanticColor(_ level: TrafficAlertLevel) -> DesignTokens.SemanticColor {
        switch level {
        case .info:
            return DesignTokens.statusColors.inactive
        case .warning:
            return DesignTokens.statusColors.warning
        case .error:
            return DesignTokens.statusColors.error
        }
    }

    private static let trafficPeriods = ["1h", "6h", "24h"]
    private static let refreshFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct TrafficTrendChart: View {
    let points: [AdminStatsTrendPoint]

    var body: some View {
        GeometryReader { geometry in
            let frame = CGRect(origin: .zero, size: geometry.size)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.88))

                Path { path in
                    let y = frame.height * 0.5
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: frame.width, y: y))
                }
                .stroke(DesignTokens.borderSubtle.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if requestPath(in: frame).isEmpty == false {
                    requestPath(in: frame)
                        .stroke(DesignTokens.statusColors.running.fill, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                if latencyPath(in: frame).isEmpty == false {
                    latencyPath(in: frame)
                        .stroke(DesignTokens.statusColors.warning.fill, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func requestPath(in rect: CGRect) -> Path {
        linePath(
            rect: rect,
            values: points.map { Double($0.requestCount) }
        )
    }

    private func latencyPath(in rect: CGRect) -> Path {
        linePath(
            rect: rect,
            values: points.map { Double($0.avgLatency) }
        )
    }

    private func linePath(rect: CGRect, values: [Double]) -> Path {
        guard values.count > 1 else {
            return Path()
        }

        let maxValue = max(values.max() ?? 1, 1)
        let minValue = min(values.min() ?? 0, maxValue)
        let range = max(maxValue - minValue, 1)
        let stepX = rect.width / CGFloat(max(values.count - 1, 1))

        return Path { path in
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = (value - minValue) / range
                let y = rect.height - CGFloat(normalized) * max(rect.height - 16, 1) - 8
                let point = CGPoint(x: x, y: y)

                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }
}
