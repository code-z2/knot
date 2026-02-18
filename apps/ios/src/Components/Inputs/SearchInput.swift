import SwiftUI

struct SearchInput: View {
    @Binding var text: String
    var placeholderKey: LocalizedStringKey = "search_placeholder"
    var width: CGFloat? = 185
    var onFocusChange: (Bool) -> Void = { _ in }
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            inputContent
                .frame(maxWidth: .infinity)

            if isFocused {
                dismissButton
                    .transition(.scale(scale: 0.75).combined(with: .opacity))
            }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isFocused)
        .onChange(of: isFocused) { _, newValue in
            onFocusChange(newValue)
        }
    }

    private var inputContent: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppThemeColor.labelSecondary)
                .frame(width: 16, height: 16)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholderKey)
                    .font(.custom("Inter-Regular", size: 16))
                    .foregroundStyle(AppThemeColor.labelSecondary),
            )
            .focused($isFocused)
            .submitLabel(.search)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .font(.custom("Inter-Regular", size: 16))
            .foregroundStyle(AppThemeColor.labelPrimary)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 10)
        .frame(height: 44)
        .clipShape(.capsule)
        .modifier(SearchFieldBackgroundModifier())
    }

    private var dismissButton: some View {
        Button {
            dismissSearchFocus()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppThemeColor.labelPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .clipShape(.circle)
        .modifier(SearchDismissButtonBackgroundModifier())
        .accessibilityLabel(Text("Dismiss search"))
    }

    private func dismissSearchFocus() {
        isFocused = false
    }
}

private struct SearchFieldBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(AppThemeColor.fillPrimary)
        }
    }
}

private struct SearchDismissButtonBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(AppThemeColor.fillPrimary)
        }
    }
}

#Preview {
    SearchInput(text: .constant(""))
        .padding()
        .background(AppThemeColor.fixedDarkSurface)
}
