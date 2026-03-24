import Foundation

struct GasTankInformationChainItem: Identifiable, Hashable {
    let id: String
    let title: String
    let assetName: String?
    let fallbackHexColor: String?

    init(
        id: String,
        title: String,
        assetName: String? = nil,
        fallbackHexColor: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.assetName = assetName
        self.fallbackHexColor = fallbackHexColor
    }
}
