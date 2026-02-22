import SwiftUI

struct AddAddressPrimaryButton: View {
    let canSave: Bool
    let isSaving: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("address_book_add")
                .font(.custom("Roboto-Bold", size: 15))
                .foregroundStyle(AppThemeColor.backgroundPrimary)
                .padding(.horizontal, 17)
                .padding(.vertical, 15)
                .frame(minWidth: 100)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSave || isSaving)
        .opacity(canSave && !isSaving ? 1 : 0)
        .animation(AppAnimation.standard, value: canSave)
        .tint(AppThemeColor.accentBrown)
    }
}
