import Foundation

let defaultAdminBaseURL = "http://127.0.0.1:7777"

enum GatewayRuntimeCategory: String {
    case running
    case stopped
    case error
    case unknown
}

struct DashboardMetrics: Equatable {
    let providerCount: Int
    let gatewayCount: Int
    let runningGatewayCount: Int
    let errorGatewayCount: Int
}

struct CreateProviderInput: Encodable {
    let id: String
    let name: String
    let kind: String
    let baseURL: String
    let apiKey: String
    let models: [String]
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case baseURL = "base_url"
        case apiKey = "api_key"
        case models
        case enabled
    }
}

struct UpdateProviderInput: Encodable {
    let name: String
    let kind: String
    let baseURL: String
    let apiKey: String
    let models: [String]
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case kind
        case baseURL = "base_url"
        case apiKey = "api_key"
        case models
        case enabled
    }
}

struct CreateGatewayInput: Encodable {
    let id: String
    let name: String
    let listenHost: String
    let listenPort: Int
    let inboundProtocol: String
    let defaultProviderId: String
    let defaultModel: String?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case listenHost = "listen_host"
        case listenPort = "listen_port"
        case inboundProtocol = "inbound_protocol"
        case defaultProviderId = "default_provider_id"
        case defaultModel = "default_model"
        case enabled
    }
}

private struct AdminActionResponse: Decodable {
    let ok: Bool
}

struct AdminProvider: Decodable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let baseURL: String
    let apiKey: String
    let models: [String]
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case baseURL = "base_url"
        case apiKey = "api_key"
        case models
        case enabled
    }
}

struct AdminGateway: Decodable, Identifiable {
    let id: String
    let name: String
    let listenHost: String
    let listenPort: Int
    let inboundProtocol: String
    let defaultProviderId: String
    let enabled: Bool
    let runtimeStatus: String?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case listenHost = "listen_host"
        case listenPort = "listen_port"
        case inboundProtocol = "inbound_protocol"
        case defaultProviderId = "default_provider_id"
        case enabled
        case runtimeStatus = "runtime_status"
        case lastError = "last_error"
    }
}

struct AdminLog: Decodable, Identifiable {
    let requestID: String
    let gatewayID: String
    let providerID: String
    let model: String?
    let statusCode: Int
    let latencyMs: Int
    let error: String?
    let createdAt: String

    var id: String { requestID }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case gatewayID = "gateway_id"
        case providerID = "provider_id"
        case model
        case statusCode = "status_code"
        case latencyMs = "latency_ms"
        case error
        case createdAt = "created_at"
    }
}


struct AdminLogCursor: Decodable {
    let createdAt: String
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case requestID = "request_id"
    }
}

struct AdminLogPage: Decodable {
    let items: [AdminLog]
    let nextCursor: AdminLogCursor?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct AdminApiClient {
    let baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL = URL(string: defaultAdminBaseURL)!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchProviders() async throws -> [AdminProvider] {
        let data = try await get(path: "/admin/providers")
        return try Self.decodeProviders(from: data)
    }

    func fetchGateways() async throws -> [AdminGateway] {
        let data = try await get(path: "/admin/gateways")
        return try Self.decodeGateways(from: data)
    }

    func fetchLogs() async throws -> [AdminLog] {
        let page = try await fetchLogsPage(limit: 50)
        return page.items
    }

    func fetchDashboardLogs(limit: Int = 20) async throws -> [AdminLog] {
        let page = try await fetchLogsPage(limit: limit)
        return page.items
    }

    func fetchLogsPage(
        limit: Int = 50,
        cursor: AdminLogCursor? = nil,
        gatewayID: String? = nil,
        providerID: String? = nil,
        statusCode: Int? = nil,
        errorsOnly: Bool = false
    ) async throws -> AdminLogPage {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor_created_at", value: cursor.createdAt))
            queryItems.append(URLQueryItem(name: "cursor_request_id", value: cursor.requestID))
        }
        if let gatewayID, !gatewayID.isEmpty {
            queryItems.append(URLQueryItem(name: "gateway_id", value: gatewayID))
        }
        if let providerID, !providerID.isEmpty {
            queryItems.append(URLQueryItem(name: "provider_id", value: providerID))
        }
        if let statusCode {
            queryItems.append(URLQueryItem(name: "status_code", value: String(statusCode)))
        }
        if errorsOnly {
            queryItems.append(URLQueryItem(name: "errors_only", value: "true"))
        }

        let data = try await get(path: "/admin/logs", queryItems: queryItems)
        return try Self.decodeLogPage(from: data)
    }

