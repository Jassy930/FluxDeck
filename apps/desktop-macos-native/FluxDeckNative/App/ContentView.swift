import SwiftUI

struct ContentView: View {
    @AppStorage("fluxdeck.native.admin_base_url") private var persistedAdminBaseURL = defaultAdminBaseURL
    @State private var providers: [AdminProvider] = []
    @State private var gateways: [AdminGateway] = []
    @State private var logs: [AdminLog] = []
    @State private var selectedSection: SidebarSection? = .overview
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var loadError: String?
    @State private var lastRefreshedAt: Date?
    @State private var isProviderSheetPresented = false
    @State private var editingProvider: AdminProvider?
    @State private var isGatewaySheetPresented = false
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
            GatewayCreateSheet(
                providers: providers,
                isSubmitting: isSubmitting
            ) { input in
                await createGateway(input)
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .overview:
            OverviewDashboardView(
                model: OverviewDashboardModel.make(
                    providers: providers,
                    gateways: gateways,
                    logs: logs
                ),
                isLoading: isLoading,
                logs: recentLogs(logs),
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
                }
            )
        case .gateways:
            GatewayListView(
                gateways: gateways,
                isLoading: isLoading,
                isSubmitting: isSubmitting,
                error: loadError,
                onCreate: { isGatewaySheetPresented = true },
                onToggleRuntime: { gateway in
                    Task {
                        await toggleGatewayRuntime(gateway)
                    }
                }
            )
        case .logs:
            LogsWorkbenchView(
                logs: filteredLogs,
                totalCount: logs.count,
                isLoading: isLoading,
                error: loadError,
                gatewayOptions: gatewayLogOptions,
                providerOptions: providerLogOptions,
                statusOptions: statusLogOptions,
                selectedGateway: $selectedLogGateway,
                selectedProvider: $selectedLogProvider,
                selectedStatus: $selectedLogStatus,
                errorsOnly: $logErrorsOnly,
                onClearFilters: clearLogFilters
            )
        case .traffic:
            TrafficAnalyticsView(
                model: TrafficAnalyticsModel.make(logs: logs)
            )
        case .connections:
            ConnectionsView(
                model: ConnectionsModel.make(logs: logs)
            )
        case .topology:
            TopologyCanvasView(
                graph: TopologyGraph.make(
                    gateways: gateways,
                    providers: providers,
                    logs: logs
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
            async let logsTask = client.fetchLogs()

            let nextProviders = try await providerTask
            let nextGateways = try await gatewayTask
            let nextLogs = try await logsTask

            providers = nextProviders
            gateways = nextGateways
            logs = nextLogs
            normalizeLogFilters()
            loadError = nil
            lastRefreshedAt = Date()
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func createProvider(_ input: CreateProviderInput) async {
        isSubmitting = true

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
    private func createGateway(_ input: CreateGatewayInput) async {
        isSubmitting = true

        do {
            _ = try await client.createGateway(input)
            isGatewaySheetPresented = false
            loadError = nil
            await refreshAll()
        } catch {
            loadError = error.localizedDescription
        }

        isSubmitting = false
    }

    @MainActor
    private func toggleGatewayRuntime(_ gateway: AdminGateway) async {
        isSubmitting = true

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

    private var gatewayLogOptions: [String] {
        [Self.logFilterAll] + Array(Set(logs.map { $0.gatewayID })).sorted()
    }

    private var providerLogOptions: [String] {
        [Self.logFilterAll] + Array(Set(logs.map { $0.providerID })).sorted()
    }

    private var statusLogOptions: [String] {
        [Self.logFilterAll] + Array(Set(logs.map { String($0.statusCode) })).sorted()
    }

    private var filteredLogs: [AdminLog] {
        filterLogs(
            logs,
            gatewayID: selectedLogGateway == Self.logFilterAll ? nil : selectedLogGateway,
            providerID: selectedLogProvider == Self.logFilterAll ? nil : selectedLogProvider,
            statusCode: selectedLogStatus == Self.logFilterAll ? nil : Int(selectedLogStatus),
            errorsOnly: logErrorsOnly
        )
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

                                providerField(title: "Kind") {
                                    textInput(placeholder: "openai", text: $kind, monospaced: true)
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
                compactMetric(title: "Kind", value: kind.isEmpty ? "-" : kind)
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

private struct GatewayCreateSheet: View {
    let providers: [AdminProvider]
    let isSubmitting: Bool
    let onSubmit: (CreateGatewayInput) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var name = ""
    @State private var listenHost = "127.0.0.1"
    @State private var listenPort = "18080"
    @State private var inboundProtocol = "openai"
    @State private var defaultProviderID = ""
    @State private var defaultModel = "gpt-4o-mini"
    @State private var enabled = true
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    TextField("ID", text: $id)
                    TextField("Name", text: $name)
                    TextField("Listen Host", text: $listenHost)
                    TextField("Listen Port", text: $listenPort)
                    TextField("Inbound Protocol", text: $inboundProtocol)
                    TextField("Default Provider ID", text: $defaultProviderID)
                    TextField("Default Model (optional)", text: $defaultModel)
                    Toggle("Enabled", isOn: $enabled)
                }

                if !providers.isEmpty {
                    Section("Available Providers") {
                        ForEach(providers) { provider in
                            Text(provider.id)
                                .font(.caption)
                        }
                    }
                }

                if let validationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Gateway")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .focusable(false)
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        submit()
                    }
                    .focusable(false)
                    .disabled(isSubmitting)
                }
            }
            .frame(width: 560, height: 460)
        }
    }

    private func submit() {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProtocol = inboundProtocol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProviderID = defaultProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedID.isEmpty, !normalizedName.isEmpty, !normalizedHost.isEmpty, !normalizedProtocol.isEmpty, !normalizedProviderID.isEmpty else {
            validationError = "ID, Name, Host, Protocol and Default Provider ID are required."
            return
        }

        guard let port = Int(listenPort.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) else {
            validationError = "Listen Port must be a valid port number (1-65535)."
            return
        }

        validationError = nil

        let input = CreateGatewayInput(
            id: normalizedID,
            name: normalizedName,
            listenHost: normalizedHost,
            listenPort: port,
            inboundProtocol: normalizedProtocol,
            defaultProviderId: normalizedProviderID,
            defaultModel: normalizedModel.isEmpty ? nil : normalizedModel,
            enabled: enabled
        )

        Task {
            await onSubmit(input)
        }
    }
}
