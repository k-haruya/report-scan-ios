//
//  FilterPreviewView.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftUI

struct FilterPreviewView: View {
    let image: UIImage
    let filterType: FilterType

    /// 画像データのハッシュ値（UIImage.hashValueはポインタベースで不安定なため、データから生成）
    let imageDataHash: Int

    @State private var filteredImage: UIImage?
    @State private var isLoading = true

    /// プレビュー用の最大ピクセル数（長辺）
    /// iPhone画面解像度（~1290px幅）を超える必要はない
    private static let previewMaxDimension: CGFloat = 1500

    init(image: UIImage, filterType: FilterType, imageDataHash: Int = 0) {
        self.image = image
        self.filterType = filterType
        self.imageDataHash = imageDataHash
    }

    var body: some View {
        ZStack {
            // 常に画像を表示（フィルター適用前はオリジナル、適用後はフィルター済み）
            Image(uiImage: filteredImage ?? image)
                .resizable()
                .aspectRatio(contentMode: .fit)

            if isLoading && filteredImage == nil {
                // 初回ロード中のみ半透明スピナーをオーバーレイ
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.1))
        .task(id: "\(imageDataHash)-\(filterType.rawValue)") {
            await applyFilter()
        }
    }

    private func applyFilter() async {
        isLoading = true

        // フィルター処理をバックグラウンドで実行
        let task = Task(priority: .userInitiated) { [image, filterType] in
            // フル解像度でフィルター適用（パラメーターはフル解像度用にチューニング済み）
            let filtered: UIImage
            if filterType == .original {
                filtered = image
            } else {
                filtered = ImageFilterService.shared.applyFilter(filterType, to: image) ?? image
            }
            // フィルター適用後にダウンサンプル（表示のパフォーマンス最適化）
            return Self.downsample(filtered, maxDimension: Self.previewMaxDimension)
        }
        let result = await task.value

        // キャンセル後にstale結果を適用しない
        guard !Task.isCancelled else { return }

        filteredImage = result
        isLoading = false
    }

    /// メモリ効率的にダウンサンプル
    private static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        guard scale < 1.0 else { return image }

        let newSize = CGSize(width: round(size.width * scale), height: round(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
