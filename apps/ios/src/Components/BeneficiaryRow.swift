import SwiftUI

struct BeneficiaryRow: View {
  let beneficiary: Beneficiary
  var onTap: (() -> Void)? = nil

  var body: some View {
    Group {
      if let onTap {
        Button(action: onTap) { rowContent }
          .buttonStyle(.plain)
      } else {
        rowContent
      }
    }
  }

  private var rowContent: some View {
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(AppThemeColor.fillPrimary)
        Text(initials)
          .font(.custom("RobotoMono-Medium", size: 14))
          .foregroundStyle(AppThemeColor.labelSecondary)
      }
      .frame(width: 37, height: 37)

      VStack(alignment: .leading, spacing: 4) {
        Text(beneficiary.name)
          .font(.custom("Inter-Medium", size: 14))
          .foregroundStyle(AppThemeColor.labelPrimary)

        Text(metaLine)
          .font(.custom("RobotoMono-Medium", size: 12))
          .foregroundStyle(AppThemeColor.labelSecondary)
      }

      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var shortAddress: String {
    AddressShortener.shortened(beneficiary.address)
  }

  private var initials: String {
    let parts = beneficiary.name
      .split(separator: " ")
      .prefix(2)
      .compactMap { $0.first }
    let chars = String(parts).uppercased()
    return chars.isEmpty ? "PA" : chars
  }

  private var metaLine: String {
    if let chain = beneficiary.chainLabel, !chain.isEmpty {
      return "\(chain)  •  \(shortAddress)"
    }
    return shortAddress
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    BeneficiaryRow(
      beneficiary: Beneficiary(
        name: "Vitalik",
        address: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193"
      )
    )
    .padding()
  }
}
