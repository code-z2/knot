import SwiftUI

struct ChevronIcon: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 12, height: 12)
            .foregroundStyle(AppThemeColor.glyphSecondary)
    }
}
