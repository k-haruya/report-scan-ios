//
//  PhotoPickerView.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftUI
import PhotosUI
import UIKit

struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Binding var loadError: String?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0 // 複数選択可能

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard !results.isEmpty else { return }

            let count = results.count
            let group = DispatchGroup()
            let imagesLock = NSLock()

            // 順序を保持するためにインデックス付き配列を使用
            var indexedImages: [(index: Int, image: UIImage)] = []
            indexedImages.reserveCapacity(count)

            for (index, result) in results.enumerated() {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    defer { group.leave() }
                    guard self != nil else { return }

                    if let error = error {
                        // エラーをメインスレッドで報告
                        DispatchQueue.main.async {
                            self?.parent.loadError = "画像の読み込みに失敗しました: \(error.localizedDescription)"
                        }
                        return
                    }

                    if let image = object as? UIImage {
                        imagesLock.lock()
                        defer { imagesLock.unlock() }
                        indexedImages.append((index: index, image: image))
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                // インデックス順にソートして順序を復元
                let sortedImages = indexedImages
                    .sorted { $0.index < $1.index }
                    .map { $0.image }
                self.parent.selectedImages = sortedImages
            }
        }
    }
}
