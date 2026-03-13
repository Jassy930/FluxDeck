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
            SurfaceCard(title: "Token Trend by Model") {
                VStack(alignment: .leading, spacing: 10) {
                    if model.tokenTrendBuckets.isEmpty {
                        Text("No trend buckets available for \(selectedPeriod).")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    } else {
                        let renderableLines = buildTrafficTrendRenderableLines(
                            series: model.tokenTrendSeries,
                            buckets: model.tokenTrendBuckets
                        )
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(renderableLines.enumerated()), id: \.element.name) { index, line in
                                    tokenTrendLegendItem(
                                        title: line.name,
                                        color: tokenTrendRenderableColor(for: line, index: index)
                                    )
                                }
                            }
                            .padding(.bottom, 2)
                        }

                        TrafficTrendChart(
                            series: model.tokenTrendSeries,
                            buckets: model.tokenTrendBuckets
                        )
                        .frame(height: 196)

                        HStack(spacing: 8) {
                            ForEach(model.tokenTrendSummaryItems, id: \.title) { item in
                                trendSummaryPill(title: item.title, value: item.value)
                            }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)
            Text(item.value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if item.detailRows.isEmpty {
                Text("No detail in this period")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(item.detailRows, id: \.label) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .lineLimit(1)

                            Spacer(minLength: 6)

                            Text(row.value)
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.textPrimary.opacity(0.94))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
            }
        }
    }

    private func tokenTrendLegendItem(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(DesignTokens.surfacePrimary.opacity(0.92))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
        )
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
    let series: [TrafficTokenTrendSeries]
    let buckets: [TrafficTokenTrendBucket]
    @State private var hoveredBucketIndex: Int?

    private var renderableLines: [TrafficTrendRenderableLine] {
        buildTrafficTrendRenderableLines(series: series, buckets: buckets)
    }

    var body: some View {
        GeometryReader { geometry in
            let frame = CGRect(origin: .zero, size: geometry.size)
            let maxTotal = max(buckets.map(\.totalTokens).max() ?? 0, 1)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.88))

                ForEach(0..<3, id: \.self) { gridIndex in
                    Path { path in
                        let ratio = CGFloat(gridIndex + 1) / 4
                        let y = frame.height - ratio * frame.height
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: frame.width, y: y))
                    }
                    .stroke(DesignTokens.borderSubtle.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                ForEach(Array(series.enumerated()), id: \.element.modelName) { index, _ in
                    stackedAreaPath(for: index, in: frame, maxTotal: maxTotal)
                        .fill(tokenTrendModelColor(for: index).opacity(0.12))
                }

                ForEach(Array(renderableLines.enumerated()), id: \.element.name) { index, line in
                    rawLinePath(values: line.values, in: frame, maxTotal: maxTotal)
                        .stroke(
                            tokenTrendRenderableColor(for: line, index: index),
                            style: StrokeStyle(
                                lineWidth: line.style == .total ? 3.2 : 1.8,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .shadow(
                            color: line.style == .total ? totalTokenTrendColor().opacity(0.26) : .clear,
                            radius: line.style == .total ? 8 : 0
                        )
                }

                if let hoveredBucketIndex, buckets.indices.contains(hoveredBucketIndex) {
                    let x = xPosition(for: hoveredBucketIndex, in: frame)

                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: frame.height))
                    }
                    .stroke(DesignTokens.textPrimary.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    ForEach(Array(renderableLines.enumerated()), id: \.element.name) { index, line in
                        let value = line.values[hoveredBucketIndex]
                        let point = CGPoint(
                            x: x,
                            y: yPosition(for: value, maxTotal: maxTotal, in: frame)
                        )
                        Circle()
                            .fill(tokenTrendRenderableColor(for: line, index: index))
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .stroke(DesignTokens.surfacePrimary, lineWidth: 2)
                            )
                            .position(point)
                    }

                    tooltipView(for: hoveredBucketIndex)
                        .position(
                            x: tooltipXPosition(for: hoveredBucketIndex, in: frame),
                            y: 54
                        )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoveredBucketIndex = bucketIndex(for: location.x, in: frame)
                case .ended:
                    hoveredBucketIndex = nil
                }
            }
        }
    }

    private func stackedAreaPath(for seriesIndex: Int, in rect: CGRect, maxTotal: Int) -> Path {
        let lowerValues = cumulativeValues(upTo: max(seriesIndex - 1, -1))
        let upperValues = cumulativeValues(upTo: seriesIndex)
        guard upperValues.count > 1 else {
            return Path()
        }

        return Path { path in
            for index in upperValues.indices {
                let point = CGPoint(
                    x: xPosition(for: index, in: rect),
                    y: yPosition(for: upperValues[index], maxTotal: maxTotal, in: rect)
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            for index in lowerValues.indices.reversed() {
                path.addLine(
                    to: CGPoint(
                        x: xPosition(for: index, in: rect),
                        y: yPosition(for: lowerValues[index], maxTotal: maxTotal, in: rect)
                    )
                )
            }

            path.closeSubpath()
        }
    }

    private func rawLinePath(values: [Int], in rect: CGRect, maxTotal: Int) -> Path {
        guard values.count > 1 else {
            return Path()
        }

        return Path { path in
            for index in values.indices {
                let point = CGPoint(
                    x: xPosition(for: index, in: rect),
                    y: yPosition(for: values[index], maxTotal: maxTotal, in: rect)
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func cumulativeValues(upTo seriesIndex: Int) -> [Int] {
        guard !series.isEmpty else {
            return []
        }
        guard seriesIndex >= 0 else {
            return Array(repeating: 0, count: buckets.count)
        }

        var cumulative = Array(repeating: 0, count: buckets.count)
        for currentIndex in 0...min(seriesIndex, series.count - 1) {
            for bucketIndex in cumulative.indices {
                cumulative[bucketIndex] += series[currentIndex].bucketValues[bucketIndex]
            }
        }
        return cumulative
    }

    private func xPosition(for bucketIndex: Int, in rect: CGRect) -> CGFloat {
        guard buckets.count > 1 else {
            return rect.midX
        }
        let step = rect.width / CGFloat(max(buckets.count - 1, 1))
        return CGFloat(bucketIndex) * step
    }

    private func yPosition(for value: Int, maxTotal: Int, in rect: CGRect) -> CGFloat {
        let normalized = Double(value) / Double(max(maxTotal, 1))
        return rect.height - CGFloat(normalized) * max(rect.height - 16, 1) - 8
    }

    private func bucketIndex(for x: CGFloat, in rect: CGRect) -> Int {
        guard buckets.count > 1 else {
            return 0
        }
        let clampedX = min(max(x, 0), rect.width)
        let ratio = clampedX / max(rect.width, 1)
        return min(max(Int(round(ratio * CGFloat(buckets.count - 1))), 0), buckets.count - 1)
    }

    private func tooltipXPosition(for bucketIndex: Int, in rect: CGRect) -> CGFloat {
        let preferredX = xPosition(for: bucketIndex, in: rect)
        return min(max(preferredX, 118), rect.width - 118)
    }

    @ViewBuilder
    private func tooltipView(for bucketIndex: Int) -> some View {
        let bucket = buckets[bucketIndex]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.timestamp)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                if bucket.errorCount > 0 {
                    Text("\(bucket.errorCount) err")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.statusColors.error.fill)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Total Tokens")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Text(formatTrendInteger(bucket.totalTokens))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            Divider()
                .overlay(DesignTokens.borderSubtle.opacity(0.8))

            ForEach(bucket.rows, id: \.modelName) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tokenTrendModelColor(for: series.firstIndex(where: { $0.modelName == row.modelName }) ?? 0))
                            .frame(width: 6, height: 6)
                        Text(row.modelName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DesignTokens.textSecondary)
                        Spacer()
                        Text(formatTrendInteger(row.totalTokens))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                    }

                    Text("I \(formatTrendInteger(row.inputTokens))  O \(formatTrendInteger(row.outputTokens))  C \(formatTrendInteger(row.cachedTokens))")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary.opacity(0.92))
                }
            }
        }
        .padding(10)
        .frame(width: 236)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.surfaceSecondary.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
    }
}

