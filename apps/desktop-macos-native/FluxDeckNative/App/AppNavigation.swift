import Foundation

enum SidebarSection: String, CaseIterable, Hashable {
    case overview = "overview"
    case traffic = "traffic"
    case connections = "connections"
    case logs = "logs"
    case topology = "topology"
    case routeMap = "route_map"
    case providers = "providers"
    case gateways = "gateways"
    case settings = "settings"

    var titleKey: String {
        "sidebar.section.\(rawValue)"
    }

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

struct SidebarGroup: Equatable, Hashable {
    let id: String
    let titleKey: String
    let items: [SidebarSection]

    static let defaultGroups: [SidebarGroup] = [
        SidebarGroup(id: "overview", titleKey: "sidebar.group.overview", items: [.overview, .traffic, .connections, .logs]),
        SidebarGroup(id: "visualization", titleKey: "sidebar.group.visualization", items: [.topology, .routeMap]),
        SidebarGroup(id: "proxy", titleKey: "sidebar.group.proxy", items: [.providers, .gateways]),
        SidebarGroup(id: "system", titleKey: "sidebar.group.system", items: [.settings])
    ]
}

enum AppMode: String, CaseIterable, Hashable {
    case backup = "backup"
    case direct = "direct"
    case rule = "rule"
    case global = "global"

    var titleKey: String {
        "shell.mode.\(rawValue)"
    }
}