    func createProvider(_ input: CreateProviderInput) async throws -> AdminProvider {
        let data = try await post(path: "/admin/providers", body: input)
        return try JSONDecoder().decode(AdminProvider.self, from: data)
    }

    func updateProvider(id: String, input: UpdateProviderInput) async throws -> AdminProvider {
        let data = try await put(path: "/admin/providers/\(id)", body: input)
        return try JSONDecoder().decode(AdminProvider.self, from: data)
    }

    func createGateway(_ input: CreateGatewayInput) async throws -> AdminGateway {
        let data = try await post(path: "/admin/gateways", body: input)
        return try JSONDecoder().decode(AdminGateway.self, from: data)
    }

    func startGateway(id: String) async throws {
        let data = try await post(path: "/admin/gateways/\(id)/start", body: EmptyRequest())
        let response = try JSONDecoder().decode(AdminActionResponse.self, from: data)
        guard response.ok else {
            throw URLError(.cannotParseResponse)
        }
    }

    func stopGateway(id: String) async throws {
        let data = try await post(path: "/admin/gateways/\(id)/stop", body: EmptyRequest())
        let response = try JSONDecoder().decode(AdminActionResponse.self, from: data)
        guard response.ok else {
            throw URLError(.cannotParseResponse)
        }
    }

    var displayBaseURL: String {
        baseURL.absoluteString
    }

    static func decodeProviders(from data: Data) throws -> [AdminProvider] {
        try JSONDecoder().decode([AdminProvider].self, from: data)
    }

    static func decodeGateways(from data: Data) throws -> [AdminGateway] {
        try JSONDecoder().decode([AdminGateway].self, from: data)
    }

    static func decodeLogs(from data: Data) throws -> [AdminLog] {
        try decodeLogPage(from: data).items
    }

    static func decodeLogPage(from data: Data) throws -> AdminLogPage {
        try JSONDecoder().decode(AdminLogPage.self, from: data)
    }

    private func get(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func post(path: String, body: some Encodable) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func put(path: String, body: some Encodable) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private struct EmptyRequest: Encodable {}

func runtimeCategory(for gateway: AdminGateway) -> GatewayRuntimeCategory {
    if gateway.lastError != nil {
        return .error
    }

    switch gateway.runtimeStatus?.lowercased() {
    case "running":
        return .running
    case "stopped":
        return .stopped
    case "error":
        return .error
    default:
        return .unknown
    }
}

func buildDashboardMetrics(providers: [AdminProvider], gateways: [AdminGateway]) -> DashboardMetrics {
    let runningCount = gateways.filter { runtimeCategory(for: $0) == .running }.count
    let errorCount = gateways.filter { runtimeCategory(for: $0) == .error }.count

    return DashboardMetrics(
        providerCount: providers.count,
        gatewayCount: gateways.count,
        runningGatewayCount: runningCount,
        errorGatewayCount: errorCount
    )
}

func filterLogs(
    _ logs: [AdminLog],
    gatewayID: String?,
    providerID: String?,
    statusCode: Int?,
    errorsOnly: Bool = false
) -> [AdminLog] {
    logs.filter { log in
        let gatewayMatched = gatewayID == nil || log.gatewayID == gatewayID
        let providerMatched = providerID == nil || log.providerID == providerID
        let statusMatched = statusCode == nil || log.statusCode == statusCode
        let errorMatched = !errorsOnly || log.statusCode >= 400 || log.error != nil
        return gatewayMatched && providerMatched && statusMatched && errorMatched
    }
}

func normalizedAdminBaseURL(_ rawValue: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
    guard let url = URL(string: candidate),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          url.host != nil
    else {
        return nil
    }

    return url
}

func recentLogs(_ logs: [AdminLog], limit: Int = 10) -> [AdminLog] {
    guard limit > 0 else {
        return []
    }

    let sorted = logs.sorted { lhs, rhs in
        let lhsDate = parseAdminLogDate(lhs.createdAt)
        let rhsDate = parseAdminLogDate(rhs.createdAt)

        switch (lhsDate, rhsDate) {
        case let (left?, right?):
            return left > right
        default:
            return lhs.createdAt > rhs.createdAt
        }
    }

    return Array(sorted.prefix(limit))
}

private func parseAdminLogDate(_ value: String) -> Date? {
    if let date = adminLogDateWithFractional.date(from: value) {
        return date
    }
    return adminLogDateWithoutFractional.date(from: value)
}

private let adminLogDateWithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let adminLogDateWithoutFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
