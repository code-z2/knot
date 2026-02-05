import SwiftUI

struct AppHeader<ActionButton: View>: View {
  let title: LocalizedStringKey
  let titleFont: Font
  let titleColor: Color
  let onBack: (() -> Void)?
  @ViewBuilder let actionButton: ActionButton

  init(
    title: LocalizedStringKey,
    titleFont: Font,
    titleColor: Color,
    onBack: (() -> Void)? = nil,
    @ViewBuilder actionButton: () -> ActionButton
  ) {
    self.title = title
    self.titleFont = titleFont
    self.titleColor = titleColor
    self.onBack = onBack
    self.actionButton = actionButton()
  }

  init(
    title: LocalizedStringKey,
    titleFont: Font,
    titleColor: Color,
    onBack: (() -> Void)? = nil
  ) where ActionButton == EmptyView {
    self.title = title
    self.titleFont = titleFont
    self.titleColor = titleColor
    self.onBack = onBack
    self.actionButton = EmptyView()
  }

  var body: some View {
    ZStack {
      Text(title)
        .font(titleFont)
        .foregroundStyle(titleColor)
        .lineLimit(1)
        .frame(maxWidth: .infinity)

      HStack(spacing: 0) {
        if let onBack {
          BackNavigationButton(tint: titleColor, action: onBack)
        }

        Spacer(minLength: 0)

        actionButton
      }
    }
    .frame(height: AppHeaderMetrics.height)
    .padding(.horizontal, 16)
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    VStack(spacing: 0) {
      AppHeader(
        title: "address_book_title",
        titleFont: .custom("Roboto-Bold", size: 22),
        titleColor: AppThemeColor.labelSecondary,
        onBack: {}
      )
      Spacer()
    }
  }
}
