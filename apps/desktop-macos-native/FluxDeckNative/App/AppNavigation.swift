import Foundation

enum SidebarSection: String, CaseIterable, Hashable {
    case overview = "Overview"
    case traffic = "Traffic"
    case connections = "Connections"
    case logs = "Logs"
    case topology = "Topology"
    case routeMap = "Route Map"
    case providers = "Providers"
    case gateways = "Gateways"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .overview:
            return "square.grid.2x2"
        case .traffic:
            return "chart.line.uptrend.xyaxis"
        case .connections:
            return "point.3.filled.connected.trianglepath.dotted"
        case .logs:
            return "list.bullet.rectangle.portrait"
        case .topology:
            return "point.3.connected.trianglepath.dotted"
        case .routeMap:
            return "map"
        case .providers:
            return "shippingbox"
        case .gateways:
            return "switch.2"
        case .settings:
            return "gearshape"
        }
    }
}

struct SidebarGroup: Equatable {
    let title: String
    let items: [SidebarSection]

    static let defaultGroups: [SidebarGroup] = [
        SidebarGroup(title: "Overview", items: [.overview, .traffic, .connections, .logs]),
        SidebarGroup(title: "Visualization", items: [.topology, .routeMap]),
        SidebarGroup(title: "Proxy", items: [.providers, .gateways]),
        SidebarGroup(title: "System", items: [.settings])
    ]
}

enum AppMode: String, CaseIterable, Hashable {
    case backup = "Backup"
    case direct = "Direct"
    case rule = "Rule"
    case global = "Global"
}
