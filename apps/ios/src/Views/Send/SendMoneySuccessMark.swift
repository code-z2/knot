import SwiftUI

struct SuccessCheckmark: View {
    @State private var isVisible = false

    var body: some View {
        GeometryReader { _ in
            Image("Icons/success_mark")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(127.0 / 123.0, contentMode: .fit)
                .foregroundStyle(AppThemeColor.accentGreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(isVisible ? 1.0 : 0.6)
                .opacity(isVisible ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                isVisible = true
            }
        }
    }
}
