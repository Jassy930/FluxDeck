import SwiftUI

struct ProviderListView: View {
    @Environment(\.locale) private var locale
    let providers: [AdminProvider]
    let providerHealthStates: [AdminProviderHealthState]
    let isLoading: Bool
    let isSubmitting: Bool
    let error: String?
    let onCreate: () -> Void
    let onConfigure: (AdminProvider) -> Void
    let onToggleEnabled: (AdminProvider) -> Void
    let onProbe: (AdminProvider) -> Void
    let onDelete: (AdminProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.string(L10n.providersListTitle, locale: locale))
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    onCreate()
                } label: {
                    Label(L10n.string(L10n.providersActionsNew, locale: locale), systemImage: "plus")
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

            if isLoading && providers.isEmpty {
                SurfaceCard {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.string(L10n.providersListLoading, locale: locale))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .font(.caption)
                }
            } else if providers.isEmpty {
                EmptyStateView(
                    title: L10n.string(L10n.providersListEmptyTitle, locale: locale),
                    systemImage: "shippingbox",
                    message: L10n.string(L10n.providersListEmptyMessage, locale: locale)
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(providers) { provider in
                            let card = ProviderWorkspaceCard.make(
                                provider: provider,
                                healthStates: providerHealthStates
                            )

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
                                        StatusPill(
                                            text: card.kindBadge,
                                            semanticColor: DesignTokens.statusColors.warning
                                        )
                                    }

                                    resourceRow(label: L10n.string(L10n.providersFieldsEndpoint, locale: locale), value: card.endpointText)
                                    resourceRow(label: L10n.string(L10n.providersFieldsModels, locale: locale), value: L10n.modelCount(card.modelCount, locale: locale))
                                    resourceRow(label: L10n.string(L10n.providersFieldsHealth, locale: locale), value: L10n.providerHealthStatus(card.healthStatus, locale: locale))

                                    if let healthDetail = card.healthDetailText {
                                        resourceRow(label: L10n.string(L10n.providersFieldsLastFailure, locale: locale), value: healthDetail)
                                    }

                                    StatusPill(
                                        text: L10n.providerStatus(card.isEnabled, locale: locale),
                                        semanticColor: provider.enabled ? DesignTokens.statusColors.running : DesignTokens.statusColors.inactive
                                    )

                                    StatusPill(
                                        text: L10n.providerHealthStatus(card.healthStatus, locale: locale),
                                        semanticColor: healthColor(for: card.healthStatus)
                                    )

                                    HStack(spacing: 12) {
                                        Button(L10n.string(L10n.providersActionsConfigure, locale: locale)) {
                                            onConfigure(provider)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .disabled(isSubmitting)

                                        Button(L10n.providerToggleAction(isEnabled: provider.enabled, locale: locale)) {
                                            onToggleEnabled(provider)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .disabled(isSubmitting)

                                        Button(L10n.string(L10n.providersActionsProbe, locale: locale)) {
                                            onProbe(provider)
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .foregroundStyle(DesignTokens.statusColors.warning.fill)
                                        .disabled(isSubmitting)

                                        Button(L10n.string(L10n.providersActionsDelete, locale: locale)) {
                                            onDelete(provider)
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
                        Text(L10n.string(L10n.providersActionsSubmitting, locale: locale))
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func healthColor(for status: String) -> DesignTokens.SemanticColor {
        switch status.lowercased() {
        case "degraded":
            return DesignTokens.statusColors.warning
        case "unhealthy":
            return DesignTokens.statusColors.error
        case "probing":
            return DesignTokens.statusColors.warning
        default:
            return DesignTokens.statusColors.running
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        SurfaceCard {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(12)
        }
    }
}
