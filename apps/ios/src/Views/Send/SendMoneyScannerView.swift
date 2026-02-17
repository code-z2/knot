import SwiftUI
import UIKit

struct SendMoneyScanView: View {
  let onDismiss: () -> Void
  let onCodeScanned: (String) -> Bool

  @StateObject private var scanner = QRScannerController()
  @State private var dragOffset: CGFloat = 0
  @State private var scanSuccessTrigger = 0
  @Environment(\.openURL) private var openURL

  var body: some View {
    ZStack {
      QRCodeScannerPreview(session: scanner.session)
        .ignoresSafeArea()

      Color.black.opacity(0.22)
        .ignoresSafeArea()

      ScannerCrosshair()
        .frame(width: 244, height: 244)

      VStack {
        Spacer()
        flashlightButton
          .padding(.bottom, 116)
      }

      if let error = scanner.error {
        scannerErrorOverlay(error)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.horizontal, AppSpacing.lg)
          .padding(.bottom, 170)
      }
    }
    .ignoresSafeArea()
    .offset(y: dragOffset)
    .gesture(dragToDismissGesture)
    .accessibilityElement(children: .contain)
    .sensoryFeedback(AppHaptic.success.sensoryFeedback, trigger: scanSuccessTrigger) { _, _ in true }
    .onAppear {
      scanner.onCodeDetected = { payload in
        let accepted = onCodeScanned(payload)
        if accepted {
          scanSuccessTrigger += 1
          onDismiss()
        }
        return accepted
      }
      scanner.start()
    }
    .onDisappear {
      scanner.stop()
    }
  }

  private var flashlightButton: some View {
    Button {
      scanner.toggleTorch()
    } label: {
      ZStack {
        Circle()
          .fill(AppThemeColor.grayBlack.opacity(0.42))
          .overlay(
            Circle()
              .stroke(AppThemeColor.grayWhite.opacity(0.24), lineWidth: 1)
          )
          .background(
            Circle()
              .fill(.ultraThinMaterial)
          )

        Image(systemName: scanner.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(Color(hex: "#BFBFBF"))
      }
      .frame(width: 48, height: 48)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("send_money_scanner_toggle_flashlight"))
  }

  @ViewBuilder
  private func scannerErrorOverlay(_ error: QRScannerError) -> some View {
    VStack(spacing: 10) {
      Text(errorTitle(error))
        .font(.custom("Roboto-Bold", size: 14))
        .foregroundStyle(AppThemeColor.labelPrimary)

      Text(errorSubtitle(error))
        .font(.custom("Roboto-Regular", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .multilineTextAlignment(.center)

      if error == .permissionDenied {
        Button("send_money_open_settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          openURL(url, prefersInApp: true)
        }
        .font(.custom("Roboto-Bold", size: 13))
        .foregroundStyle(AppThemeColor.labelPrimary)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppThemeColor.fillPrimary)
        )
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, AppSpacing.sm)
    .background(
      RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous)
        .fill(AppThemeColor.grayBlack.opacity(0.62))
    )
  }

  private func errorTitle(_ error: QRScannerError) -> String {
    switch error {
    case .permissionDenied:
      return String(localized: "send_money_scanner_camera_access_needed")
    case .unavailable:
      return String(localized: "send_money_scanner_camera_unavailable")
    case .configurationFailed:
      return String(localized: "send_money_scanner_unavailable")
    }
  }

  private func errorSubtitle(_ error: QRScannerError) -> String {
    switch error {
    case .permissionDenied:
      return String(localized: "send_money_scanner_permission_subtitle")
    case .unavailable:
      return String(localized: "send_money_scanner_unavailable_subtitle")
    case .configurationFailed:
      return String(localized: "send_money_scanner_config_subtitle")
    }
  }

  private var dragToDismissGesture: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        dragOffset = max(0, value.translation.height)
      }
      .onEnded { value in
        let shouldDismiss = dragOffset > 110 || value.predictedEndTranslation.height > 180
        if shouldDismiss {
          withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) {
            dragOffset = 0
            onDismiss()
          }
        } else {
          withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
            dragOffset = 0
          }
        }
      }
  }
}

struct ScannerCrosshair: View {
  var body: some View {
    ZStack {
      corner(x: -90, y: -90, rotation: .degrees(0))
      corner(x: 90, y: -90, rotation: .degrees(90))
      corner(x: 90, y: 90, rotation: .degrees(180))
      corner(x: -90, y: 90, rotation: .degrees(270))
    }
  }

  private func corner(x: CGFloat, y: CGFloat, rotation: Angle) -> some View {
    RoundedCornerArc()
      .stroke(style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
      .foregroundStyle(AppThemeColor.grayWhite)
      .frame(width: 58, height: 58)
      .rotationEffect(rotation)
      .offset(x: x, y: y)
  }
}

struct RoundedCornerArc: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addArc(
      center: CGPoint(x: rect.maxX, y: rect.maxY),
      radius: rect.width,
      startAngle: .degrees(180),
      endAngle: .degrees(270),
      clockwise: false
    )
    return path
  }
}
