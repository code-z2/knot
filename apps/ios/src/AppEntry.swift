import SwiftData
import SwiftUI
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
        updatedAt: Date,
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
    init() {
        Self.ensureApplicationSupportDirectory()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [WalletActivityCache.self])
    }

    private static func ensureApplicationSupportDirectory() {
        guard
            let appSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
            ).first
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true,
                attributes: nil,
            )
        } catch {
            print("⚠️ [AppEntry] Failed to create Application Support directory: \(error.localizedDescription)")
        }
    }
}
