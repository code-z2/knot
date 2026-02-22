import SwiftUI

struct ProfileHeaderView: View {
    let hasChanges: Bool
    let isSaving: Bool
    let canSave: Bool
    let onBack: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            Text("profile_title")
                .font(.custom("Roboto-Bold", size: 22))
                .foregroundStyle(AppThemeColor.labelSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                if hasChanges {
                    cancelButton
                        .transition(.opacity)
                } else {
                    BackNavigationButton(tint: AppThemeColor.labelSecondary, action: onBack)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)

                if hasChanges {
                    saveButton
                        .transition(.opacity)
                }
            }
        }
        .frame(height: AppHeaderMetrics.height)
        .padding(.horizontal, AppSpacing.md)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("profile_cancel")
                .font(.custom("Roboto-Medium", size: 15))
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 6)
        }
        .foregroundStyle(AppThemeColor.labelPrimary)
        .disabled(isSaving)
        .modifier(ProfileGlassCapsuleButtonModifier())
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Text(isSaving ? "profile_saving" : "profile_save")
                .font(.custom("Roboto-Medium", size: 15))
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 6)
        }
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
        .modifier(ProfileProminentActionButtonModifier())
    }
}
