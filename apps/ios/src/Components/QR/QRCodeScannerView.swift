import AVFoundation
import Combine
import SwiftUI
import UIKit

enum QRScannerError: Equatable {
    case permissionDenied
    case unavailable
    case configurationFailed
}

final class QRScannerController: NSObject, ObservableObject {
    @Published private(set) var error: QRScannerError?
    @Published private(set) var isTorchEnabled = false

    let session = AVCaptureSession()
    var onCodeDetected: ((String) -> Bool)?
    private let metadataDelegate = QRScannerMetadataDelegate()

    private let sessionQueue = DispatchQueue(label: "fi.knot.qr-scanner")
    private var isConfigured = false
    private var isProcessing = false

    override init() {
        super.init()
        metadataDelegate.onCodeDetected = { [weak self] code in
            self?.handleDetectedCode(code)
        }
    }

    func start() {
        isProcessing = false

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    configureAndStartIfNeeded()
                } else {
                    DispatchQueue.main.async {
                        self.error = .permissionDenied
                    }
                }
            }
        case .denied, .restricted:
            error = .permissionDenied
        @unknown default:
            error = .unavailable
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if session.isRunning {
                session.stopRunning()
            }
            if isTorchEnabled {
                setTorch(enabled: false)
            }
        }
    }

    func toggleTorch() {
        setTorch(enabled: !isTorchEnabled)
    }

    private func configureAndStartIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if isConfigured {
                if !session.isRunning {
                    session.startRunning()
                }
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .high

            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.error = .unavailable }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { self.error = .configurationFailed }
                    return
                }
                session.addInput(input)
            } catch {
                session.commitConfiguration()
                DispatchQueue.main.async { self.error = .configurationFailed }
                return
            }

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.error = .configurationFailed }
                return
            }

            session.addOutput(output)
            output.setMetadataObjectsDelegate(metadataDelegate, queue: .main)
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()

            isConfigured = true
            DispatchQueue.main.async {
                self.error = nil
            }

            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func setTorch(enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                camera.hasTorch
            else { return }

            do {
                try camera.lockForConfiguration()
                camera.torchMode = enabled ? .on : .off
                camera.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isTorchEnabled = enabled
                }
            } catch {
                // Torch toggling failure should not block scanning.
            }
        }
    }

    private func handleDetectedCode(_ code: String) {
        guard !isProcessing else { return }
        isProcessing = true

        let accepted = onCodeDetected?(code) ?? false
        if accepted {
            stop()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isProcessing = false
        }
    }
}

private final class QRScannerMetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let callbackLock = NSLock()
    private nonisolated(unsafe) var callback: ((String) -> Void)?

    nonisolated var onCodeDetected: ((String) -> Void)? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return callback
        }
        set {
            callbackLock.lock()
            callback = newValue
            callbackLock.unlock()
        }
    }

    nonisolated func metadataOutput(
        _: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from _: AVCaptureConnection,
    ) {
        guard
            let readableObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let code = readableObject.stringValue
        else {
            return
        }

        onCodeDetected?(code)
    }
}

struct QRCodeScannerPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> ScannerPreviewView {
        let view = ScannerPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: ScannerPreviewView, context _: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

final class ScannerPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
