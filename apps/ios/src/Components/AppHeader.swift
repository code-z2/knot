import SwiftUI

struct AppHeader<Trailing: View>: View {
  let title: LocalizedStringKey
  let titleFont: Font
  let titleColor: Color
  let onBack: (() -> Void)?
  @ViewBuilder let trailing: Trailing

  init(
    title: LocalizedStringKey,
    titleFont: Font,
    titleColor: Color,
    onBack: (() -> Void)? = nil,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.titleFont = titleFont
    self.titleColor = titleColor
    self.onBack = onBack
    self.trailing = trailing()
  }

  init(
    title: LocalizedStringKey,
    titleFont: Font,
    titleColor: Color,
    onBack: (() -> Void)? = nil
  ) where Trailing == EmptyView {
    self.title = title
    self.titleFont = titleFont
    self.titleColor = titleColor
    self.onBack = onBack
    self.trailing = EmptyView()
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

        trailing
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
