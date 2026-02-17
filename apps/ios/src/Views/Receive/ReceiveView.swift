import SwiftUI
import UIKit

struct ReceiveView: View {
  let address: String
  var onBack: () -> Void = {}
  @State private var activityItems: [Any]?

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      VStack {
        ReceiveQRCodeCard(address: address) { items in
          activityItems = items
        }
        .frame(maxWidth: 351)
        .padding(.top, 44)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 20)
      .padding(.top, AppHeaderMetrics.contentTopPadding)
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      AppHeader(
        title: "receive_title",
        titleFont: .custom("Roboto-Bold", size: 22),
        titleColor: AppThemeColor.labelSecondary,
        onBack: onBack
      )
    }
    .background {
      ActivityViewPresenter(activityItems: $activityItems)
        .frame(width: 0, height: 0)
    }
  }
}

private struct ActivityViewPresenter: UIViewControllerRepresentable {
  @Binding var activityItems: [Any]?

  func makeUIViewController(context: Context) -> UIViewController {
    UIViewController()
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    guard let items = activityItems, context.coordinator.presenter == nil else { return }
    let activityBinding = _activityItems

    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.modalPresentationStyle = .automatic
    controller.completionWithItemsHandler = { _, _, _, _ in
      context.coordinator.presenter = nil
      activityBinding.wrappedValue = nil
    }

    if let popover = controller.popoverPresentationController {
      popover.sourceView = uiViewController.view
      popover.sourceRect = CGRect(
        x: uiViewController.view.bounds.midX,
        y: uiViewController.view.bounds.maxY - 1,
        width: 1,
        height: 1
      )
    }

    context.coordinator.presenter = controller
    uiViewController.present(controller, animated: true)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator {
    var presenter: UIActivityViewController?
  }
}

#Preview {
  ReceiveView(address: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193")
}
