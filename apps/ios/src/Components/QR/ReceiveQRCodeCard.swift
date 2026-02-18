import QRCode
import SwiftUI
import UIKit

struct ReceiveQRCodeCard: View {
    let address: String
    let onShare: ([Any]) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var qrImage: UIImage?

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text("receive_wallet_address")
                    .font(.custom("Roboto-Bold", size: 16))
                    .foregroundStyle(AppThemeColor.labelPrimary)

                Text(shortAddress)
                    .font(.custom("RobotoMono-Medium", size: 14))
                    .foregroundStyle(AppThemeColor.labelSecondary)
            }

            qrContainer
            shareButton
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(AppThemeColor.backgroundSecondary),
        )
        .task(id: qrTaskID) {
            regenerateQRCode()
        }
    }

    private var qrContainer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .fill(AppThemeColor.backgroundPrimary)

            if let qrImage {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(AppSpacing.sm)
            } else {
                ProgressView()
                    .tint(AppThemeColor.labelSecondary)
            }
        }
        .frame(height: 286)
    }

    private var shareButton: some View {
        HStack {
            AppButton(
                fullWidth: true,
                label: "receive_share",
                variant: .default,
                showIcon: true,
                iconName: "square.and.arrow.up",
                iconSize: 20,
            ) {
                onShare(shareItems)
            }
            .frame(height: 64)
        }
        .padding(.horizontal, AppSpacing.sm)
    }

    private var shortAddress: String {
        guard address.count > 12 else { return address }
        let prefix = String(address.prefix(6))
        let suffix = String(address.suffix(5))
        return "\(prefix)•••\(suffix)"
    }

    private var shareItems: [Any] {
        if let qrImage {
            return [qrImage, address]
        }
        return [address]
    }

    private var qrTaskID: String {
        "\(address)-\(colorScheme == .dark ? "dark" : "light")"
    }

    private func regenerateQRCode() {
        do {
            let document = try QRCode.Document(utf8String: address)
            document.errorCorrection = .high
            document.design.additionalQuietZonePixels = 2

            let accentStart = UIColor(
                colorScheme == .dark ? AppThemeColor.accentBrownDark : AppThemeColor.accentBrownLight,
            ).cgColor
            let accentEnd = UIColor(AppThemeColor.labelPrimary).cgColor
            let backgroundColor = UIColor(AppThemeColor.backgroundPrimary).cgColor
            let accentExtended = UIColor(AppThemeColor.accentBrown).cgColor

            document.design.style.background = QRCode.FillStyle.Solid(backgroundColor)
            let gradient = try DSFGradient(
                pins: [
                    DSFGradient.Pin(accentStart, 0),
                    DSFGradient.Pin(accentExtended, 0.24),
                    DSFGradient.Pin(accentEnd, 1),
                ],
            )
            let radial = QRCode.FillStyle.RadialGradient(
                gradient,
                centerPoint: CGPoint(x: 0.5, y: 0.5),
            )
            document.design.style.onPixels = radial
            document.design.style.eye = nil
            document.design.style.pupil = nil

            document.design.shape.onPixels = QRCode.PixelShape.Circle()
            document.design.shape.eye = QRCode.EyeShape.Squircle()
            document.design.shape.pupil = QRCode.PupilShape.Koala()

            if let logoCGImage = UIImage(named: "LogoMark")?.cgImage {
                document.logoTemplate = QRCode.LogoTemplate(
                    image: logoCGImage,
                    path: CGPath(ellipseIn: CGRect(x: 0.40, y: 0.40, width: 0.20, height: 0.20), transform: nil),
                    inset: 6,
                )
            }

            let cgImage = try document.cgImage(CGSize(width: 700, height: 700))
            qrImage = UIImage(cgImage: cgImage)
        } catch {
            qrImage = nil
        }
    }
}
