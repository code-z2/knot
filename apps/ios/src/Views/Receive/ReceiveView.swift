import SwiftUI
import UIKit

struct ReceiveView: View {
  let address: String
  var onBack: () -> Void = {}

  @State private var copied = false
  @State private var showShareSheet = false

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      VStack(spacing: 0) {
        VStack(spacing: 36) {
          StylizedQRCodeView(
            content: address,
            size: 217,
            foreground: AppThemeColor.labelPrimary,
            logo: "LogoMark"
          )

          addressCard
            .frame(maxWidth: .infinity)

          AppButton(
            fullWidth: true,
            label: "receive_share",
            variant: .default,
            showIcon: true,
            iconName: "Icons/share_02",
            backgroundColorOverride: AppThemeColor.accentBrown
          ) {
            showShareSheet = true
          }
          .frame(height: 52)
        }
        .padding(.top, 56)
        .frame(maxWidth: 314)

        Spacer()
      }
      .frame(maxWidth: .infinity)
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
    .sheet(isPresented: $showShareSheet) {
      ActivitySheet(items: [address])
    }
  }

  private var addressCard: some View {
    VStack(alignment: .trailing, spacing: 8) {
      Text(address)
        .font(.custom("RobotoFlex-Regular_Light", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .lineLimit(1)
        .kerning(0.12)

      Button {
        UIPasteboard.general.string = address
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
      } label: {
        HStack(spacing: 10) {
          Text(copied ? "receive_copied" : "receive_tap_to_copy")
            .font(.custom("Roboto-Medium", size: 12))
            .foregroundStyle(AppThemeColor.labelPrimary)

          Image("Icons/copy_02")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .foregroundStyle(AppThemeColor.labelPrimary)
        }
      }
      .buttonStyle(.plain)
      .frame(height: 26)
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(AppThemeColor.fillPrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(AppThemeColor.fillSecondary, lineWidth: 1)
    )
  }
}

private struct ActivitySheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
  ReceiveView(address: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193")
}
