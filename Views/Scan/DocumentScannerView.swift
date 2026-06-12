//
//  DocumentScannerView.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftUI
import UIKit
import AVFoundation

struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var scannedImages: [UIImage]
    @Binding var scannerError: String?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> MultiPhotoCameraViewController {
        let controller = MultiPhotoCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MultiPhotoCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MultiPhotoCameraDelegate {
        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        func didCaptureImages(_ images: [UIImage]) {
            parent.scannedImages = images
            parent.dismiss()
        }

        func didCancel() {
            parent.dismiss()
        }
    }
}

// MARK: - Multi-Photo Camera Delegate Protocol

protocol MultiPhotoCameraDelegate: AnyObject {
    func didCaptureImages(_ images: [UIImage])
    func didCancel()
}

// MARK: - Custom Multi-Photo Camera View Controller

class MultiPhotoCameraViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    weak var delegate: MultiPhotoCameraDelegate?
    private var capturedImages: [UIImage] = []
    private var imagePicker: UIImagePickerController?
    private var hasPresentedCamera = false

    // カスタムオーバーレイのUI要素
    private weak var countLabel: UILabel?
    private weak var doneButton: UIButton?
    private weak var shutterButton: UIButton?
    private weak var closeButton: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasPresentedCamera {
            hasPresentedCamera = true
            presentCamera()
        }
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            delegate?.didCancel()
            return
        }

        // カメラ権限チェック
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.showCamera()
                    } else {
                        self?.delegate?.didCancel()
                    }
                }
            }
            return
        case .denied, .restricted:
            delegate?.didCancel()
            return
        case .authorized:
            break
        @unknown default:
            break
        }

        showCamera()
    }

    private func showCamera() {

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = self
        picker.showsCameraControls = false  // カスタムコントロールを使用
        self.imagePicker = picker

        // カメラプレビューを画面全体にフィット（4:3→フルスクリーン）
        let screenBounds = UIScreen.main.bounds
        let cameraAspectRatio: CGFloat = 4.0 / 3.0
        let previewHeight = screenBounds.width * cameraAspectRatio
        if previewHeight < screenBounds.height {
            let scale = screenBounds.height / previewHeight
            picker.cameraViewTransform = CGAffineTransform(scaleX: scale, y: scale)
        }

        present(picker, animated: true) { [weak self] in
            self?.setupOverlay()
        }
    }

    // MARK: - カスタムオーバーレイ

    private func setupOverlay() {
        guard let picker = imagePicker else { return }

        let overlay = UIView(frame: picker.view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = true

        // 閉じるボタン (top-left)
        let close = UIButton(type: .system)
        close.setTitle("閉じる", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        overlay.addSubview(close)
        self.closeButton = close

        // 撮影枚数ラベル (top-right)
        let count = UILabel()
        count.backgroundColor = UIColor.systemBlue
        count.textColor = .white
        count.font = .boldSystemFont(ofSize: 14)
        count.textAlignment = .center
        count.layer.cornerRadius = 16
        count.layer.masksToBounds = true
        count.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(count)
        self.countLabel = count

        // シャッターボタン (bottom-center)
        let shutter = createShutterButton()
        overlay.addSubview(shutter)
        self.shutterButton = shutter

        // 完了ボタン (bottom-right, シャッター横)
        let done = UIButton(type: .system)
        done.setTitle("完了", for: .normal)
        done.setTitleColor(.systemYellow, for: .normal)
        done.titleLabel?.font = .boldSystemFont(ofSize: 18)
        done.translatesAutoresizingMaskIntoConstraints = false
        done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        overlay.addSubview(done)
        self.doneButton = done

        NSLayoutConstraint.activate([
            // 閉じるボタン
            close.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 16),

            // 撮影枚数ラベル
            count.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            count.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
            count.heightAnchor.constraint(equalToConstant: 32),

            // シャッターボタン
            shutter.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            shutter.widthAnchor.constraint(equalToConstant: 72),
            shutter.heightAnchor.constraint(equalToConstant: 72),

            // 完了ボタン
            done.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -24),
        ])

        picker.cameraOverlayView = overlay
        updateOverlay()
    }

    private func createShutterButton() -> UIButton {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.layer.borderColor = UIColor.white.cgColor
        button.layer.borderWidth = 4
        button.layer.cornerRadius = 36

        let innerCircle = UIView()
        innerCircle.backgroundColor = .white
        innerCircle.layer.cornerRadius = 29
        innerCircle.isUserInteractionEnabled = false
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(innerCircle)

        NSLayoutConstraint.activate([
            innerCircle.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 58),
            innerCircle.heightAnchor.constraint(equalToConstant: 58),
        ])

        button.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        return button
    }

    private func updateOverlay() {
        let c = capturedImages.count
        countLabel?.text = " \(c)枚撮影済み "
        countLabel?.isHidden = c == 0
        doneButton?.isHidden = c == 0
    }

    // MARK: - Actions

    @objc private func shutterTapped() {
        shutterButton?.isEnabled = false  // 連打防止
        imagePicker?.takePicture()

        // 撮影フィードバック（フラッシュエフェクト）
        if let overlay = imagePicker?.cameraOverlayView {
            let flash = UIView(frame: overlay.bounds)
            flash.backgroundColor = .white
            flash.alpha = 0
            overlay.addSubview(flash)
            UIView.animate(withDuration: 0.1, animations: {
                flash.alpha = 0.5
            }) { _ in
                UIView.animate(withDuration: 0.15, animations: {
                    flash.alpha = 0
                }) { _ in
                    flash.removeFromSuperview()
                }
            }
        }
    }

    @objc private func closeTapped() {
        imagePicker?.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            if capturedImages.isEmpty {
                delegate?.didCancel()
            } else {
                delegate?.didCaptureImages(capturedImages)
            }
        }
    }

    @objc private func doneTapped() {
        guard !capturedImages.isEmpty else { return }
        imagePicker?.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            delegate?.didCaptureImages(capturedImages)
        }
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[.originalImage] as? UIImage {
            capturedImages.append(image)
        }
        // プレビューなしで連続撮影（dismiss→再表示でカメラ復帰）
        picker.dismiss(animated: false) { [weak self] in
            self?.presentCamera()
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            if capturedImages.isEmpty {
                delegate?.didCancel()
            } else {
                delegate?.didCaptureImages(capturedImages)
            }
        }
    }
}
