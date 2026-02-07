import SwiftUI

enum SlideModalKind: Equatable {
  case fullHeight(topInset: CGFloat = 12)
  case compact(maxHeight: CGFloat = 280, horizontalInset: CGFloat = 12)
}

struct SlideModal<Content: View>: View {
  let isPresented: Bool
  let kind: SlideModalKind
  let onDismiss: () -> Void
  let content: () -> Content
  @State private var dragOffset: CGFloat = 0

  init(
    isPresented: Bool,
    kind: SlideModalKind = .fullHeight(),
    onDismiss: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.isPresented = isPresented
    self.kind = kind
    self.onDismiss = onDismiss
    self.content = content
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      if isPresented {
        Color.black.opacity(0.35)
          .ignoresSafeArea()
          .transition(.opacity)
          .contentShape(Rectangle())
          .onTapGesture {
            onDismiss()
          }

        panel
          .transition(.move(edge: .bottom))
      }
    }
    .animation(.default, value: isPresented)
    .onChange(of: isPresented) { _, presented in
      if !presented {
        dragOffset = 0
      }
    }
  }

  private var panel: some View {
    VStack(spacing: 0) {
      HStack {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
          .fill(AppThemeColor.gray2)
          .frame(width: 90, height: 5)
      }
      .frame(maxWidth: .infinity, minHeight: 25)
      .padding(.top, 12)
      .padding(.bottom, 8)
      .contentShape(Rectangle())
      .gesture(dragGesture)

      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity)
    .background(AppThemeColor.backgroundSecondary)
    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    .modifier(PanelLayout(kind: kind))
    .offset(y: dragOffset)
    .ignoresSafeArea(edges: .bottom)
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        dragOffset = max(0, value.translation.height)
      }
      .onEnded { value in
        let shouldDismiss = dragOffset > 90 || value.predictedEndTranslation.height > 140
        if shouldDismiss {
          dragOffset = 0
          onDismiss()
        } else {
          withAnimation(.default) {
            dragOffset = 0
          }
        }
      }
  }
}

private struct PanelLayout: ViewModifier {
  let kind: SlideModalKind

  func body(content: Content) -> some View {
    switch kind {
    case .fullHeight(let topInset):
      content
        .padding(.top, topInset)
    case .compact(let maxHeight, let horizontalInset):
      content
        .frame(maxHeight: maxHeight)
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, 8)
    }
  }
}

#Preview {
  ZStack {
    AppThemeColor.backgroundPrimary.ignoresSafeArea()
    SlideModal(isPresented: true, onDismiss: {}) {
      VStack {
        Text("Modal Content")
          .foregroundStyle(AppThemeColor.labelPrimary)
        Spacer()
      }
      .padding()
    }
  }
}
