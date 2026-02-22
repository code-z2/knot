import PhotosUI
import SwiftUI
import UIKit

extension ProfileView {
    @MainActor
    func importPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw URLError(.cannotDecodeRawData)
            }
            try preparePendingAvatarUpload(from: data)
        } catch {
            showError(error)
        }
    }

    @MainActor
    func importFile(_ result: Result<[URL], any Error>) async {
        do {
            guard let fileURL = try result.get().first else { return }
            let didStart = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStart { fileURL.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: fileURL)
            try preparePendingAvatarUpload(from: data)
        } catch {
            showError(error)
        }
    }

    @MainActor
    func preparePendingAvatarUpload(from imageData: Data) throws {
        guard let image = UIImage(data: imageData),
              let jpegData = image.jpegData(compressionQuality: 0.86)
        else {
            throw URLError(.cannotDecodeRawData)
        }

        let fileName = "avatar-\(UUID().uuidString.lowercased()).jpg"
        _ = try imageStorageService.persistLocally(
            data: jpegData,
            eoaAddress: eoaAddress,
            fileName: fileName,
        )

        localAvatarImage = image
        pendingAvatarUpload = PendingAvatarUpload(
            id: UUID(),
            data: jpegData,
            mimeType: "image/jpeg",
            fileName: fileName,
        )
        startAvatarUploadIfNeeded()
    }

    @MainActor
    func ensureAvatarUploadCompletedIfNeeded() async throws {
        guard pendingAvatarUpload != nil else { return }

        if !isUploadingAvatar {
            startAvatarUploadIfNeeded()
        }
        await avatarUploadTask?.value

        if pendingAvatarUpload != nil {
            throw ProfileImageStorageError.pendingUpload
        }
    }

    @MainActor
    func startAvatarUploadIfNeeded() {
        guard let pendingAvatarUpload else { return }

        avatarUploadTask?.cancel()
        avatarUploadTask = Task {
            await runAvatarUpload(for: pendingAvatarUpload)
        }
    }

    @MainActor
    func runAvatarUpload(for pending: PendingAvatarUpload) async {
        isUploadingAvatar = true
        avatarUploadFlowState = .inProgress
        defer {
            if pendingAvatarUpload?.id == pending.id || pendingAvatarUpload == nil {
                isUploadingAvatar = false
            }
        }

        do {
            let uploadedURL = try await imageStorageService.uploadAvatar(
                data: pending.data,
                eoaAddress: eoaAddress,
                fileName: pending.fileName,
                mimeType: pending.mimeType,
            )

            guard pendingAvatarUpload?.id == pending.id else { return }
            avatarURL = uploadedURL.absoluteString
            pendingAvatarUpload = nil
            avatarUploadFlowState = .succeeded
        } catch is CancellationError {
            return
        } catch {
            guard pendingAvatarUpload?.id == pending.id else { return }
            avatarUploadFlowState = .failed(error.localizedDescription)
            showError(error)
        }
    }

    @MainActor
    func clearAvatarSelection() {
        avatarUploadTask?.cancel()
        avatarUploadTask = nil
        isUploadingAvatar = false
        avatarURL = ""
        localAvatarImage = nil
        pendingAvatarUpload = nil
        avatarUploadFlowState = .idle
    }
}
