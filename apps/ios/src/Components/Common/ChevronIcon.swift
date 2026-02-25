import SwiftUI

struct ChevronIcon: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 14, height: 14)
            .foregroundStyle(AppThemeColor.glyphSecondary)
    }
}
