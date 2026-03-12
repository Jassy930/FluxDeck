import SwiftUI

struct ContentView: View {
    @AppStorage("fluxdeck.native.admin_base_url") private var persistedAdminBaseURL = defaultAdminBaseURL
    @State private var providers: [AdminProvider] = []
    @State private var gateways: [AdminGateway] = []
    @State private var dashboardLogs: [AdminLog] = []
    @State private var logsPageItems: [AdminLog] = []
    @State private var logsPageCursor: AdminLogCursor?
    @State private var logsPageHasMore = false
    @State private var isLogsPageLoading = false
    @State private var trafficOverview: AdminStatsOverview?
    @State private var trafficTrend: AdminStatsTrend?
    @State private var selectedTrafficPeriod = Self.defaultTrafficPeriod
    @State private var isTrafficLoading = false
    @State private var trafficError: String?
    @State private var trafficLastRefreshedAt: Date?
    @State private var selectedSection: SidebarSection? = .overview
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var loadError: String?
    @State private var operationNotice: String?
    @State private var lastRefreshedAt: Date?
    @State private var isProviderSheetPresented = false
    @State private var editingProvider: AdminProvider?
    @State private var isGatewaySheetPresented = false
    @State private var editingGateway: AdminGateway?
    @State private var providerPendingDelete: AdminProvider?
    @State private var gatewayPendingDelete: AdminGateway?
    @State private var selectedLogGateway = Self.logFilterAll
    @State private var selectedLogProvider = Self.logFilterAll
    @State private var selectedLogStatus = Self.logFilterAll
    @State private var logErrorsOnly = false
    @State private var adminBaseURLInput = defaultAdminBaseURL
    @State private var settingsError: String?
    @State private var selectedMode: AppMode = .rule

    private var shellStatusSummary: ShellStatusSummary {
        ShellStatusSummary.make(
            isLoading: isLoading,
            loadError: loadError,
            gateways: gateways
        )
    }

    private var client: AdminApiClient {
        let url = normalizedAdminBaseURL(persistedAdminBaseURL) ?? URL(string: defaultAdminBaseURL)!
        return AdminApiClient(baseURL: url)
    }

    private var logsTaskKey: String {
        [
            selectedSection?.rawValue ?? "none",
            selectedLogGateway,
            selectedLogProvider,
            selectedLogStatus,
            logErrorsOnly ? "errors" : "all",
            persistedAdminBaseURL
        ].joined(separator: "|")
    }

    private var trafficTaskKey: String {
        [
            selectedSection?.rawValue ?? "none",
            selectedTrafficPeriod,
            persistedAdminBaseURL
        ].joined(separator: "|")
    }

    var body: some View {
        AppShellView(
            title: selectedSection?.rawValue ?? SidebarSection.overview.rawValue,
            groups: SidebarGroup.defaultGroups,
            selectedSection: $selectedSection,
            selectedMode: $selectedMode,
            statusSummary: shellStatusSummary
        ) {
            VStack(spacing: 0) {
                headerBar
                Divider()
                    .overlay(DesignTokens.borderSubtle)
                detailView(for: selectedSection ?? .overview)
                    .frame(maxWidth: 1280, maxHeight: .infinity, alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .frame(minWidth: 920, minHeight: 560)
        }
        .task {
            await refreshAll()
        }
        .task(id: logsTaskKey) {
            guard selectedSection == .logs else {
                return
            }
            await loadLogsPage(reset: true)
        }
        .task(id: trafficTaskKey) {
            guard selectedSection == .traffic else {
                return
            }
            await loadTrafficStats()
        }
        .onAppear {
            selectedSection = selectedSection ?? .overview
            adminBaseURLInput = persistedAdminBaseURL
        }
        .sheet(isPresented: $isProviderSheetPresented) {
            ProviderFormSheet(
                mode: .create,
                isSubmitting: isSubmitting,
                onCreate: { input in
                    await createProvider(input)
                },
                onUpdate: { providerID, input in
                    await updateProvider(id: providerID, input: input)
                }
            )
        }
        .sheet(item: $editingProvider) { provider in
            ProviderFormSheet(
                mode: .edit(provider),
                isSubmitting: isSubmitting,
                onCreate: { input in
                    await createProvider(input)
                },
                onUpdate: { providerID, input in
                    await updateProvider(id: providerID, input: input)
                }
            )
        }
        .sheet(isPresented: $isGatewaySheetPresented) {
            GatewayFormSheet(
                mode: .create,
                providers: providers,
                isSubmitting: isSubmitting,
                onCreate: { input in
                    await createGateway(input)
                },
                onUpdate: { gatewayID, input in
                    await updateGateway(id: gatewayID, input: input)
                }
            )
        }
        .sheet(item: $editingGateway) { gateway in
            GatewayFormSheet(
                mode: .edit(gateway),
                providers: providers,
                isSubmitting: isSubmitting,
                onCreate: { input in
                    await createGateway(input)
                },
                onUpdate: { gatewayID, input in
                    await updateGateway(id: gatewayID, input: input)
                }
            )
        }
        .alert(
            "Delete Provider?",
            isPresented: Binding(
                get: { providerPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        providerPendingDelete = nil
                    }
                }
            ),
            actions: {
                Button("Delete", role: .destructive) {
                    guard let provider = providerPendingDelete else {
                        return
                    }
                    providerPendingDelete = nil
                    Task {
                        await deleteProvider(provider)
                    }
                }
                Button("Cancel", role: .cancel) {
                    providerPendingDelete = nil
                }
            },
            message: {
                let providerID = providerPendingDelete?.id ?? "provider"
                Text("Delete `\(providerID)` permanently. If any Gateway still references this Provider, the operation will fail.")
            }
        )
        .alert(
            "Delete Gateway?",
            isPresented: Binding(
                get: { gatewayPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        gatewayPendingDelete = nil
                    }
                }
            ),
            actions: {
                Button("Delete", role: .destructive) {
                    guard let gateway = gatewayPendingDelete else {
                        return
                    }
                    gatewayPendingDelete = nil
                    Task {
                        await deleteGateway(gateway)
                    }
                }
                Button("Cancel", role: .cancel) {
                    gatewayPendingDelete = nil
                }
            },
            message: {
                let gatewayID = gatewayPendingDelete?.id ?? "gateway"
                Text("Delete `\(gatewayID)` permanently. This does not require deleting its Provider first. If this Gateway is running, the system will stop it before deletion.")
            }
        )
    }

