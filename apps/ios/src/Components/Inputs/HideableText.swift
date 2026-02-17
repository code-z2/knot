import SwiftUI

struct HideableText: View {
  let text: String
  @Binding var isHidden: Bool
  var font: Font = .custom("RobotoMono-Medium", size: 24)
  var onToggle: (() -> Void)? = nil
  @State private var toggleTrigger = 0

  var body: some View {
    HStack(spacing: AppSpacing.xs) {
      if isHidden {
        Text("••••")
          .font(font)
          .tracking(-0.48)
          .foregroundStyle(AppThemeColor.labelPrimary)
          .frame(alignment: .leading)
          .contentTransition(.numericText())
      } else {
        Text(text)
          .font(font)
          .foregroundStyle(AppThemeColor.labelPrimary)
          .contentTransition(.numericText())
      }

      Button {
        toggleTrigger += 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
          isHidden.toggle()
        }
        onToggle?()
      } label: {
        Image(systemName: isHidden ? "eye.slash" : "eye")
          .font(.custom("RobotoMono-Bold", size: 16))
          .foregroundStyle(AppThemeColor.accentBrown)
          .contentTransition(.symbolEffect(.replace))
      }
      .buttonStyle(.plain)
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isHidden)
    .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: toggleTrigger) { _, _ in true }
  }
}

#Preview {
  VStack(spacing: 18) {
    HideableText(text: "Abcytg", isHidden: .constant(false))
    HideableText(text: "Abcytg", isHidden: .constant(true))
  }
  .padding()
  .background(AppThemeColor.fixedDarkSurface)
}
