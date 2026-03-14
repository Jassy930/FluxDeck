import SwiftUI

enum ShellConnectionState: Equatable {
    case syncing
    case offline
    case connected
}

struct ShellStatusSummary {
    let connectionState: ShellConnectionState
    let runningGatewayCount: Int
    let alertCount: Int
    let connectionColor: DesignTokens.SemanticColor
    let gatewayColor: DesignTokens.SemanticColor
    let errorColor: DesignTokens.SemanticColor

    static func make(
        isLoading: Bool,
        loadError: String?,
        gateways: [AdminGateway],
        locale _: Locale = .autoupdatingCurrent
    ) -> ShellStatusSummary {
        let runningCount = gateways.filter { runtimeCategory(for: $0) == .running }.count
        let gatewayErrorCount = gateways.filter { runtimeCategory(for: $0) == .error }.count
        let alertCount = gatewayErrorCount + (loadError == nil ? 0 : 1)

        let connectionState: ShellConnectionState
        let connectionColor: DesignTokens.SemanticColor
        if isLoading {
            connectionState = .syncing
            connectionColor = DesignTokens.statusColors.warning
        } else if gateways.isEmpty, loadError != nil {
            connectionState = .offline
            connectionColor = DesignTokens.statusColors.error
        } else {
            connectionState = .connected
            connectionColor = DesignTokens.statusColors.running
        }

        return ShellStatusSummary(
            connectionState: connectionState,
            runningGatewayCount: runningCount,
            alertCount: alertCount,
            connectionColor: connectionColor,
            gatewayColor: runningCount > 0 ? DesignTokens.statusColors.running : DesignTokens.statusColors.inactive,
            errorColor: alertCount > 0 ? DesignTokens.statusColors.error : DesignTokens.statusColors.inactive
        )
    }
}

struct AppShellView<Content: View>: View {
    let groups: [SidebarGroup]
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedMode: AppMode
    let toolbarModel: ShellToolbarModel
    let onRefresh: () -> Void
    let content: Content

    init(
        groups: [SidebarGroup],
        selectedSection: Binding<SidebarSection?>,
        selectedMode: Binding<AppMode>,
        toolbarModel: ShellToolbarModel,
        onRefresh: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.groups = groups
        self._selectedSection = selectedSection
        self._selectedMode = selectedMode
        self.toolbarModel = toolbarModel
        self.onRefresh = onRefresh
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DesignTokens.workbenchBackground,
                    DesignTokens.surfacePrimary.opacity(0.96),
                    Color.black.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarView(
                    groups: groups,
                    selectedSection: $selectedSection
                )
                .frame(width: 226)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.borderSubtle.opacity(0.0),
                                DesignTokens.borderSubtle.opacity(0.55),
                                DesignTokens.borderSubtle.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)

                VStack(spacing: 0) {
                    TopModeBar(
                        model: toolbarModel,
                        selectedMode: $selectedMode,
                        onRefresh: onRefresh
                    )
                    Divider()
                        .overlay(DesignTokens.borderSubtle)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
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
    }
}
