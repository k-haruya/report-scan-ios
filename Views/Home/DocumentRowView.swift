import SwiftUI
import ImageIO

struct DocumentRowView: View {
    let document: ScannedDocument

    var body: some View {
        HStack(spacing: 12) {
            // サムネイル（キャッシュ付き、処理済み画像があれば優先）
            ThumbnailView(
                imageData: document.getDisplayImage(at: 0),
                cacheKey: "\(document.id)-\(Int(document.updatedAt.timeIntervalSince1970))"
            )
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // 情報
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.caption)
                    Text("\(document.imageData.count)ページ")
                        .font(.caption)
                }
                .foregroundColor(.textSecondary)

                Text(formatDate(document.updatedAt))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func formatDate(_ date: Date) -> String {
        Constants.DateFormatters.mediumDateTime.string(from: date)
    }
}

// MARK: - Thumbnail Cache

/// サムネイル画像のメモリキャッシュ（リスト再描画時の再生成を防止）
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 100
    }

    func thumbnail(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setThumbnail(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

// MARK: - Thumbnail View with Async Loading + Cache

struct ThumbnailView: View {
    let imageData: Data?
    var cacheKey: String = ""

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "doc.text")
                            .foregroundColor(.gray)
                    )
            }
        }
        .task(id: cacheKey) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        // キャッシュから取得を試みる
        if !cacheKey.isEmpty,
           let cached = ThumbnailCache.shared.thumbnail(forKey: cacheKey) {
            thumbnail = cached
            return
        }

        // なければバックグラウンドで生成
        guard let data = imageData else { return }
        let key = cacheKey

        let result = await Task.detached(priority: .utility) {
            Self.createThumbnail(from: data, maxSize: 120)
        }.value

        guard let image = result else { return }

        // キャッシュに保存
        if !key.isEmpty {
            ThumbnailCache.shared.setThumbnail(image, forKey: key)
        }
        thumbnail = image
    }

    /// フル解像度をデコードせず、サムネイルサイズでデコード（省メモリ）
    nonisolated private static func createThumbnail(from data: Data, maxSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
