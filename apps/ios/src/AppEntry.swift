import SwiftUI
import SwiftData
import UIKit

@Model
final class WalletActivityCache {
  @Attribute(.unique) var id: String
  var walletAddress: String
  var supportMode: String
  var balanceSnapshot: Data?
  var transactionSnapshot: Data?
  var updatedAt: Date

  init(
    id: String,
    walletAddress: String,
    supportMode: String,
    balanceSnapshot: Data?,
    transactionSnapshot: Data?,
    updatedAt: Date
  ) {
    self.id = id
    self.walletAddress = walletAddress
    self.supportMode = supportMode
    self.balanceSnapshot = balanceSnapshot
    self.transactionSnapshot = transactionSnapshot
    self.updatedAt = updatedAt
  }
}

@main
struct AppEntry: App {
  var body: some Scene {
    WindowGroup {
      AppRootView()
    }
    .modelContainer(for: [WalletActivityCache.self])
  }
}