enum TrafficTrendRenderableLineStyle: Equatable {
    case total
    case model
}

struct TrafficTrendRenderableLine: Equatable {
    let name: String
    let values: [Int]
    let style: TrafficTrendRenderableLineStyle
}

func buildTrafficTrendRenderableLines(
    series: [TrafficTokenTrendSeries],
    buckets: [TrafficTokenTrendBucket]
) -> [TrafficTrendRenderableLine] {
    [
        TrafficTrendRenderableLine(
            name: "Total Tokens",
            values: buckets.map(\.totalTokens),
            style: .total
        )
    ] + series.map {
        TrafficTrendRenderableLine(
            name: $0.modelName,
            values: $0.bucketValues,
            style: .model
        )
    }
}

private func totalTokenTrendColor() -> Color {
    Color(red: 0.89, green: 0.96, blue: 1.0)
}

private func tokenTrendModelColor(for index: Int) -> Color {
    let palette: [Color] = [
        DesignTokens.statusColors.running.fill,
        Color(red: 0.22, green: 0.82, blue: 0.88),
        DesignTokens.statusColors.warning.fill,
        Color(red: 0.39, green: 0.56, blue: 1.00),
        Color(red: 0.47, green: 0.53, blue: 0.63)
    ]
    return palette[index % palette.count]
}

private func tokenTrendRenderableColor(
    for line: TrafficTrendRenderableLine,
    index: Int
) -> Color {
    switch line.style {
    case .total:
        return totalTokenTrendColor()
    case .model:
        return tokenTrendModelColor(for: max(index - 1, 0))
    }
}

private func formatTrendInteger(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}
