import SwiftUI

extension View {
    func appNavigation(
        titleKey: LocalizedStringKey,
        displayMode: NavigationBarItem.TitleDisplayMode = .inline,
        hidesBackButton: Bool = false,
    ) -> some View {
        navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(displayMode)
            .navigationBarBackButtonHidden(hidesBackButton)
    }

    func appNavigationScrollEdgeStyle() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
    }

    func appNavigation(
        titleKey: LocalizedStringKey,
        displayMode: NavigationBarItem.TitleDisplayMode = .inline,
        hidesBackButton: Bool = false,
        @ToolbarContentBuilder leading: @escaping () -> some ToolbarContent,
    ) -> some View {
        navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(displayMode)
            .navigationBarBackButtonHidden(hidesBackButton)
            .toolbar {
                leading()
            }
    }

    func appNavigation(
        titleKey: LocalizedStringKey,
        displayMode: NavigationBarItem.TitleDisplayMode = .inline,
        hidesBackButton: Bool = false,
        @ToolbarContentBuilder leading: @escaping () -> some ToolbarContent,
        @ToolbarContentBuilder trailing: @escaping () -> some ToolbarContent,
    ) -> some View {
        navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(displayMode)
            .navigationBarBackButtonHidden(hidesBackButton)
            .toolbar {
                leading()
                trailing()
            }
    }
}
