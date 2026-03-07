import SwiftUI

struct SidebarView: View {
    let groups: [SidebarGroup]
    @Binding var selectedSection: SidebarSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FluxDeck")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)

                Text("Control Plane")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .textCase(.uppercase)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(DesignTokens.textSecondary.opacity(0.88))
                                .textCase(.uppercase)
                                .kerning(0.8)

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(group.items, id: \.self) { section in
                                    Button {
                                        selectedSection = section
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: section.icon)
                                                .frame(width: 16)
                                            Text(section.rawValue)
                                                .font(.subheadline.weight(isSelected(section) ? .semibold : .regular))
                                            Spacer(minLength: 0)
                                        }
                                        .foregroundStyle(isSelected(section) ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(background(for: section))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    DesignTokens.surfacePrimary.opacity(0.94),
                    DesignTokens.surfacePrimary.opacity(0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func isSelected(_ section: SidebarSection) -> Bool {
        selectedSection == section
    }

    @ViewBuilder
    private func background(for section: SidebarSection) -> some View {
        if isSelected(section) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        } else {
            Color.clear
        }
    }
}
