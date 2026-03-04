import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case providers = "Providers"
    case gateways = "Gateways"
    case logs = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:
            return "square.grid.2x2"
        case .providers:
            return "shippingbox"
        case .gateways:
            return "point.3.connected.trianglepath.dotted"
        case .logs:
            return "list.bullet.rectangle.portrait"
        case .settings:
            return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var providers: [AdminProvider] = []
    @State private var gateways: [AdminGateway] = []
    @State private var logs: [AdminLog] = []
    @State private var selectedSection: SidebarSection? = .overview
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var loadError: String?
    @State private var lastRefreshedAt: Date?
    @State private var isProviderSheetPresented = false
    @State private var isGatewaySheetPresented = false
    @State private var selectedLogGateway = Self.logFilterAll
    @State private var selectedLogProvider = Self.logFilterAll
    @State private var selectedLogStatus = Self.logFilterAll
    @State private var logErrorsOnly = false
    private let client = AdminApiClient()

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section as SidebarSection?)
            }
            .navigationTitle("FluxDeck")
        } detail: {
            VStack(spacing: 0) {
                headerBar
                Divider()
                detailView(for: selectedSection ?? .overview)
            }
            .frame(minWidth: 920, minHeight: 560)
        }
        .task {
            await refreshAll()
        }
        .onAppear {
            selectedSection = selectedSection ?? .overview
        }
        .sheet(isPresented: $isProviderSheetPresented) {
            ProviderCreateSheet(isSubmitting: isSubmitting) { input in
                await createProvider(input)
            }
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
            OverviewView(metrics: buildDashboardMetrics(providers: providers, gateways: gateways), isLoading: isLoading)
        case .providers:
            ProviderListView(
                providers: providers,
                isLoading: isLoading,
                isSubmitting: isSubmitting,
                error: loadError,
                onCreate: { isProviderSheetPresented = true }
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
            LogsPanelView(
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
        case .settings:
            SettingsView(adminURL: client.displayBaseURL)
        }
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("FluxDeck Native")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Text("Admin: \(client.displayBaseURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ConnectionBadge(isLoading: isLoading, hasError: loadError != nil, hasSuccessfulSync: lastRefreshedAt != nil)

                Button {
                    Task {
                        await refreshAll()
                    }
                } label: {
                    if isLoading || isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isLoading || isSubmitting)
                .keyboardShortcut("r", modifiers: .command)
            }

            if let lastRefreshedAt {
                Text("Last refresh: \(Self.refreshFormatter.string(from: lastRefreshedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
}

private struct OverviewView: View {
    let metrics: DashboardMetrics
    let isLoading: Bool

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
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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

                Text("Showing \(logs.count) / \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isLoading && logs.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading logs...")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else if logs.isEmpty {
                EmptyStateView(
                    title: "No logs",
                    systemImage: "list.bullet.rectangle.portrait",
                    message: "No request logs match current filters."
                )
            } else {
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
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let adminURL: String

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Admin API", value: adminURL)
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

private struct ProviderCreateSheet: View {
    let isSubmitting: Bool
    let onSubmit: (CreateProviderInput) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var name = ""
    @State private var kind = "openai"
    @State private var baseURL = "https://api.openai.com/v1"
    @State private var apiKey = ""
    @State private var models = "gpt-4o-mini"
    @State private var enabled = true
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    TextField("ID", text: $id)
                    TextField("Name", text: $name)
                    TextField("Kind", text: $kind)
                    TextField("Base URL", text: $baseURL)
                    TextField("API Key", text: $apiKey)
                    TextField("Models (comma separated)", text: $models)
                    Toggle("Enabled", isOn: $enabled)
                }

                if let validationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        submit()
                    }
                    .disabled(isSubmitting)
                }
            }
            .frame(width: 520, height: 420)
        }
    }

    private func submit() {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedModels = models
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedID.isEmpty, !normalizedName.isEmpty, !normalizedBaseURL.isEmpty, !normalizedApiKey.isEmpty else {
            validationError = "ID, Name, Base URL and API Key are required."
            return
        }
        guard !parsedModels.isEmpty else {
            validationError = "At least one model is required."
            return
        }

        validationError = nil

        let input = CreateProviderInput(
            id: normalizedID,
            name: normalizedName,
            kind: kind.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: normalizedBaseURL,
            apiKey: normalizedApiKey,
            models: parsedModels,
            enabled: enabled
        )

        Task {
            await onSubmit(input)
        }
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
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        submit()
                    }
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

#Preview {
    ContentView()
}
