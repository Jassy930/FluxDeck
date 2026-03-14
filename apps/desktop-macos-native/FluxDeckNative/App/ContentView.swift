import SwiftUI

struct ContentView: View {
    @Environment(\.locale) private var locale
    @AppStorage("fluxdeck.native.admin_base_url") private var persistedAdminBaseURL = defaultAdminBaseURL
    @AppStorage("fluxdeck.native.language_preference") private var persistedLanguagePreference = AppLanguage.system.storageValue
    @State private var providers: [AdminProvider] = []
    @State private var providerHealthStates: [AdminProviderHealthState] = []
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
            gateways: gateways,
            locale: locale
        )
    }

    private var shellToolbarModel: ShellToolbarModel {
        ShellToolbarModel.make(
            title: L10n.string(selectedSection?.titleKey ?? SidebarSection.overview.titleKey, locale: locale),
            adminBaseURL: client.displayBaseURL,
            lastRefreshText: lastRefreshedAt.map { Self.refreshFormatter.string(from: $0) },
            isRefreshing: isLoading || isSubmitting,
            statusSummary: shellStatusSummary,
            locale: locale
        )
    }

    private var client: AdminApiClient {
        let url = normalizedAdminBaseURL(persistedAdminBaseURL) ?? URL(string: defaultAdminBaseURL)!
        return AdminApiClient(baseURL: url)
    }

    private var selectedLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage.from(storageValue: persistedLanguagePreference) },
            set: { persistedLanguagePreference = $0.storageValue }
        )
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
            groups: SidebarGroup.defaultGroups,
            selectedSection: $selectedSection,
            selectedMode: $selectedMode,
            toolbarModel: shellToolbarModel,
            onRefresh: {
                Task {
                    await refreshAll()
                }
            }
        ) {
            VStack(spacing: 0) {
                if let loadError {
                    shellErrorBanner(loadError)
                    Divider()
                        .overlay(DesignTokens.borderSubtle)
                }
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
            L10n.string("dialog.delete_provider.title", locale: locale),
            isPresented: Binding(
                get: { providerPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        providerPendingDelete = nil
                    }
                }
            ),
            actions: {
                Button(L10n.string("dialog.delete.action.delete", locale: locale), role: .destructive) {
                    guard let provider = providerPendingDelete else {
                        return
                    }
                    providerPendingDelete = nil
                    Task {
                        await deleteProvider(provider)
                    }
                }
                Button(L10n.string("dialog.delete.action.cancel", locale: locale), role: .cancel) {
                    providerPendingDelete = nil
                }
            },
            message: {
                let providerID = providerPendingDelete?.id ?? "provider"
                Text(L10n.formatted("dialog.delete_provider.message", locale: locale, providerID))
            }
        )
        .alert(
            L10n.string("dialog.delete_gateway.title", locale: locale),
            isPresented: Binding(
                get: { gatewayPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        gatewayPendingDelete = nil
                    }
                }
            ),
            actions: {
                Button(L10n.string("dialog.delete.action.delete", locale: locale), role: .destructive) {
                    guard let gateway = gatewayPendingDelete else {
                        return
                    }
                    gatewayPendingDelete = nil
                    Task {
                        await deleteGateway(gateway)
                    }
                }
                Button(L10n.string("dialog.delete.action.cancel", locale: locale), role: .cancel) {
                    gatewayPendingDelete = nil
                }
            },
            message: {
                let gatewayID = gatewayPendingDelete?.id ?? "gateway"
                Text(L10n.formatted("dialog.delete_gateway.message", locale: locale, gatewayID))
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
                    logs: dashboardLogs,
                    locale: locale
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
                providerHealthStates: providerHealthStates,
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
                onProbe: { provider in
                    Task {
                        await probeProvider(provider)
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
                    selectedPeriod: selectedTrafficPeriod,
                    locale: locale
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
                    logs: dashboardLogs,
                    locale: locale
                )
            )
        case .routeMap:
            PlaceholderDetailView(
                title: L10n.string("placeholder.route_map.title", locale: locale),
                systemImage: SidebarSection.routeMap.icon,
                message: L10n.string("placeholder.route_map.message", locale: locale)
            )
        case .settings:
            SettingsPanelView(
                adminURLInput: $adminBaseURLInput,
                selectedLanguage: selectedLanguageBinding,
                resolvedAdminURL: client.displayBaseURL,
                isBusy: isLoading || isSubmitting,
                errorMessage: settingsError,
                model: SettingsPanelModel.make(
                    adminBaseURL: client.displayBaseURL,
                    isLoading: isLoading || isSubmitting,
                    hasError: settingsError != nil,
                    selectedLanguage: selectedLanguageBinding.wrappedValue,
                    locale: selectedLanguageBinding.wrappedValue.resolvedLocale
                ),
                onApply: { await applyAdminBaseURL() },
                onReset: {
                    adminBaseURLInput = defaultAdminBaseURL
                    settingsError = nil
                }
            )
        }
    }

    @ViewBuilder
    private func shellErrorBanner(_ loadError: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(loadError)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button(L10n.string("shell.error.retry", locale: locale)) {
                Task {
                    await refreshAll()
                }
            }
            .buttonStyle(.link)
            .focusable(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.formatted("shell.error.refresh_accessibility", locale: locale, loadError))
    }

    @MainActor
    private func refreshAll() async {
        isLoading = true

        do {
            async let providerTask = client.fetchProviders()
            async let providerHealthTask = client.fetchProviderHealth()
            async let gatewayTask = client.fetchGateways()
            async let dashboardLogsTask = client.fetchDashboardLogs(limit: Self.dashboardLogLimit)

            let nextProviders = try await providerTask
            let nextProviderHealthStates = try await providerHealthTask
            let nextGateways = try await gatewayTask
            let nextDashboardLogs = try await dashboardLogsTask

            providers = nextProviders
            providerHealthStates = nextProviderHealthStates
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
            operationNotice = L10n.string("admin.provider.notice.deleted", locale: locale)
            await refreshAll()
        } catch {
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func probeProvider(_ provider: AdminProvider) async {
        isSubmitting = true
        operationNotice = nil

        do {
            let result = try await client.probeProvider(id: provider.id)
            loadError = nil
            operationNotice = L10n.formatted(
                L10n.adminProviderProbeStarted,
                locale: locale,
                provider.id,
                L10n.providerHealthStatus(result.status, locale: locale)
            )
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

    private static let logFilterAll = "__all__"
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
            settingsError = L10n.string("settings.connection.validation.invalid_url", locale: locale)
            return
        }

        let normalizedValue = normalizedURL.absoluteString
        persistedAdminBaseURL = normalizedValue
        adminBaseURLInput = normalizedValue
        settingsError = nil
        await refreshAll()
    }
}

func trafficTrendInterval(for period: String) -> String {
    switch period {
    case "1h":
        return "1m"
    case "6h":
        return "5m"
    case "24h":
        return "15m"
    default:
        return "5m"
    }
}


private func providersAndGatewaysIDs(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
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

    @Environment(\.locale) private var locale
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
                        SurfaceCard(title: L10n.string("provider_form.section.identity", locale: locale)) {
                            VStack(alignment: .leading, spacing: 12) {
                                if isCreateMode {
                                    providerField(title: L10n.string("provider_form.field.provider_id", locale: locale), caption: L10n.string("provider_form.field.provider_id.caption_create", locale: locale)) {
                                        textInput(placeholder: "provider_main", text: $id, monospaced: true)
                                    }
                                } else {
                                    providerField(title: L10n.string("provider_form.field.provider_id", locale: locale), caption: L10n.string("provider_form.field.provider_id.caption_edit", locale: locale)) {
                                        readOnlyValue(id, monospaced: true)
                                    }
                                }

                                providerField(title: L10n.string("provider_form.field.display_name", locale: locale)) {
                                    textInput(placeholder: "Main Provider", text: $name)
                                }

                                providerField(title: L10n.string("provider_form.field.kind", locale: locale), caption: L10n.string("provider_form.field.kind.caption", locale: locale)) {
                                    providerKindPicker(selection: $kind)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        SurfaceCard(title: L10n.string("provider_form.section.runtime", locale: locale)) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(L10n.string(enabled ? "provider_form.runtime.routing_enabled" : "provider_form.runtime.routing_disabled", locale: locale))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Spacer()
                                    Toggle(L10n.string("provider_form.toggle.enabled", locale: locale), isOn: $enabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }

                                Text(L10n.string("provider_form.runtime.snapshot_caption", locale: locale))
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)

                                dividerLine

                                VStack(alignment: .leading, spacing: 10) {
                                    providerMetaRow(label: L10n.string("provider_form.meta.status", locale: locale), value: L10n.string(enabled ? "provider_form.meta.status_active" : "provider_form.meta.status_disabled", locale: locale))
                                    providerMetaRow(label: L10n.string("provider_form.meta.models", locale: locale), value: "\(parsedModelCount)")
                                    providerMetaRow(label: L10n.string("provider_form.meta.auth", locale: locale), value: L10n.string(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "provider_form.meta.auth_missing" : "provider_form.meta.auth_configured", locale: locale))
                                }
                            }
                        }
                        .frame(width: 220)
                    }

                    SurfaceCard(title: L10n.string("provider_form.section.connection", locale: locale)) {
                        VStack(alignment: .leading, spacing: 12) {
                            providerField(title: L10n.string("provider_form.field.base_url", locale: locale), caption: L10n.string("provider_form.field.base_url.caption", locale: locale)) {
                                textInput(placeholder: "https://api.openai.com/v1", text: $baseURL, monospaced: true)
                            }

                            dividerLine

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(L10n.string("provider_form.field.api_key", locale: locale))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignTokens.textPrimary)
                                        Text(L10n.string("provider_form.field.api_key.caption", locale: locale))
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.textSecondary)
                                    }
                                    Spacer()
                                    Button(L10n.string(showApiKey ? "provider_form.action.hide" : "provider_form.action.reveal", locale: locale)) {
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

                    SurfaceCard(title: L10n.string("provider_form.section.models", locale: locale)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.string("provider_form.models.caption", locale: locale))
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
                                Label(L10n.string(enabled ? "provider_form.models.ready" : "provider_form.models.disabled", locale: locale), systemImage: enabled ? "checkmark.circle.fill" : "pause.circle.fill")
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
                                    Text(L10n.string("provider_form.validation.review", locale: locale))
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
                    Text(L10n.string(isCreateMode ? "provider_form.footer.create" : "provider_form.footer.update", locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(parsedModelsPreview)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer()

                Button(L10n.string("common.action.cancel", locale: locale)) {
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
                        Text(L10n.string(isCreateMode ? "provider_form.action.create" : "common.action.save_changes", locale: locale))
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
                Text(L10n.string(isCreateMode ? "provider_form.header.create" : "provider_form.header.edit", locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(L10n.string("provider_form.header.subtitle", locale: locale))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            StatusPill(
                text: L10n.string(enabled ? "provider_form.status.enabled" : "provider_form.status.disabled", locale: locale),
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
                Text(L10n.string(isCreateMode ? "provider_form.summary.profile" : "provider_form.summary.snapshot", locale: locale))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.string("provider_form.summary.untitled", locale: locale) : name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.string("provider_form.summary.no_endpoint", locale: locale) : baseURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                compactMetric(title: L10n.string("provider_form.metric.kind", locale: locale), value: providerKindLabel(for: kind))
                compactMetric(title: L10n.string("provider_form.metric.models", locale: locale), value: "\(parsedModelCount)")
                compactMetric(title: L10n.string("provider_form.metric.auth", locale: locale), value: L10n.string(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "provider_form.metric.auth_off" : "provider_form.metric.auth_on", locale: locale))
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
        Picker(L10n.string("provider_form.field.kind", locale: locale), selection: selection) {
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

        return L10n.formatted("provider_form.kind.unsupported_current_value", locale: locale, kind)
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
            validationError = L10n.string("provider_form.validation.id_required", locale: locale)
            return
        }

        guard !normalizedName.isEmpty, !normalizedKind.isEmpty, !normalizedBaseURL.isEmpty, !normalizedApiKey.isEmpty else {
            validationError = L10n.string("provider_form.validation.required_fields", locale: locale)
            return
        }
        guard ProviderKindOption(rawValue: normalizedKind) != nil else {
            validationError = L10n.string("provider_form.validation.unsupported_kind", locale: locale)
            return
        }
        guard URL(string: normalizedBaseURL) != nil else {
            validationError = L10n.string("provider_form.validation.invalid_base_url", locale: locale)
            return
        }
        guard !parsedModels.isEmpty else {
            validationError = L10n.string("provider_form.validation.model_required", locale: locale)
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
        L10n.formatted(
            parsedModelCount == 1 ? "provider_form.models.count.one" : "provider_form.models.count.other",
            locale: locale,
            Int64(parsedModelCount)
        )
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
    static func providerOptions(providers: [AdminProvider], selectedProviderID: String, locale: Locale = .autoupdatingCurrent) -> [GatewayPickerOption] {
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
                title: L10n.formatted("gateway_form.option.current_value", locale: locale, normalizedSelectedID),
                subtitle: L10n.string("gateway_form.option.unavailable_provider", locale: locale),
                isFallback: true
            )
        ] + baseOptions
    }

    static func protocolOptions(kind: GatewayProtocolKind, selectedValue: String, locale: Locale = .autoupdatingCurrent) -> [GatewayPickerOption] {
        let normalizedSelectedValue = selectedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseOptions = defaultProtocolOptions(for: kind, locale: locale)

        guard !normalizedSelectedValue.isEmpty,
              baseOptions.contains(where: { $0.id == normalizedSelectedValue }) == false else {
            return baseOptions
        }

        return [
            GatewayPickerOption(
                id: normalizedSelectedValue,
                title: L10n.formatted("gateway_form.option.current_value", locale: locale, normalizedSelectedValue),
                subtitle: L10n.string("gateway_form.option.unsupported_saved_value", locale: locale),
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
        providers: [AdminProvider],
        locale: Locale = .autoupdatingCurrent
    ) -> GatewayFormSnapshot {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPort = listenPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProviderID = defaultProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProtocolConfig = protocolConfigJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        let title = normalizedName.isEmpty ? L10n.string("gateway_form.summary.untitled", locale: locale) : normalizedName
        let endpoint = normalizedHost.isEmpty || normalizedPort.isEmpty ? L10n.string("gateway_form.summary.no_endpoint", locale: locale) : "\(normalizedHost):\(normalizedPort)"
        let protocolSummary = "\(protocolTitle(for: inboundProtocol, kind: .inbound, locale: locale)) -> \(protocolTitle(for: upstreamProtocol, kind: .upstream, locale: locale))"
        let routingMode: String

        if let parsed = try? JSONValue.parseObject(from: normalizedProtocolConfig.isEmpty ? "{}" : normalizedProtocolConfig), !parsed.isEmpty {
            routingMode = L10n.string("gateway_form.routing.mapped", locale: locale)
        } else if upstreamProtocol.trimmingCharacters(in: .whitespacesAndNewlines) == "provider_default" {
            routingMode = L10n.string("gateway_form.routing.direct", locale: locale)
        } else {
            routingMode = L10n.string("gateway_form.routing.bridge", locale: locale)
        }

        let providerLabel = normalizedProviderID.isEmpty ? L10n.string("gateway_form.provider.unassigned", locale: locale) : (providers.first(where: { $0.id == normalizedProviderID })?.id ?? normalizedProviderID)

        _ = defaultModel

        return GatewayFormSnapshot(
            title: title,
            endpoint: endpoint,
            providerLabel: providerLabel,
            protocolSummary: protocolSummary,
            runtimeStatus: L10n.string(enabled ? "gateway_form.runtime.active" : "gateway_form.runtime.disabled", locale: locale),
            startupMode: L10n.string(autoStart ? "gateway_form.startup.automatic" : "gateway_form.startup.manual", locale: locale),
            routingMode: routingMode,
            footerSummary: endpoint == L10n.string("gateway_form.summary.no_endpoint", locale: locale)
                ? L10n.string(autoStart ? "gateway_form.footer.auto_start_on" : "gateway_form.footer.auto_start_off", locale: locale)
                : L10n.formatted(
                    "gateway_form.footer.endpoint_with_auto_start",
                    locale: locale,
                    endpoint,
                    L10n.string(autoStart ? "gateway_form.footer.auto_start_on" : "gateway_form.footer.auto_start_off", locale: locale)
                )
        )
    }

    static func protocolTitle(for rawValue: String, kind: GatewayProtocolKind, locale: Locale = .autoupdatingCurrent) -> String {
        let normalizedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedRawValue.isEmpty else {
            return "-"
        }

        return defaultProtocolOptions(for: kind, locale: locale).first(where: { $0.id == normalizedRawValue })?.title ?? normalizedRawValue
    }

    static func normalizedRouteTargets(
        routeTargets: [AdminRouteTargetInput],
        primaryProviderID: String
    ) -> [AdminRouteTargetInput] {
        let normalizedPrimary = primaryProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        var workingTargets = routeTargets.sorted(by: { $0.priority < $1.priority })

        if !normalizedPrimary.isEmpty {
            if let existingPrimaryIndex = workingTargets.firstIndex(where: {
                $0.providerId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedPrimary
            }) {
                workingTargets.remove(at: existingPrimaryIndex)
            }

            workingTargets.insert(
                AdminRouteTargetInput(providerId: normalizedPrimary, priority: 0, enabled: true),
                at: 0
            )
        }

        var normalizedTargets: [AdminRouteTargetInput] = []
        var seenProviderIDs = Set<String>()

        for target in workingTargets {
            let providerID = target.providerId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !providerID.isEmpty, seenProviderIDs.insert(providerID).inserted else {
                continue
            }

            normalizedTargets.append(
                AdminRouteTargetInput(
                    providerId: providerID,
                    priority: normalizedTargets.count,
                    enabled: normalizedTargets.isEmpty ? true : target.enabled
                )
            )
        }

        return normalizedTargets
    }

    static func addRouteTarget(
        routeTargets: [AdminRouteTargetInput],
        availableProviderIDs: [String],
        primaryProviderID: String
    ) -> [AdminRouteTargetInput] {
        let normalizedTargets = normalizedRouteTargets(
            routeTargets: routeTargets,
            primaryProviderID: primaryProviderID
        )
        let usedProviderIDs = Set(normalizedTargets.map(\.providerId))
        guard let nextProviderID = availableProviderIDs.first(where: { usedProviderIDs.contains($0) == false }) else {
            return normalizedTargets
        }

        return normalizedRouteTargets(
            routeTargets: normalizedTargets + [
                AdminRouteTargetInput(
                    providerId: nextProviderID,
                    priority: normalizedTargets.count,
                    enabled: true
                )
            ],
            primaryProviderID: primaryProviderID
        )
    }

    static func removeRouteTarget(
        routeTargets: [AdminRouteTargetInput],
        index: Int,
        primaryProviderID: String
    ) -> [AdminRouteTargetInput] {
        var normalizedTargets = normalizedRouteTargets(
            routeTargets: routeTargets,
            primaryProviderID: primaryProviderID
        )
        guard normalizedTargets.indices.contains(index) else {
            return normalizedTargets
        }

        normalizedTargets.remove(at: index)
        let nextPrimary = normalizedTargets.first?.providerId ?? primaryProviderID
        return normalizedRouteTargets(routeTargets: normalizedTargets, primaryProviderID: nextPrimary)
    }

    static func moveRouteTarget(
        routeTargets: [AdminRouteTargetInput],
        from: Int,
        to: Int,
        primaryProviderID: String
    ) -> [AdminRouteTargetInput] {
        var normalizedTargets = normalizedRouteTargets(
            routeTargets: routeTargets,
            primaryProviderID: primaryProviderID
        )
        guard normalizedTargets.indices.contains(from), normalizedTargets.indices.contains(to), from != to else {
            return normalizedTargets
        }

        let item = normalizedTargets.remove(at: from)
        normalizedTargets.insert(item, at: to)
        normalizedTargets = normalizedTargets.enumerated().map { index, target in
            AdminRouteTargetInput(
                providerId: target.providerId,
                priority: index,
                enabled: index == 0 ? true : target.enabled
            )
        }
        let nextPrimary = normalizedTargets.first?.providerId ?? primaryProviderID
        return normalizedRouteTargets(routeTargets: normalizedTargets, primaryProviderID: nextPrimary)
    }

    static func updateRouteTargetEnabled(
        routeTargets: [AdminRouteTargetInput],
        index: Int,
        enabled: Bool,
        primaryProviderID: String
    ) -> [AdminRouteTargetInput] {
        var normalizedTargets = normalizedRouteTargets(
            routeTargets: routeTargets,
            primaryProviderID: primaryProviderID
        )
        guard normalizedTargets.indices.contains(index) else {
            return normalizedTargets
        }

        normalizedTargets[index] = AdminRouteTargetInput(
            providerId: normalizedTargets[index].providerId,
            priority: normalizedTargets[index].priority,
            enabled: index == 0 ? true : enabled
        )
        return normalizedRouteTargets(routeTargets: normalizedTargets, primaryProviderID: primaryProviderID)
    }

    static func updateRouteTargetProvider(
        routeTargets: [AdminRouteTargetInput],
        index: Int,
        providerID: String,
        primaryProviderID: String
    ) -> [AdminRouteTargetInput] {
        var normalizedTargets = normalizedRouteTargets(
            routeTargets: routeTargets,
            primaryProviderID: primaryProviderID
        )
        guard normalizedTargets.indices.contains(index) else {
            return normalizedTargets
        }

        normalizedTargets[index] = AdminRouteTargetInput(
            providerId: providerID,
            priority: normalizedTargets[index].priority,
            enabled: normalizedTargets[index].enabled
        )
        let nextPrimary = index == 0 ? providerID : normalizedTargets.first?.providerId ?? primaryProviderID
        return normalizedRouteTargets(routeTargets: normalizedTargets, primaryProviderID: nextPrimary)
    }

    private static func defaultProtocolOptions(for kind: GatewayProtocolKind, locale: Locale = .autoupdatingCurrent) -> [GatewayPickerOption] {
        switch kind {
        case .inbound:
            return ProviderKindOption.allCases.map { option in
                GatewayPickerOption(
                    id: option.rawValue,
                    title: option.label,
                    subtitle: option.inboundProtocolSubtitle(locale: locale),
                    isFallback: false
                )
            }
        case .upstream:
            return [
                GatewayPickerOption(
                    id: "provider_default",
                    title: L10n.string("gateway_form.protocol.provider_default", locale: locale),
                    subtitle: L10n.string("gateway_form.protocol.provider_default.caption", locale: locale),
                    isFallback: false
                ),
            ] + ProviderKindOption.allCases.map { option in
                GatewayPickerOption(
                    id: option.rawValue,
                    title: option.label,
                    subtitle: option.upstreamProtocolSubtitle(locale: locale),
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

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var name = ""
    @State private var listenHost = "127.0.0.1"
    @State private var listenPort = "18080"
    @State private var inboundProtocol = "openai"
    @State private var upstreamProtocol = "provider_default"
    @State private var protocolConfigJSON = JSONValue.prettyPrinted(["compatibility_mode": .string("compatible")])
    @State private var defaultProviderID = ""
    @State private var routeTargets: [AdminRouteTargetInput] = []
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
            _routeTargets = State(initialValue: [])
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
            _routeTargets = State(
                initialValue: gateway.routeTargets
                    .sorted { $0.priority < $1.priority }
                    .map { AdminRouteTargetInput(providerId: $0.providerId, priority: $0.priority, enabled: $0.enabled) }
            )
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
                        SurfaceCard(title: L10n.string("gateway_form.section.identity", locale: locale)) {
                            VStack(alignment: .leading, spacing: 12) {
                                if isCreateMode {
                                    gatewayField(title: L10n.string("gateway_form.field.gateway_id", locale: locale), caption: L10n.string("gateway_form.field.gateway_id.caption_create", locale: locale)) {
                                        textInput(placeholder: "gateway_main", text: $id, monospaced: true)
                                    }
                                } else {
                                    gatewayField(title: L10n.string("gateway_form.field.gateway_id", locale: locale), caption: L10n.string("gateway_form.field.gateway_id.caption_edit", locale: locale)) {
                                        readOnlyValue(id, monospaced: true)
                                    }
                                }

                                gatewayField(title: L10n.string("gateway_form.field.display_name", locale: locale)) {
                                    textInput(placeholder: "Gateway Main", text: $name)
                                }

                                gatewayField(title: L10n.string("gateway_form.field.default_provider", locale: locale), caption: L10n.string("gateway_form.field.default_provider.caption", locale: locale)) {
                                    providerPicker
                                }

                                gatewayField(
                                    title: L10n.string(L10n.gatewayFormRouteTargetsPreviewTitle, locale: locale),
                                    caption: L10n.string(L10n.gatewayFormRouteTargetsPreviewCaption, locale: locale)
                                ) {
                                    routeTargetPreview
                                }

                                gatewayField(title: L10n.string("gateway_form.field.default_model", locale: locale), caption: L10n.string("gateway_form.field.default_model.caption", locale: locale)) {
                                    textInput(placeholder: "gpt-4o-mini", text: $defaultModel, monospaced: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        SurfaceCard(title: L10n.string("gateway_form.section.runtime", locale: locale)) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(L10n.string(enabled ? "gateway_form.runtime.routing_enabled" : "gateway_form.runtime.routing_disabled", locale: locale))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Spacer()
                                    Toggle(L10n.string("gateway_form.toggle.enabled", locale: locale), isOn: $enabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }

                                HStack {
                                    Text(L10n.string(autoStart ? "gateway_form.startup.auto_start_on_launch" : "gateway_form.startup.manual_short", locale: locale))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Spacer()
                                    Toggle(L10n.string("gateway_form.toggle.auto_start", locale: locale), isOn: $autoStart)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }

                                Text(L10n.string("gateway_form.runtime.snapshot_caption", locale: locale))
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)

                                dividerLine

                                VStack(alignment: .leading, spacing: 10) {
                                    gatewayMetaRow(label: L10n.string("gateway_form.meta.status", locale: locale), value: snapshot.runtimeStatus)
                                    gatewayMetaRow(label: L10n.string("gateway_form.meta.startup", locale: locale), value: snapshot.startupMode)
                                    gatewayMetaRow(label: L10n.string("gateway_form.meta.endpoint", locale: locale), value: snapshot.endpoint)
                                    gatewayMetaRow(label: L10n.string("gateway_form.meta.routing", locale: locale), value: snapshot.routingMode)
                                }
                            }
                        }
                        .frame(width: 240)
                    }

                    SurfaceCard(title: L10n.string("gateway_form.section.network_protocols", locale: locale)) {
                        HStack(alignment: .top, spacing: 12) {
                            gatewayField(title: L10n.string("gateway_form.field.listen_host", locale: locale), caption: L10n.string("gateway_form.field.listen_host.caption", locale: locale)) {
                                textInput(placeholder: "127.0.0.1", text: $listenHost, monospaced: true)
                            }

                            gatewayField(title: L10n.string("gateway_form.field.listen_port", locale: locale), caption: L10n.string("gateway_form.field.listen_port.caption", locale: locale)) {
                                textInput(placeholder: "18080", text: $listenPort, monospaced: true)
                            }

                            gatewayField(title: L10n.string("gateway_form.field.inbound_protocol", locale: locale), caption: L10n.string("gateway_form.field.inbound_protocol.caption", locale: locale)) {
                                protocolPicker(kind: .inbound, selection: $inboundProtocol)
                            }

                            gatewayField(title: L10n.string("gateway_form.field.upstream_protocol", locale: locale), caption: L10n.string("gateway_form.field.upstream_protocol.caption", locale: locale)) {
                                protocolPicker(kind: .upstream, selection: $upstreamProtocol)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        SurfaceCard(title: L10n.string("gateway_form.section.routing_json", locale: locale)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.string("gateway_form.routing_json.caption", locale: locale))
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

                        SurfaceCard(title: L10n.string("gateway_form.section.routing_targets", locale: locale)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.string("gateway_form.routing_targets.caption", locale: locale))
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)

                                if providers.isEmpty {
                                    Text(L10n.string("gateway_form.provider.none_yet", locale: locale))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                } else {
                                    routeTargetEditor
                                }
                            }
                        }
                        .frame(width: 320)
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
                                    Text(L10n.string("gateway_form.validation.review", locale: locale))
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
                    Text(L10n.string(isCreateMode ? "gateway_form.footer.create" : "gateway_form.footer.update", locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(snapshot.footerSummary)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer()

                Button(L10n.string("common.action.cancel", locale: locale)) {
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
                        Text(L10n.string(isCreateMode ? "gateway_form.action.create" : "common.action.save_changes", locale: locale))
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
            validationError = L10n.string("gateway_form.validation.id_required", locale: locale)
            return
        }

        guard !normalizedName.isEmpty, !normalizedHost.isEmpty, !normalizedProtocol.isEmpty, !normalizedUpstreamProtocol.isEmpty else {
            validationError = L10n.string("gateway_form.validation.required_fields", locale: locale)
            return
        }

        guard !normalizedProviderID.isEmpty else {
            validationError = L10n.string("gateway_form.validation.default_provider_required", locale: locale)
            return
        }

        guard let port = Int(listenPort.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) else {
            validationError = L10n.string("gateway_form.validation.listen_port_invalid", locale: locale)
            return
        }

        let parsedProtocolConfig: [String: JSONValue]
        do {
            parsedProtocolConfig = try JSONValue.parseObject(from: normalizedProtocolConfig.isEmpty ? "{}" : normalizedProtocolConfig)
        } catch {
            validationError = L10n.string("gateway_form.validation.routing_json_invalid", locale: locale)
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
                routeTargets: normalizedRouteTargets(primaryProviderID: normalizedProviderID),
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
                routeTargets: normalizedRouteTargets(primaryProviderID: normalizedProviderID),
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
            providers: providers,
            locale: locale
        )
    }

    private var editableRouteTargets: [AdminRouteTargetInput] {
        normalizedRouteTargets(primaryProviderID: defaultProviderID)
    }

    private var routeTargetPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(editableRouteTargets) { target in
                HStack(spacing: 8) {
                    Text("#\(target.priority)")
                        .font(.caption.monospaced())
                        .foregroundStyle(DesignTokens.textSecondary)
                    Text(target.providerId)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    Text(L10n.string(target.enabled ? L10n.resourceProviderStatusEnabled : L10n.resourceProviderStatusDisabled, locale: locale))
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
        }
    }

    private var routeTargetEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(editableRouteTargets.enumerated()), id: \.offset) { index, target in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(
                            index == 0
                                ? L10n.string(L10n.gatewayFormRouteTargetsPrimary, locale: locale)
                                : L10n.formatted(L10n.gatewayFormRouteTargetsBackup, locale: locale, Int64(index))
                        )
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(DesignTokens.textSecondary)
                        Spacer()
                        if index == 0 {
                            StatusPill(
                                text: L10n.string(L10n.gatewayFormRouteTargetsDefault, locale: locale),
                                semanticColor: DesignTokens.statusColors.running
                            )
                        }
                    }

                    Picker(
                        L10n.string(L10n.gatewayFormRouteTargetsPickerProvider, locale: locale),
                        selection: Binding(
                            get: { target.providerId },
                            set: { newValue in
                                applyRouteTargets(
                                    GatewayFormSupport.updateRouteTargetProvider(
                                        routeTargets: editableRouteTargets,
                                        index: index,
                                        providerID: newValue,
                                        primaryProviderID: defaultProviderID
                                    )
                                )
                            }
                        )
                    ) {
                        ForEach(routeTargetProviderOptions(for: index)) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignTokens.surfacePrimary.opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DesignTokens.borderSubtle.opacity(0.85), lineWidth: 1)
                    )

                    HStack(spacing: 8) {
                        Toggle(
                            L10n.string(L10n.resourceProviderStatusEnabled, locale: locale),
                            isOn: Binding(
                                get: { target.enabled },
                                set: { newValue in
                                    applyRouteTargets(
                                        GatewayFormSupport.updateRouteTargetEnabled(
                                            routeTargets: editableRouteTargets,
                                            index: index,
                                            enabled: newValue,
                                            primaryProviderID: defaultProviderID
                                        )
                                    )
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .disabled(index == 0)

                        Spacer()

                        smallActionButton(L10n.string(L10n.gatewayFormRouteTargetsMoveUp, locale: locale), systemImage: "arrow.up") {
                            applyRouteTargets(
                                GatewayFormSupport.moveRouteTarget(
                                    routeTargets: editableRouteTargets,
                                    from: index,
                                    to: index - 1,
                                    primaryProviderID: defaultProviderID
                                )
                            )
                        }
                        .disabled(index == 0)

                        smallActionButton(L10n.string(L10n.gatewayFormRouteTargetsMoveDown, locale: locale), systemImage: "arrow.down") {
                            applyRouteTargets(
                                GatewayFormSupport.moveRouteTarget(
                                    routeTargets: editableRouteTargets,
                                    from: index,
                                    to: index + 1,
                                    primaryProviderID: defaultProviderID
                                )
                            )
                        }
                        .disabled(index == editableRouteTargets.count - 1)

                        smallActionButton(L10n.string("common.action.delete", locale: locale), systemImage: "trash") {
                            applyRouteTargets(
                                GatewayFormSupport.removeRouteTarget(
                                    routeTargets: editableRouteTargets,
                                    index: index,
                                    primaryProviderID: defaultProviderID
                                )
                            )
                        }
                        .disabled(editableRouteTargets.count <= 1)
                    }

                    if index == 0 {
                        Text(L10n.string(L10n.gatewayFormRouteTargetsPrimaryHint, locale: locale))
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignTokens.surfacePrimary.opacity(0.76))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignTokens.borderSubtle.opacity(0.8), lineWidth: 1)
                )
            }

            Button {
                applyRouteTargets(
                    GatewayFormSupport.addRouteTarget(
                        routeTargets: editableRouteTargets,
                        availableProviderIDs: availableRouteTargetProviderIDs,
                        primaryProviderID: defaultProviderID
                    )
                )
            } label: {
                Label(L10n.string(L10n.gatewayFormRouteTargetsAdd, locale: locale), systemImage: "plus")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.surfacePrimary.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DesignTokens.borderSubtle.opacity(0.85), lineWidth: 1)
            )
            .disabled(unusedRouteTargetProviderIDs.isEmpty)
        }
    }

    private func normalizedRouteTargets(primaryProviderID: String) -> [AdminRouteTargetInput] {
        GatewayFormSupport.normalizedRouteTargets(
            routeTargets: routeTargets,
            primaryProviderID: primaryProviderID
        )
    }

    private var availableRouteTargetProviderIDs: [String] {
        let providerIDs = providers.map(\.id)
        guard providerIDs.isEmpty == false else {
            let fallback = defaultProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? [] : [fallback]
        }
        return providerIDs
    }

    private var unusedRouteTargetProviderIDs: [String] {
        let usedProviderIDs = Set(editableRouteTargets.map(\.providerId))
        return availableRouteTargetProviderIDs.filter { usedProviderIDs.contains($0) == false }
    }

    private func applyRouteTargets(_ updatedTargets: [AdminRouteTargetInput]) {
        let nextPrimary = updatedTargets.first?.providerId ?? defaultProviderID
        let normalizedTargets = GatewayFormSupport.normalizedRouteTargets(
            routeTargets: updatedTargets,
            primaryProviderID: nextPrimary
        )
        routeTargets = normalizedTargets
        if let providerID = normalizedTargets.first?.providerId {
            defaultProviderID = providerID
        }
    }

    private func routeTargetProviderOptions(for index: Int) -> [GatewayPickerOption] {
        guard editableRouteTargets.indices.contains(index) else {
            return []
        }

        let currentProviderID = editableRouteTargets[index].providerId
        let usedByOthers = Set(
            editableRouteTargets.enumerated().compactMap { offset, target in
                offset == index ? nil : target.providerId
            }
        )
        let baseOptions = providers
            .filter { provider in
                usedByOthers.contains(provider.id) == false || provider.id == currentProviderID
            }
            .map { provider in
                GatewayPickerOption(
                    id: provider.id,
                    title: provider.id,
                    subtitle: provider.name,
                    isFallback: false
                )
            }

        guard
            currentProviderID.isEmpty == false,
            baseOptions.contains(where: { $0.id == currentProviderID }) == false
        else {
            return baseOptions
        }

        return [
            GatewayPickerOption(
                id: currentProviderID,
                title: L10n.formatted("gateway_form.option.current_value", locale: locale, currentProviderID),
                subtitle: L10n.string("gateway_form.option.unavailable_provider", locale: locale),
                isFallback: true
            )
        ] + baseOptions
    }

    private var providerOptions: [GatewayPickerOption] {
        GatewayFormSupport.providerOptions(providers: providers, selectedProviderID: defaultProviderID, locale: locale)
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
            return L10n.string("gateway_form.validation.routing_json_invalid", locale: locale)
        }
    }

    private var gatewayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isCreateMode ? "point.3.connected.trianglepath.dotted" : "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(isCreateMode ? DesignTokens.statusColors.running.fill : DesignTokens.statusColors.warning.fill)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(isCreateMode ? "gateway_form.header.create" : "gateway_form.header.edit", locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(L10n.string("gateway_form.header.subtitle", locale: locale))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            StatusPill(
                text: L10n.string(enabled ? "provider_form.status.enabled" : "provider_form.status.disabled", locale: locale),
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
                Text(L10n.string(isCreateMode ? "gateway_form.summary.profile" : "gateway_form.summary.snapshot", locale: locale))
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
                compactMetric(title: L10n.string("gateway_form.metric.inbound", locale: locale), value: GatewayFormSupport.protocolTitle(for: inboundProtocol, kind: .inbound, locale: locale))
                compactMetric(title: L10n.string("gateway_form.metric.upstream", locale: locale), value: GatewayFormSupport.protocolTitle(for: upstreamProtocol, kind: .upstream, locale: locale))
                compactMetric(title: L10n.string("gateway_form.metric.provider", locale: locale), value: snapshot.providerLabel)
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
                readOnlyValue(L10n.string("gateway_form.provider.none_available", locale: locale))
            } else {
                Picker(L10n.string("gateway_form.field.default_provider", locale: locale), selection: $defaultProviderID) {
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
        let options = GatewayFormSupport.protocolOptions(kind: kind, selectedValue: selection.wrappedValue, locale: locale)

        return Picker(
            kind == .inbound ? L10n.string("gateway_form.field.inbound_protocol", locale: locale) : L10n.string("gateway_form.field.upstream_protocol", locale: locale),
            selection: selection
        ) {
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

    private func smallActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.surfaceSecondary.opacity(0.84))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
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
