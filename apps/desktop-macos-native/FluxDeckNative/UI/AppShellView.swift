import SwiftUI

struct ShellStatusSummary {
    let connectionLabel: String
    let gatewayLabel: String
    let errorLabel: String
    let connectionColor: DesignTokens.SemanticColor
    let gatewayColor: DesignTokens.SemanticColor
    let errorColor: DesignTokens.SemanticColor

    static func make(isLoading: Bool, loadError: String?, gateways: [AdminGateway]) -> ShellStatusSummary {
        let runningCount = gateways.filter { runtimeCategory(for: $0) == .running }.count
        let gatewayErrorCount = gateways.filter { runtimeCategory(for: $0) == .error }.count
        let alertCount = gatewayErrorCount + (loadError == nil ? 0 : 1)

        let connectionLabel: String
        let connectionColor: DesignTokens.SemanticColor
        if isLoading {
            connectionLabel = "Syncing"
            connectionColor = DesignTokens.statusColors.warning
        } else if gateways.isEmpty, loadError != nil {
            connectionLabel = "Offline"
            connectionColor = DesignTokens.statusColors.error
        } else {
            connectionLabel = "Connected"
            connectionColor = DesignTokens.statusColors.running
        }

        let gatewayLabel = runningCount == 1 ? "1 running" : "\(runningCount) running"
        let errorLabel = alertCount == 1 ? "1 alert" : "\(alertCount) alerts"

        return ShellStatusSummary(
            connectionLabel: connectionLabel,
            gatewayLabel: gatewayLabel,
            errorLabel: errorLabel,
            connectionColor: connectionColor,
            gatewayColor: runningCount > 0 ? DesignTokens.statusColors.running : DesignTokens.statusColors.inactive,
            errorColor: alertCount > 0 ? DesignTokens.statusColors.error : DesignTokens.statusColors.inactive
        )
    }
}

struct AppShellView<Content: View>: View {
    let title: String
    let groups: [SidebarGroup]
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedMode: AppMode
    let statusSummary: ShellStatusSummary
    let content: Content

    init(
        title: String,
        groups: [SidebarGroup],
        selectedSection: Binding<SidebarSection?>,
        selectedMode: Binding<AppMode>,
        statusSummary: ShellStatusSummary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.groups = groups
        self._selectedSection = selectedSection
        self._selectedMode = selectedMode
        self.statusSummary = statusSummary
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
                .frame(width: 244)

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
                        title: title,
                        selectedMode: $selectedMode,
                        statusSummary: statusSummary
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
