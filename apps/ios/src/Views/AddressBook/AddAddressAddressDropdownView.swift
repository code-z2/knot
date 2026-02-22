import SwiftUI

struct AddAddressAddressDropdownView: View {
    let beneficiaries: [Beneficiary]
    let onSelect: (Beneficiary) -> Void

    var body: some View {
        Group {
            if beneficiaries.isEmpty {
                Text("address_book_no_beneficiaries_found")
                    .font(.custom("Roboto-Regular", size: 13))
                    .foregroundStyle(AppThemeColor.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 36)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(beneficiaries) { beneficiary in
                            BeneficiaryRow(beneficiary: beneficiary) {
                                onSelect(beneficiary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 182)
            }
        }
    }
}