    @ViewBuilder
    private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .overview:
            OverviewDashboardView(
                model: OverviewDashboardModel.make(
                    providers: providers,
                    gateways: gateways,
                    logs: dashboardLogs
                ),
                isLoading: isLoading,
                logs: recentLogs(dashboardLogs),
                onOpenAllLogs: {
                    selectedSection = .logs
                    clearLogFilters()
                },
                onDrillDownLog: { log in
                    selectedSection = .logs
                    selectedLogGateway = log.gatewayID
                    selectedLogProvider = log.providerID
                    selectedLogStatus = Self.logFilterAll
                    logErrorsOnly = false
                }
            )
        case .providers:
            ProviderListView(
                providers: providers,
                isLoading: isLoading,
                isSubmitting: isSubmitting,
                error: loadError,
                onCreate: { isProviderSheetPresented = true },
                onConfigure: { provider in
                    editingProvider = provider
                },
                onToggleEnabled: { provider in
                    Task {
                        let input = UpdateProviderInput(
                            name: provider.name,
                            kind: provider.kind,
                            baseURL: provider.baseURL,
                            apiKey: provider.apiKey,
                            models: provider.models,
                            enabled: !provider.enabled
                        )
                        await updateProvider(id: provider.id, input: input)
                    }
                },
                onDelete: { provider in
                    providerPendingDelete = provider
                }
            )
        case .gateways:
            GatewayListView(
                gateways: gateways,
                isLoading: isLoading,
                isSubmitting: isSubmitting,
                error: loadError,
                notice: operationNotice,
                onCreate: { isGatewaySheetPresented = true },
                onConfigure: { gateway in
                    editingGateway = gateway
                },
                onToggleRuntime: { gateway in
                    Task {
                        await toggleGatewayRuntime(gateway)
                    }
                },
                onDelete: { gateway in
                    gatewayPendingDelete = gateway
                }
            )
        case .logs:
            LogsWorkbenchView(
                logs: logsPageItems,
                hasMore: logsPageHasMore,
                isLoading: isLogsPageLoading && logsPageItems.isEmpty,
                isLoadingMore: isLogsPageLoading && !logsPageItems.isEmpty,
                error: loadError,
                gatewayOptions: gatewayLogOptions,
                providerOptions: providerLogOptions,
                statusOptions: statusLogOptions,
                selectedGateway: $selectedLogGateway,
                selectedProvider: $selectedLogProvider,
                selectedStatus: $selectedLogStatus,
                errorsOnly: $logErrorsOnly,
                onClearFilters: clearLogFilters,
                onLoadMore: {
                    Task {
                        await loadLogsPage(reset: false)
                    }
                }
            )
        case .traffic:
            TrafficAnalyticsView(
                model: TrafficAnalyticsModel.make(
                    overview: trafficOverview,
                    trend: trafficTrend,
                    selectedPeriod: selectedTrafficPeriod
                ),
                isLoading: isTrafficLoading,
                error: trafficError,
                lastRefreshedAt: trafficLastRefreshedAt,
                selectedPeriod: selectedTrafficPeriod,
                onSelectPeriod: { period in
                    selectedTrafficPeriod = period
                },
                onRefresh: {
                    Task {
                        await loadTrafficStats()
                    }
                }
            )
        case .connections:
            ConnectionsView(
                model: ConnectionsModel.make(logs: dashboardLogs)
            )
        case .topology:
            TopologyCanvasView(
                graph: TopologyGraph.make(
                    gateways: gateways,
                    providers: providers,
                    logs: dashboardLogs
                )
            )
        case .routeMap:
            PlaceholderDetailView(
                title: "Route Map",
                systemImage: SidebarSection.routeMap.icon,
                message: "Route map visualization will be added in the redesigned native workbench."
            )
        case .settings:
            SettingsPanelView(
                adminURLInput: $adminBaseURLInput,
                resolvedAdminURL: client.displayBaseURL,
                isBusy: isLoading || isSubmitting,
                errorMessage: settingsError,
                model: SettingsPanelModel.make(
                    adminBaseURL: client.displayBaseURL,
                    isLoading: isLoading || isSubmitting,
                    hasError: settingsError != nil
                ),
                onApply: { await applyAdminBaseURL() },
                onReset: {
                    adminBaseURLInput = defaultAdminBaseURL
                    settingsError = nil
                }
            )
        }
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("Admin")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(DesignTokens.textSecondary)

                    Text(client.displayBaseURL)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.92))
                        .lineLimit(1)
                }

                Spacer()

                if let lastRefreshedAt {
                    Text("Last refresh: \(Self.refreshFormatter.string(from: lastRefreshedAt))")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                ConnectionBadge(isLoading: isLoading, hasError: loadError != nil, hasSuccessfulSync: lastRefreshedAt != nil)

                Button {
                    Task {
                        await refreshAll()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isLoading || isSubmitting {
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignTokens.surfaceSecondary.opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DesignTokens.borderSubtle.opacity(0.45), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isLoading || isSubmitting)
                .keyboardShortcut("r", modifiers: .command)
            }

            if let loadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(loadError)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("Retry") {
                        Task {
                            await refreshAll()
                        }
                    }
                    .buttonStyle(.link)
                    .focusable(false)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Refresh error: \(loadError)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @MainActor
    private func refreshAll() async {
        isLoading = true

        do {
            async let providerTask = client.fetchProviders()
            async let gatewayTask = client.fetchGateways()
            async let dashboardLogsTask = client.fetchDashboardLogs(limit: Self.dashboardLogLimit)

            let nextProviders = try await providerTask
            let nextGateways = try await gatewayTask
            let nextDashboardLogs = try await dashboardLogsTask

            providers = nextProviders
            gateways = nextGateways
            dashboardLogs = nextDashboardLogs
            normalizeLogFilters()
            loadError = nil
            lastRefreshedAt = Date()
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false

        if selectedSection == .logs {
            await loadLogsPage(reset: true)
        }
        if selectedSection == .traffic {
            await loadTrafficStats()
        }
    }

    @MainActor
    private func createProvider(_ input: CreateProviderInput) async {
        isSubmitting = true
        operationNotice = nil

        do {
            _ = try await client.createProvider(input)
            isProviderSheetPresented = false
            loadError = nil
            await refreshAll()
        } catch {
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func updateProvider(id: String, input: UpdateProviderInput) async {
        isSubmitting = true
        operationNotice = nil

        do {
            _ = try await client.updateProvider(id: id, input: input)
            editingProvider = nil
            loadError = nil
            await refreshAll()
        } catch {
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func deleteProvider(_ provider: AdminProvider) async {
        isSubmitting = true
        operationNotice = nil

        do {
            _ = try await client.deleteProvider(id: provider.id)
            if editingProvider?.id == provider.id {
                editingProvider = nil
            }
            loadError = nil
            operationNotice = "Provider 已删除。"
            await refreshAll()
        } catch {
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func createGateway(_ input: CreateGatewayInput) async {
        isSubmitting = true
        operationNotice = nil

        do {
            _ = try await client.createGateway(input)
            isGatewaySheetPresented = false
            loadError = nil
            await refreshAll()
        } catch {
            operationNotice = nil
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func updateGateway(id: String, input: UpdateGatewayInput) async {
        isSubmitting = true

        do {
            let result = try await client.updateGateway(id: id, input: input)
            editingGateway = nil
            loadError = nil
            operationNotice = gatewayUpdateNoticeText(for: result)
            await refreshAll()
        } catch {
            operationNotice = nil
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func deleteGateway(_ gateway: AdminGateway) async {
        isSubmitting = true
        operationNotice = nil

        do {
            let result = try await client.deleteGateway(id: gateway.id)
            if editingGateway?.id == gateway.id {
                editingGateway = nil
            }
            loadError = nil
            operationNotice = gatewayDeleteNoticeText(for: result)
            await refreshAll()
        } catch {
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func toggleGatewayRuntime(_ gateway: AdminGateway) async {
        isSubmitting = true
        operationNotice = nil

        do {
            if runtimeCategory(for: gateway) == .running {
                try await client.stopGateway(id: gateway.id)
            } else {
                try await client.startGateway(id: gateway.id)
            }
            loadError = nil
            await refreshAll()
        } catch {
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    private static let refreshFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let logFilterAll = "All"
    private static let dashboardLogLimit = 20
    private static let logsPageLimit = 50
    private static let defaultTrafficPeriod = "1h"
    private static let statusFilterOptions = [logFilterAll, "200", "400", "401", "403", "404", "429", "500", "502", "503"]

    private var gatewayLogOptions: [String] {
        [Self.logFilterAll] + providersAndGatewaysIDs(gateways.map(\.id))
    }

    private var providerLogOptions: [String] {
        [Self.logFilterAll] + providersAndGatewaysIDs(providers.map(\.id))
    }

    private var statusLogOptions: [String] {
        Self.statusFilterOptions
    }

    private var selectedGatewayFilter: String? {
        selectedLogGateway == Self.logFilterAll ? nil : selectedLogGateway
    }

    private var selectedProviderFilter: String? {
        selectedLogProvider == Self.logFilterAll ? nil : selectedLogProvider
    }

    private var selectedStatusFilter: Int? {
        selectedLogStatus == Self.logFilterAll ? nil : Int(selectedLogStatus)
    }

    private func normalizeLogFilters() {
        if !gatewayLogOptions.contains(selectedLogGateway) {
            selectedLogGateway = Self.logFilterAll
        }
        if !providerLogOptions.contains(selectedLogProvider) {
            selectedLogProvider = Self.logFilterAll
        }
        if !statusLogOptions.contains(selectedLogStatus) {
            selectedLogStatus = Self.logFilterAll
        }
    }

    private func clearLogFilters() {
        selectedLogGateway = Self.logFilterAll
        selectedLogProvider = Self.logFilterAll
        selectedLogStatus = Self.logFilterAll
        logErrorsOnly = false
    }

    @MainActor
    private func loadTrafficStats() async {
        guard selectedSection == .traffic else {
            return
        }
        guard !isTrafficLoading else {
            return
        }

        isTrafficLoading = true
        defer { isTrafficLoading = false }

        do {
            async let overviewTask = client.fetchStatsOverview(period: selectedTrafficPeriod)
            async let trendTask = client.fetchStatsTrend(
                period: selectedTrafficPeriod,
                interval: trafficTrendInterval(for: selectedTrafficPeriod)
            )

            trafficOverview = try await overviewTask
            trafficTrend = try await trendTask
            trafficError = nil
            trafficLastRefreshedAt = Date()
        } catch {
            trafficError = error.localizedDescription
        }
    }

    @MainActor
    private func loadLogsPage(reset: Bool) async {
        guard selectedSection == .logs else {
            return
        }
        guard !isLogsPageLoading else {
            return
        }
        guard reset || logsPageHasMore || logsPageItems.isEmpty else {
            return
        }

        isLogsPageLoading = true
        defer { isLogsPageLoading = false }

        do {
            let page = try await client.fetchLogsPage(
                limit: Self.logsPageLimit,
                cursor: reset ? nil : logsPageCursor,
                gatewayID: selectedGatewayFilter,
                providerID: selectedProviderFilter,
                statusCode: selectedStatusFilter,
                errorsOnly: logErrorsOnly
            )

            if reset {
                logsPageItems = page.items
            } else {
                logsPageItems.append(contentsOf: page.items)
            }
            logsPageCursor = page.nextCursor
            logsPageHasMore = page.hasMore
            loadError = nil
        } catch {
            if reset {
                logsPageItems = []
                logsPageCursor = nil
                logsPageHasMore = false
            }
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func applyAdminBaseURL() async {
        guard let normalizedURL = normalizedAdminBaseURL(adminBaseURLInput) else {
            settingsError = "Admin URL 仅支持 http/https，例如 http://127.0.0.1:7777。"
            return
        }

        let normalizedValue = normalizedURL.absoluteString
        persistedAdminBaseURL = normalizedValue
        adminBaseURLInput = normalizedValue
        settingsError = nil
        await refreshAll()
    }

    private func trafficTrendInterval(for period: String) -> String {
        switch period {
        case "24h":
            return "1h"
        case "6h":
            return "15m"
        default:
            return "5m"
        }
    }
}


private func providersAndGatewaysIDs(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

private struct OverviewView: View {
    let metrics: DashboardMetrics
    let isLoading: Bool
    let logs: [AdminLog]
    let onOpenAllLogs: () -> Void
    let onDrillDownLog: (AdminLog) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Overview")
                    .font(.title2)
                    .fontWeight(.semibold)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
                    spacing: 12
                ) {
                    MetricCard(title: "Providers", value: "\(metrics.providerCount)", tint: .blue)
                    MetricCard(title: "Gateways", value: "\(metrics.gatewayCount)", tint: .indigo)
                    MetricCard(title: "Running", value: "\(metrics.runningGatewayCount)", tint: .green)
                    MetricCard(title: "Errors", value: "\(metrics.errorGatewayCount)", tint: .red)
                }

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing dashboard data...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent Logs")
                            .font(.headline)
                        Spacer()
                        Button("Open Logs") {
                            onOpenAllLogs()
                        }
                        .buttonStyle(.link)
                        .focusable(false)
                    }

                    if logs.isEmpty {
                        Text("No recent logs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(logs) { log in
                            Button {
                                onDrillDownLog(log)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(log.requestID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 180, alignment: .leading)

                                    Text("\(log.gatewayID) -> \(log.providerID)")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(log.statusCode)")
                                        .font(.caption.bold())
                                        .foregroundStyle(color(for: log.statusCode))
                                        .frame(width: 40, alignment: .trailing)

                                    Text("\(log.latencyMs) ms")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 68, alignment: .trailing)

                                    Text(log.createdAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 170, alignment: .trailing)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .accessibilityLabel("Open log \(log.requestID)")
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(for statusCode: Int) -> Color {
        switch statusCode {
        case 200..<300:
            return .green
        case 400..<500:
            return .orange
        case 500..<600:
            return .red
        default:
            return .secondary
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct LogsPanelView: View {
    let logs: [AdminLog]
    let totalCount: Int
    let isLoading: Bool
    let error: String?
    let gatewayOptions: [String]
    let providerOptions: [String]
    let statusOptions: [String]
    @Binding var selectedGateway: String
    @Binding var selectedProvider: String
    @Binding var selectedStatus: String
    @Binding var errorsOnly: Bool
    let onClearFilters: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logs")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Picker("Gateway", selection: $selectedGateway) {
                    ForEach(gatewayOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Picker("Provider", selection: $selectedProvider) {
                    ForEach(providerOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Picker("Status", selection: $selectedStatus) {
                    ForEach(statusOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Only Errors", isOn: $errorsOnly)
                    .toggleStyle(.switch)

                Spacer()

                Button("Clear Filters") {
                    onClearFilters()
                }
                .buttonStyle(.link)
                .focusable(false)

                Text("Showing \(logs.count) / \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ZStack {
                List(logs) { log in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(log.requestID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 170, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(log.gatewayID) -> \(log.providerID)")
                                .font(.caption)
                            Text(log.model ?? "-")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 230, alignment: .leading)

                        Text("\(log.statusCode)")
                            .font(.caption.bold())
                            .foregroundStyle(color(for: log.statusCode))
                            .frame(width: 48, alignment: .leading)

                        Text("\(log.latencyMs) ms")
                            .font(.caption)
                            .frame(width: 72, alignment: .leading)

                        Text(log.createdAt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)

                if isLoading && logs.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading logs...")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if logs.isEmpty {
                    EmptyStateView(
                        title: "No logs",
                        systemImage: "list.bullet.rectangle.portrait",
                        message: "No request logs match current filters."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func color(for statusCode: Int) -> Color {
        switch statusCode {
        case 200..<300:
            return .green
        case 400..<500:
            return .orange
        case 500..<600:
            return .red
        default:
            return .secondary
        }
    }
}

private struct SettingsView: View {
    @Binding var adminURLInput: String
    let resolvedAdminURL: String
    let isBusy: Bool
    let errorMessage: String?
    let onApply: () async -> Void
    let onReset: () -> Void

    @FocusState private var isAddressFocused: Bool

    var body: some View {
        Form {
            Section("Connection") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Admin API Endpoint", systemImage: "network")
                        .font(.headline)

                    Text("Configure the fluxd Admin API address used by this native shell.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("http://127.0.0.1:7777", text: $adminURLInput)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .focused($isAddressFocused)
                        .onSubmit {
                            Task {
                                await onApply()
                            }
                        }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Settings error: \(errorMessage)")
                    }
                }
            }

            Section("Applied") {
                LabeledContent("Current Endpoint") {
                    Text(resolvedAdminURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    if isBusy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Refreshing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Reset Default") {
                        onReset()
                        isAddressFocused = true
                    }
                    .focusable(false)
                    .disabled(isBusy)

                    Button("Apply & Refresh") {
                        Task {
                            await onApply()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .focusable(false)
                    .disabled(isBusy)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }

            Section("Notes") {
                Label("Default local endpoint: http://127.0.0.1:7777", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Only http/https URLs are accepted.", systemImage: "shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("This native shell only consumes fluxd Admin API and does not duplicate backend business logic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConnectionBadge: View {
    let isLoading: Bool
    let hasError: Bool
    let hasSuccessfulSync: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var statusText: String {
        if isLoading {
            return "Syncing"
        }
        if hasError {
            return "Degraded"
        }
        if hasSuccessfulSync {
            return "Connected"
        }
        return "Idle"
    }

    private var statusColor: Color {
        if isLoading {
            return .yellow
        }
        if hasError {
            return .red
        }
        if hasSuccessfulSync {
            return .green
        }
        return .gray
    }
}

private struct ProviderFormSheet: View {
    enum Mode {
        case create
        case edit(AdminProvider)
    }

    let mode: Mode
    let isSubmitting: Bool
    let onCreate: (CreateProviderInput) async -> Void
    let onUpdate: (String, UpdateProviderInput) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var id: String
    @State private var name: String
    @State private var kind: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var models: String
    @State private var enabled: Bool
    @State private var showApiKey = false
    @State private var validationError: String?

    init(
        mode: Mode,
        isSubmitting: Bool,
        onCreate: @escaping (CreateProviderInput) async -> Void,
        onUpdate: @escaping (String, UpdateProviderInput) async -> Void
    ) {
        self.mode = mode
        self.isSubmitting = isSubmitting
        self.onCreate = onCreate
        self.onUpdate = onUpdate

        switch mode {
        case .create:
            _id = State(initialValue: "")
            _name = State(initialValue: "")
            _kind = State(initialValue: "openai")
            _baseURL = State(initialValue: "https://api.openai.com/v1")
            _apiKey = State(initialValue: "")
            _models = State(initialValue: "gpt-4o-mini")
            _enabled = State(initialValue: true)
        case let .edit(provider):
            _id = State(initialValue: provider.id)
            _name = State(initialValue: provider.name)
            _kind = State(initialValue: provider.kind)
            _baseURL = State(initialValue: provider.baseURL)
            _apiKey = State(initialValue: provider.apiKey)
            _models = State(initialValue: provider.models.joined(separator: ", "))
            _enabled = State(initialValue: provider.enabled)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            providerHeader

            Divider()
                .overlay(DesignTokens.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    providerSummaryCard

                    HStack(alignment: .top, spacing: 14) {
                        SurfaceCard(title: "Identity") {
                            VStack(alignment: .leading, spacing: 12) {
                                if isCreateMode {
                                    providerField(title: "Provider ID", caption: "Stable routing key used across gateways.") {
                                        textInput(placeholder: "provider_main", text: $id, monospaced: true)
                                    }
                                } else {
                                    providerField(title: "Provider ID", caption: "Locked after creation to keep downstream routes stable.") {
                                        readOnlyValue(id, monospaced: true)
                                    }
                                }

                                providerField(title: "Display Name") {
                                    textInput(placeholder: "Main Provider", text: $name)
                                }

                                providerField(title: "Kind", caption: "Choose one of the supported upstream provider types.") {
                                    providerKindPicker(selection: $kind)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        SurfaceCard(title: "Runtime") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(enabled ? "Routing enabled" : "Routing disabled")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Spacer()
                                    Toggle("Enabled", isOn: $enabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }

                                Text("Quick state snapshot for this upstream profile.")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)

                                dividerLine

                                VStack(alignment: .leading, spacing: 10) {
                                    providerMetaRow(label: "Status", value: enabled ? "Active" : "Disabled")
                                    providerMetaRow(label: "Models", value: "\(parsedModelCount)")
                                    providerMetaRow(label: "Auth", value: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Missing" : "Configured")
                                }
                            }
                        }
                        .frame(width: 220)
                    }

                    SurfaceCard(title: "Connection") {
                        VStack(alignment: .leading, spacing: 12) {
                            providerField(title: "Base URL", caption: "Use a full upstream endpoint, including the version path when needed.") {
                                textInput(placeholder: "https://api.openai.com/v1", text: $baseURL, monospaced: true)
                            }

                            dividerLine

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("API Key")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignTokens.textPrimary)
                                        Text("Stored locally and used for upstream authentication.")
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.textSecondary)
                                    }
                                    Spacer()
                                    Button(showApiKey ? "Hide" : "Reveal") {
                                        showApiKey.toggle()
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(showApiKey ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(DesignTokens.surfacePrimary.opacity(0.9))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
                                    )
                                }

                                if showApiKey {
                                    textInput(placeholder: "sk-...", text: $apiKey, monospaced: true)
                                } else {
                                    secureInput(placeholder: "sk-...", text: $apiKey)
                                }
                            }
                        }
                    }

                    SurfaceCard(title: "Models") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("List one or multiple models. Separate by comma or line break.")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)

                            TextEditor(text: $models)
                                .scrollContentBackground(.hidden)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .frame(minHeight: 136, maxHeight: 168)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(DesignTokens.surfacePrimary.opacity(0.92))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
                                )

                            HStack {
                                Label(parsedModelsPreview, systemImage: "shippingbox")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)
                                Spacer()
                                Label(enabled ? "Ready for routing" : "Disabled from routing", systemImage: enabled ? "checkmark.circle.fill" : "pause.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(enabled ? DesignTokens.statusColors.running.fill : DesignTokens.textSecondary)
                            }
                        }
                    }

                    if let validationError {
                        SurfaceCard {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(DesignTokens.statusColors.error.fill)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(validationError)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Text("Please review the highlighted configuration before saving.")
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }

            Divider()
                .overlay(DesignTokens.borderSubtle)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCreateMode ? "Create a reusable upstream profile" : "Update provider routing configuration")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(parsedModelsPreview)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignTokens.surfacePrimary.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignTokens.borderSubtle.opacity(0.85), lineWidth: 1)
                )
                .disabled(isSubmitting)

                Button {
                    submit()
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isCreateMode ? "Create Provider" : "Save Changes")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.13, green: 0.52, blue: 0.92))
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(DesignTokens.surfacePrimary.opacity(0.9))
        }
        .frame(width: 760, height: 670)
        .background(
            LinearGradient(
                colors: [
                    DesignTokens.surfacePrimary.opacity(0.98),
                    DesignTokens.surfaceSecondary.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var providerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isCreateMode ? "shippingbox.circle.fill" : "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(isCreateMode ? DesignTokens.statusColors.running.fill : DesignTokens.statusColors.warning.fill)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(isCreateMode ? "Create Provider" : "Configure Provider")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Manage upstream endpoint, API key and model routing in one compact control surface.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            StatusPill(
                text: enabled ? "Enabled" : "Disabled",
                semanticColor: enabled ? DesignTokens.statusColors.running : DesignTokens.statusColors.inactive
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(DesignTokens.surfacePrimary.opacity(0.86))
    }

    private var providerSummaryCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isCreateMode ? "Provider Profile" : "Provider Snapshot")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Provider" : name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No endpoint configured" : baseURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                compactMetric(title: "Kind", value: providerKindLabel(for: kind))
                compactMetric(title: "Models", value: "\(parsedModelCount)")
                compactMetric(title: "Auth", value: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Off" : "On")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.surfaceSecondary.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.borderSubtle.opacity(0.75), lineWidth: 1)
        )
    }

    private var isCreateMode: Bool {
        if case .create = mode {
            return true
        }
        return false
    }

    private var parsedModelCount: Int {
        models
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(DesignTokens.borderSubtle.opacity(0.75))
            .frame(height: 1)
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(DesignTokens.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .frame(minWidth: 64, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.surfacePrimary.opacity(0.88))
        )
    }

    private func providerMetaRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }

    private func providerField<Content: View>(title: String, caption: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(2)
                }
            }
            content()
        }
    }

    private func textInput(placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
            )
    }

    private func providerKindPicker(selection: Binding<String>) -> some View {
        Picker("Kind", selection: selection) {
            if let unsupportedKindLabel {
                Text(unsupportedKindLabel)
                    .tag(kind)
            }

            ForEach(ProviderKindOption.allCases) { option in
                Text(option.label)
                    .tag(option.rawValue)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.surfacePrimary.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
        )
    }

    private func secureInput(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
            )
    }

    private func readOnlyValue(_ value: String, monospaced: Bool = false) -> some View {
        Text(value)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .foregroundStyle(DesignTokens.textPrimary.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.borderSubtle.opacity(0.75), lineWidth: 1)
            )
    }

    private var unsupportedKindLabel: String? {
        guard !kind.isEmpty, ProviderKindOption(rawValue: kind) == nil else {
            return nil
        }

        return "Unsupported current value: \(kind)"
    }

    private func providerKindLabel(for rawValue: String) -> String {
        if rawValue.isEmpty {
            return "-"
        }

        return ProviderKindOption(rawValue: rawValue)?.label ?? rawValue
    }

    private func submit() {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedModels = models
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if isCreateMode && normalizedID.isEmpty {
            validationError = "ID is required."
            return
        }

        guard !normalizedName.isEmpty, !normalizedKind.isEmpty, !normalizedBaseURL.isEmpty, !normalizedApiKey.isEmpty else {
            validationError = "Name, Kind, Base URL and API Key are required."
            return
        }
        guard ProviderKindOption(rawValue: normalizedKind) != nil else {
            validationError = "Choose one of the supported provider kinds."
            return
        }
        guard URL(string: normalizedBaseURL) != nil else {
            validationError = "Base URL must be a valid URL."
            return
        }
        guard !parsedModels.isEmpty else {
            validationError = "At least one model is required."
            return
        }

        validationError = nil

        switch mode {
        case .create:
            let input = CreateProviderInput(
                id: normalizedID,
                name: normalizedName,
                kind: normalizedKind,
                baseURL: normalizedBaseURL,
                apiKey: normalizedApiKey,
                models: parsedModels,
                enabled: enabled
            )

            Task {
                await onCreate(input)
            }
        case .edit:
            let input = UpdateProviderInput(
                name: normalizedName,
                kind: normalizedKind,
                baseURL: normalizedBaseURL,
                apiKey: normalizedApiKey,
                models: parsedModels,
                enabled: enabled
            )

            Task {
                await onUpdate(normalizedID, input)
            }
        }
    }

    private var parsedModelsPreview: String {
        let count = parsedModelCount
        return count == 1 ? "1 model configured" : "\(count) models configured"
    }
}

private struct PlaceholderDetailView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        EmptyStateView(
            title: title,
            systemImage: systemImage,
            message: message
        )
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct GatewayPickerOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let isFallback: Bool
}

enum GatewayProtocolKind {
    case inbound
    case upstream
}

struct GatewayFormSnapshot: Equatable {
    let title: String
    let endpoint: String
    let providerLabel: String
    let protocolSummary: String
    let runtimeStatus: String
    let startupMode: String
    let routingMode: String
    let footerSummary: String
}

enum GatewayFormSupport {
    static func providerOptions(providers: [AdminProvider], selectedProviderID: String) -> [GatewayPickerOption] {
        let normalizedSelectedID = selectedProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseOptions = providers.map { provider in
            GatewayPickerOption(id: provider.id, title: provider.id, subtitle: provider.name, isFallback: false)
        }

        guard !normalizedSelectedID.isEmpty,
              providers.contains(where: { $0.id == normalizedSelectedID }) == false else {
            return baseOptions
        }

        return [
            GatewayPickerOption(
                id: normalizedSelectedID,
                title: "Current value: \(normalizedSelectedID)",
                subtitle: "Unavailable provider",
                isFallback: true
            )
        ] + baseOptions
    }

    static func protocolOptions(kind: GatewayProtocolKind, selectedValue: String) -> [GatewayPickerOption] {
        let normalizedSelectedValue = selectedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseOptions = defaultProtocolOptions(for: kind)

        guard !normalizedSelectedValue.isEmpty,
              baseOptions.contains(where: { $0.id == normalizedSelectedValue }) == false else {
            return baseOptions
        }

        return [
            GatewayPickerOption(
                id: normalizedSelectedValue,
                title: "Current value: \(normalizedSelectedValue)",
                subtitle: "Unsupported saved value",
                isFallback: true
            )
        ] + baseOptions
    }

    static func snapshot(
        name: String,
        listenHost: String,
        listenPort: String,
        inboundProtocol: String,
        upstreamProtocol: String,
        defaultProviderID: String,
        defaultModel: String,
        enabled: Bool,
        autoStart: Bool,
        protocolConfigJSON: String,
        providers: [AdminProvider]
    ) -> GatewayFormSnapshot {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPort = listenPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProviderID = defaultProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProtocolConfig = protocolConfigJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        let title = normalizedName.isEmpty ? "Untitled Gateway" : normalizedName
        let endpoint = normalizedHost.isEmpty || normalizedPort.isEmpty ? "No endpoint configured" : "\(normalizedHost):\(normalizedPort)"
        let protocolSummary = "\(protocolTitle(for: inboundProtocol, kind: .inbound)) -> \(protocolTitle(for: upstreamProtocol, kind: .upstream))"
        let routingMode: String

        if let parsed = try? JSONValue.parseObject(from: normalizedProtocolConfig.isEmpty ? "{}" : normalizedProtocolConfig), !parsed.isEmpty {
            routingMode = "Mapped"
        } else if upstreamProtocol.trimmingCharacters(in: .whitespacesAndNewlines) == "provider_default" {
            routingMode = "Direct"
        } else {
            routingMode = "Bridge"
        }

        let providerLabel = normalizedProviderID.isEmpty ? "Unassigned" : (providers.first(where: { $0.id == normalizedProviderID })?.id ?? normalizedProviderID)

        _ = defaultModel

        return GatewayFormSnapshot(
            title: title,
            endpoint: endpoint,
            providerLabel: providerLabel,
            protocolSummary: protocolSummary,
            runtimeStatus: enabled ? "Active" : "Disabled",
            startupMode: autoStart ? "Automatic" : "Manual",
            routingMode: routingMode,
            footerSummary: endpoint == "No endpoint configured"
                ? (autoStart ? "Auto Start On" : "Auto Start Off")
                : "\(endpoint) · \(autoStart ? "Auto Start On" : "Auto Start Off")"
        )
    }

    static func protocolTitle(for rawValue: String, kind: GatewayProtocolKind) -> String {
        let normalizedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedRawValue.isEmpty else {
            return "-"
        }

        return defaultProtocolOptions(for: kind).first(where: { $0.id == normalizedRawValue })?.title ?? normalizedRawValue
    }

    private static func defaultProtocolOptions(for kind: GatewayProtocolKind) -> [GatewayPickerOption] {
        switch kind {
        case .inbound:
            return ProviderKindOption.allCases.map { option in
                GatewayPickerOption(
                    id: option.rawValue,
                    title: option.label,
                    subtitle: option.inboundProtocolSubtitle,
                    isFallback: false
                )
            }
        case .upstream:
            return [
                GatewayPickerOption(id: "provider_default", title: "Provider Default", subtitle: "Delegate protocol to provider kind", isFallback: false),
            ] + ProviderKindOption.allCases.map { option in
                GatewayPickerOption(
                    id: option.rawValue,
                    title: option.label,
                    subtitle: option.upstreamProtocolSubtitle,
                    isFallback: false
                )
            }
        }
    }
}

private enum GatewayFormMode {
    case create
    case edit(AdminGateway)
}

private struct GatewayFormSheet: View {
    let mode: GatewayFormMode
    let providers: [AdminProvider]
    let isSubmitting: Bool
    let onCreate: (CreateGatewayInput) async -> Void
    let onUpdate: (String, UpdateGatewayInput) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var name = ""
    @State private var listenHost = "127.0.0.1"
    @State private var listenPort = "18080"
    @State private var inboundProtocol = "openai"
    @State private var upstreamProtocol = "provider_default"
    @State private var protocolConfigJSON = JSONValue.prettyPrinted(["compatibility_mode": .string("compatible")])
    @State private var defaultProviderID = ""
    @State private var defaultModel = "gpt-4o-mini"
    @State private var enabled = true
    @State private var autoStart = false
    @State private var validationError: String?

    init(
        mode: GatewayFormMode,
        providers: [AdminProvider],
        isSubmitting: Bool,
        onCreate: @escaping (CreateGatewayInput) async -> Void,
        onUpdate: @escaping (String, UpdateGatewayInput) async -> Void
    ) {
        self.mode = mode
        self.providers = providers
        self.isSubmitting = isSubmitting
        self.onCreate = onCreate
        self.onUpdate = onUpdate

        switch mode {
        case .create:
            _id = State(initialValue: "")
            _name = State(initialValue: "")
            _listenHost = State(initialValue: "127.0.0.1")
            _listenPort = State(initialValue: "18080")
            _inboundProtocol = State(initialValue: "openai")
            _upstreamProtocol = State(initialValue: "provider_default")
            _protocolConfigJSON = State(initialValue: JSONValue.prettyPrinted(["compatibility_mode": .string("compatible")]))
            _defaultProviderID = State(initialValue: "")
            _defaultModel = State(initialValue: "gpt-4o-mini")
            _enabled = State(initialValue: true)
            _autoStart = State(initialValue: false)
        case .edit(let gateway):
            _id = State(initialValue: gateway.id)
            _name = State(initialValue: gateway.name)
            _listenHost = State(initialValue: gateway.listenHost)
            _listenPort = State(initialValue: String(gateway.listenPort))
            _inboundProtocol = State(initialValue: gateway.inboundProtocol)
            _upstreamProtocol = State(initialValue: gateway.upstreamProtocol)
            _protocolConfigJSON = State(initialValue: JSONValue.prettyPrinted(gateway.protocolConfigJSON))
            _defaultProviderID = State(initialValue: gateway.defaultProviderId)
            _defaultModel = State(initialValue: gateway.defaultModel ?? "")
            _enabled = State(initialValue: gateway.enabled)
            _autoStart = State(initialValue: gateway.autoStart)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            gatewayHeader

            Divider()
                .overlay(DesignTokens.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    gatewaySummaryCard

                    HStack(alignment: .top, spacing: 14) {
                        SurfaceCard(title: "Identity") {
                            VStack(alignment: .leading, spacing: 12) {
                                if isCreateMode {
                                    gatewayField(title: "Gateway ID", caption: "Stable local route identifier used by admin workflows.") {
                                        textInput(placeholder: "gateway_main", text: $id, monospaced: true)
                                    }
                                } else {
                                    gatewayField(title: "Gateway ID", caption: "Locked after creation to keep local clients and scripts stable.") {
                                        readOnlyValue(id, monospaced: true)
                                    }
                                }

                                gatewayField(title: "Display Name") {
                                    textInput(placeholder: "Gateway Main", text: $name)
                                }

                                gatewayField(title: "Default Provider", caption: "Choose the upstream provider that receives unmatched traffic.") {
                                    providerPicker
                                }

                                gatewayField(title: "Default Model", caption: "Optional model hint for clients that omit the model field.") {
                                    textInput(placeholder: "gpt-4o-mini", text: $defaultModel, monospaced: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        SurfaceCard(title: "Runtime") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(enabled ? "Routing enabled" : "Routing disabled")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Spacer()
                                    Toggle("Enabled", isOn: $enabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }

                                HStack {
                                    Text(autoStart ? "Auto start on fluxd launch" : "Manual startup")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Spacer()
                                    Toggle("Auto Start", isOn: $autoStart)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }

                                Text("Quick runtime snapshot for the current gateway profile.")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)

                                dividerLine

                                VStack(alignment: .leading, spacing: 10) {
                                    gatewayMetaRow(label: "Status", value: snapshot.runtimeStatus)
                                    gatewayMetaRow(label: "Startup", value: snapshot.startupMode)
                                    gatewayMetaRow(label: "Endpoint", value: snapshot.endpoint)
                                    gatewayMetaRow(label: "Routing", value: snapshot.routingMode)
                                }
                            }
                        }
                        .frame(width: 240)
                    }

                    SurfaceCard(title: "Network & Protocols") {
                        HStack(alignment: .top, spacing: 12) {
                            gatewayField(title: "Listen Host", caption: "Local bind address for the gateway process.") {
                                textInput(placeholder: "127.0.0.1", text: $listenHost, monospaced: true)
                            }

                            gatewayField(title: "Listen Port", caption: "Expose a unique local port between 1 and 65535.") {
                                textInput(placeholder: "18080", text: $listenPort, monospaced: true)
                            }

                            gatewayField(title: "Inbound Protocol", caption: "Client-facing protocol accepted at the local endpoint.") {
                                protocolPicker(kind: .inbound, selection: $inboundProtocol)
                            }

                            gatewayField(title: "Upstream Protocol", caption: "Protocol used when forwarding to the selected provider.") {
                                protocolPicker(kind: .upstream, selection: $upstreamProtocol)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        SurfaceCard(title: "Routing JSON") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Protocol compatibility and routing overrides are stored with the gateway profile. If this instance is currently running and the configuration changes, FluxDeck will restart it automatically after save.")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)

                                TextEditor(text: $protocolConfigJSON)
                                    .scrollContentBackground(.hidden)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .frame(minHeight: 180, maxHeight: 220)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(DesignTokens.surfacePrimary.opacity(0.92))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
                                    )

                                if let routingValidationError {
                                    Label(routingValidationError, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.statusColors.error.fill)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        SurfaceCard(title: "Routing Targets") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Use this reference list to confirm the provider selected as the default upstream target.")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)

                                if providerOptions.isEmpty {
                                    Text("No providers available yet.")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                } else {
                                    ForEach(providerOptions) { option in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(option.title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(DesignTokens.textPrimary)
                                                Spacer()
                                                if let provider = providers.first(where: { $0.id == option.id }) {
                                                    StatusPill(
                                                        text: provider.enabled ? "Enabled" : "Disabled",
                                                        semanticColor: provider.enabled ? DesignTokens.statusColors.running : DesignTokens.statusColors.inactive
                                                    )
                                                } else if option.isFallback {
                                                    StatusPill(
                                                        text: "Fallback",
                                                        semanticColor: DesignTokens.statusColors.warning
                                                    )
                                                }
                                            }

                                            if let subtitle = option.subtitle {
                                                Text(subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(DesignTokens.textSecondary)
                                            }
                                        }
                                        .padding(.bottom, option.id == providerOptions.last?.id ? 0 : 6)
                                    }
                                }
                            }
                        }
                        .frame(width: 240)
                    }

                    if let validationError {
                        SurfaceCard {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(DesignTokens.statusColors.error.fill)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(validationError)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Text("Review the required fields before saving this gateway configuration.")
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }

            Divider()
                .overlay(DesignTokens.borderSubtle)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCreateMode ? "Create a local gateway profile" : "Update local routing and protocol configuration")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(snapshot.footerSummary)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignTokens.surfacePrimary.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignTokens.borderSubtle.opacity(0.85), lineWidth: 1)
                )
                .disabled(isSubmitting)

                Button {
                    submit()
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isCreateMode ? "Create Gateway" : "Save Changes")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.13, green: 0.52, blue: 0.92))
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(DesignTokens.surfacePrimary.opacity(0.9))
        }
        .frame(width: 760, height: 680)
        .background(
            LinearGradient(
                colors: [
                    DesignTokens.surfacePrimary.opacity(0.98),
                    DesignTokens.surfaceSecondary.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func submit() {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProtocol = inboundProtocol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUpstreamProtocol = upstreamProtocol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProviderID = defaultProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProtocolConfig = protocolConfigJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        if isCreateMode && normalizedID.isEmpty {
            validationError = "ID is required."
            return
        }

        guard !normalizedName.isEmpty, !normalizedHost.isEmpty, !normalizedProtocol.isEmpty, !normalizedUpstreamProtocol.isEmpty else {
            validationError = "Name, Host and Protocols are required."
            return
        }

        guard !normalizedProviderID.isEmpty else {
            validationError = "Default Provider is required."
            return
        }

        guard let port = Int(listenPort.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) else {
            validationError = "Listen Port must be a valid port number (1-65535)."
            return
        }

        let parsedProtocolConfig: [String: JSONValue]
        do {
            parsedProtocolConfig = try JSONValue.parseObject(from: normalizedProtocolConfig.isEmpty ? "{}" : normalizedProtocolConfig)
        } catch {
            validationError = "Protocol Config JSON must be a valid JSON object."
            return
        }

        validationError = nil

        switch mode {
        case .create:
            let input = CreateGatewayInput(
                id: normalizedID,
                name: normalizedName,
                listenHost: normalizedHost,
                listenPort: port,
                inboundProtocol: normalizedProtocol,
                upstreamProtocol: normalizedUpstreamProtocol,
                protocolConfigJSON: parsedProtocolConfig,
                defaultProviderId: normalizedProviderID,
                defaultModel: normalizedModel.isEmpty ? nil : normalizedModel,
                enabled: enabled,
                autoStart: autoStart
            )

            Task {
                await onCreate(input)
            }
        case .edit:
            let input = UpdateGatewayInput(
                name: normalizedName,
                listenHost: normalizedHost,
                listenPort: port,
                inboundProtocol: normalizedProtocol,
                upstreamProtocol: normalizedUpstreamProtocol,
                protocolConfigJSON: parsedProtocolConfig,
                defaultProviderId: normalizedProviderID,
                defaultModel: normalizedModel.isEmpty ? nil : normalizedModel,
                enabled: enabled,
                autoStart: autoStart
            )

            Task {
                await onUpdate(normalizedID, input)
            }
        }
    }

    private var isCreateMode: Bool {
        if case .create = mode {
            return true
        }
        return false
    }

    private var snapshot: GatewayFormSnapshot {
        GatewayFormSupport.snapshot(
            name: name,
            listenHost: listenHost,
            listenPort: listenPort,
            inboundProtocol: inboundProtocol,
            upstreamProtocol: upstreamProtocol,
            defaultProviderID: defaultProviderID,
            defaultModel: defaultModel,
            enabled: enabled,
            autoStart: autoStart,
            protocolConfigJSON: protocolConfigJSON,
            providers: providers
        )
    }

    private var providerOptions: [GatewayPickerOption] {
        GatewayFormSupport.providerOptions(providers: providers, selectedProviderID: defaultProviderID)
    }

    private var routingValidationError: String? {
        let normalizedProtocolConfig = protocolConfigJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedProtocolConfig.isEmpty else {
            return nil
        }

        do {
            _ = try JSONValue.parseObject(from: normalizedProtocolConfig)
            return nil
        } catch {
            return "Routing JSON must be a valid JSON object."
        }
    }

    private var gatewayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isCreateMode ? "point.3.connected.trianglepath.dotted" : "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(isCreateMode ? DesignTokens.statusColors.running.fill : DesignTokens.statusColors.warning.fill)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(isCreateMode ? "Create Gateway" : "Configure Gateway")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Manage the local endpoint, protocol bridge and default upstream route in one compact control surface.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            StatusPill(
                text: enabled ? "Enabled" : "Disabled",
                semanticColor: enabled ? DesignTokens.statusColors.running : DesignTokens.statusColors.inactive
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(DesignTokens.surfacePrimary.opacity(0.86))
    }

    private var gatewaySummaryCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isCreateMode ? "Gateway Profile" : "Gateway Snapshot")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(snapshot.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(snapshot.endpoint)
                    .font(.caption.monospaced())
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                compactMetric(title: "Inbound", value: GatewayFormSupport.protocolTitle(for: inboundProtocol, kind: .inbound))
                compactMetric(title: "Upstream", value: GatewayFormSupport.protocolTitle(for: upstreamProtocol, kind: .upstream))
                compactMetric(title: "Provider", value: snapshot.providerLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.surfaceSecondary.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.borderSubtle.opacity(0.75), lineWidth: 1)
        )
    }

    private var providerPicker: some View {
        Group {
            if providerOptions.isEmpty {
                readOnlyValue("No providers available")
            } else {
                Picker("Default Provider", selection: $defaultProviderID) {
                    ForEach(providerOptions) { option in
                        Text(option.title)
                            .tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignTokens.surfacePrimary.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
                )
            }
        }
    }

    private func protocolPicker(kind: GatewayProtocolKind, selection: Binding<String>) -> some View {
        let options = GatewayFormSupport.protocolOptions(kind: kind, selectedValue: selection.wrappedValue)

        return Picker(kind == .inbound ? "Inbound Protocol" : "Upstream Protocol", selection: selection) {
            ForEach(options) { option in
                Text(option.title)
                    .tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.surfacePrimary.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
        )
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(DesignTokens.borderSubtle.opacity(0.75))
            .frame(height: 1)
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(DesignTokens.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
        }
        .frame(minWidth: 72, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.surfacePrimary.opacity(0.88))
        )
    }

    private func gatewayMetaRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
        }
    }

    private func gatewayField<Content: View>(title: String, caption: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(2)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textInput(placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.borderSubtle.opacity(0.9), lineWidth: 1)
            )
    }

    private func readOnlyValue(_ value: String, monospaced: Bool = false) -> some View {
        Text(value)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .foregroundStyle(DesignTokens.textPrimary.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.borderSubtle.opacity(0.75), lineWidth: 1)
            )
    }
}
