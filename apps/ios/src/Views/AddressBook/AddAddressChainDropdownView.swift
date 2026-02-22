import SwiftUI

struct AddAddressChainDropdownView: View {
    @Binding var query: String
    let onSelect: (ChainOption) -> Void

    var body: some View {
        ChainList(query: query) { chain in
            onSelect(chain)
        }
        .frame(maxHeight: 360)
    }
}
