import SwiftUI

struct GatewayListView: View {
    @Environment(\.locale) private var locale
    let gateways: [AdminGateway]
    let isLoading: Bool
    let isSubmitting: Bool
    let error: String?
    let notice: String?
    let onCreate: () -> Void
    let onConfigure: (AdminGateway) -> Void
    let onToggleRuntime: (AdminGateway) -> Void
    let onDelete: (AdminGateway) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.string(L10n.gatewaysListTitle, locale: locale))
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    onCreate()
                } label: {
                    Label(L10n.string(L10n.gatewaysActionsNew, locale: locale), systemImage: "plus")
                }
                .focusable(false)
                .disabled(isSubmitting)
            }

            if let error {
                SurfaceCard {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.statusColors.error.fill)
                }
            }

            if let notice, !notice.isEmpty {
                SurfaceCard {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.statusColors.running.fill)
                }
            }

            if isLoading && gateways.isEmpty {
                SurfaceCard {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.string(L10n.gatewaysListLoading, locale: locale))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .font(.caption)
                }
            } else if gateways.isEmpty {
                EmptyStateView(
                    title: L10n.string(L10n.gatewaysListEmptyTitle, locale: locale),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    message: L10n.string(L10n.gatewaysListEmptyMessage, locale: locale)
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(gateways) { gateway in
                            let category = runtimeCategory(for: gateway)
                            let card = GatewayWorkspaceCard.make(gateway: gateway)

                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(card.title)
                                                .font(.headline)
                                                .foregroundStyle(DesignTokens.textPrimary)
                                            Text(card.id)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(DesignTokens.textSecondary)
                                        }
                                        Spacer()
                                        StatusPill(text: L10n.gatewayRuntimeStatus(card.runtimeState, locale: locale), semanticColor: colorToken(for: category))
                                    }

                                    resourceRow(label: L10n.string(L10n.gatewaysFieldsEndpoint, locale: locale), value: card.endpointText)
                                    resourceRow(label: L10n.string(L10n.gatewaysFieldsProvider, locale: locale), value: card.providerText)
                                    resourceRow(label: L10n.string(L10n.gatewaysFieldsAutoStart, locale: locale), value: L10n.autoStart(card.autoStartEnabled, locale: locale))
                                    resourceRow(label: L10n.string(L10n.gatewaysFieldsActiveProvider, locale: locale), value: activeProviderText(for: card))
                                    resourceRow(label: L10n.string(L10n.gatewaysFieldsRoutes, locale: locale), value: routeSummaryText(for: card))
                                    resourceRow(label: L10n.string(L10n.gatewaysFieldsHealth, locale: locale), value: healthSummaryText(for: card))

                                    if let lastError = card.lastErrorText, !lastError.isEmpty {
                                        resourceRow(label: L10n.string(L10n.gatewaysFieldsLastError, locale: locale), value: lastError)
                                    }

                                    HStack(spacing: 12) {
                                        Button(L10n.string(L10n.gatewaysActionsEdit, locale: locale)) {
                                            onConfigure(gateway)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .disabled(isSubmitting)

                                        Button(actionText(for: category)) {
                                            onToggleRuntime(gateway)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .disabled(isSubmitting)

                                        Button(L10n.string(L10n.gatewaysActionsDelete, locale: locale)) {
                                            onDelete(gateway)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.statusColors.error.fill)
                                        .disabled(isSubmitting)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if isSubmitting {
                SurfaceCard {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.string(L10n.gatewaysActionsApplying, locale: locale))
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorToken(for category: GatewayRuntimeCategory) -> DesignTokens.SemanticColor {
        switch category {
        case .running:
            return DesignTokens.statusColors.running
        case .stopped:
            return DesignTokens.statusColors.inactive
        case .error:
            return DesignTokens.statusColors.error
        case .unknown:
            return DesignTokens.statusColors.warning
        }
    }

    private func actionText(for category: GatewayRuntimeCategory) -> String {
        L10n.gatewayRuntimeAction(category, locale: locale)
    }

    private func activeProviderText(for card: GatewayWorkspaceCard) -> String {
        card.activeProviderText ?? L10n.string(L10n.gatewaysValueIdle, locale: locale)
    }

    private func routeSummaryText(for card: GatewayWorkspaceCard) -> String {
        guard card.routeTargets.isEmpty == false else {
            return card.providerText
        }

        return card.routeTargets
            .map { target in
                guard let healthStatus = target.healthStatus else {
                    return target.providerId
                }
                return L10n.formatted(
                    L10n.gatewaysRouteTargetWithHealth,
                    locale: locale,
                    target.providerId,
                    L10n.providerHealthStatus(healthStatus, locale: locale)
                )
            }
            .joined(separator: " -> ")
    }

    private func healthSummaryText(for card: GatewayWorkspaceCard) -> String {
        guard let summary = card.healthSummary else {
            return L10n.string(L10n.gatewaysHealthSummaryNone, locale: locale)
        }

        return L10n.formatted(
            L10n.gatewaysHealthSummaryFormat,
            locale: locale,
            Int64(summary.healthyCount),
            Int64(summary.degradedCount),
            Int64(summary.unhealthyCount),
            Int64(summary.probingCount)
        )
    }

    private func resourceRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
