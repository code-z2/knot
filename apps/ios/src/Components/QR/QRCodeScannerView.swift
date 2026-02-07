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

  private let sessionQueue = DispatchQueue(label: "com.peteranyaogu.metu.qr-scanner")
  private var isConfigured = false
  private var isProcessing = false

  func start() {
    isProcessing = false

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndStartIfNeeded()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self else { return }
        if granted {
          self.configureAndStartIfNeeded()
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
      if self.session.isRunning {
        self.session.stopRunning()
      }
      if self.isTorchEnabled {
        self.setTorch(enabled: false)
      }
    }
  }

  func toggleTorch() {
    setTorch(enabled: !isTorchEnabled)
  }

  private func configureAndStartIfNeeded() {
    sessionQueue.async { [weak self] in
      guard let self else { return }

      if self.isConfigured {
        if !self.session.isRunning {
          self.session.startRunning()
        }
        return
      }

      self.session.beginConfiguration()
      self.session.sessionPreset = .high

      guard
        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
      else {
        self.session.commitConfiguration()
        DispatchQueue.main.async { self.error = .unavailable }
        return
      }

      do {
        let input = try AVCaptureDeviceInput(device: camera)
        guard self.session.canAddInput(input) else {
          self.session.commitConfiguration()
          DispatchQueue.main.async { self.error = .configurationFailed }
          return
        }
        self.session.addInput(input)
      } catch {
        self.session.commitConfiguration()
        DispatchQueue.main.async { self.error = .configurationFailed }
        return
      }

      let output = AVCaptureMetadataOutput()
      guard self.session.canAddOutput(output) else {
        self.session.commitConfiguration()
        DispatchQueue.main.async { self.error = .configurationFailed }
        return
      }

      self.session.addOutput(output)
      output.setMetadataObjectsDelegate(self, queue: .main)
      output.metadataObjectTypes = [.qr]
      self.session.commitConfiguration()

      self.isConfigured = true
      DispatchQueue.main.async {
        self.error = nil
      }

      if !self.session.isRunning {
        self.session.startRunning()
      }
    }
  }

  private func setTorch(enabled: Bool) {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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
}

extension QRScannerController: AVCaptureMetadataOutputObjectsDelegate {
  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !isProcessing else { return }

    guard
      let readableObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
      let code = readableObject.stringValue
    else {
      return
    }

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

struct QRCodeScannerPreview: UIViewRepresentable {
  let session: AVCaptureSession

  func makeUIView(context: Context) -> ScannerPreviewView {
    let view = ScannerPreviewView()
    view.previewLayer.videoGravity = .resizeAspectFill
    view.previewLayer.session = session
    return view
  }

  func updateUIView(_ uiView: ScannerPreviewView, context: Context) {
    if uiView.previewLayer.session !== session {
      uiView.previewLayer.session = session
    }
  }
}

final class ScannerPreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

  var previewLayer: AVCaptureVideoPreviewLayer {
    layer as! AVCaptureVideoPreviewLayer
  }
}
