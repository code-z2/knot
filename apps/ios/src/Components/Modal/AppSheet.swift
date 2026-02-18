import SwiftUI

enum AppSheetKind {
    case full
    case height(CGFloat)

    var detents: Set<PresentationDetent> {
        switch self {
        case .full:
            [.large]
        case let .height(value):
            [.height(value)]
        }
    }
}

struct AppSheet<Content: View>: View {
    let kind: AppSheetKind
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .presentationDetents(kind.detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .padding(.top, AppSpacing.xl)
    }
}
