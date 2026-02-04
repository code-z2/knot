import SwiftUI

struct SearchInput: View {
  @Binding var text: String
  var placeholder: String = "Search"
  var width: CGFloat = 185

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .frame(width: 11, height: 11)

      TextField(placeholder, text: $text)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .font(.custom("Inter-Regular", size: 14))
        .foregroundStyle(AppThemeColor.labelSecondary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 9)
    .frame(width: width, height: 37)
    .background(AppThemeColor.fillPrimary)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

#Preview {
  SearchInput(text: .constant(""))
    .padding()
    .background(AppThemeColor.fixedDarkSurface)
}
