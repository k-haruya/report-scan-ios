//
//  ScannedDocument.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftData
import Foundation

@Model
final class ScannedDocument {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var ocrText: String?

    // 画像データ（複数ページ対応）
    // @Attribute(.externalStorage): 外部ファイルに保存し、遅延ロードでメモリ節約
    @Attribute(.externalStorage)
    var imageData: [Data]

    // フィルター適用後の画像データ
    @Attribute(.externalStorage)
    var processedImageData: [Data]?

    // 各画像に適用中のフィルタータイプ（画像ごとに個別設定）
    var filterTypes: [String]  // 画像ごとのフィルター
    
    // 後方互換性のための計算プロパティ
    var filterType: String {
        get { filterTypes.first ?? "auto" }
        set { 
            if filterTypes.isEmpty {
                filterTypes = [newValue]
            } else {
                filterTypes[0] = newValue
            }
        }
    }

    // 所属フォルダ（nil = 未整理）
    var folder: DocumentFolder?

    init(title: String, imageData: [Data]) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.imageData = imageData
        // 各画像にデフォルトでスキャン強化フィルターを適用
        self.filterTypes = Array(repeating: "auto", count: imageData.count)
    }
    
    /// 画像追加時にフィルタータイプも追加
    func addImage(_ data: Data, filterType: String = "auto") {
        imageData.append(data)
        filterTypes.append(filterType)
    }
    
    /// 特定の画像のフィルタータイプを取得
    func getFilterType(at index: Int) -> String {
        guard index >= 0 && index < filterTypes.count else {
            return "auto"
        }
        return filterTypes[index]
    }
    
    /// 特定の画像のフィルタータイプを設定
    func setFilterType(_ filterType: String, at index: Int) {
        // 配列サイズの調整
        while filterTypes.count <= index {
            filterTypes.append("auto")
        }
        filterTypes[index] = filterType
    }
    
    // MARK: - Processed Image Management
    
    /// 表示用の画像データを取得（処理済みがあれば優先、なければ生データ）
    func getDisplayImage(at index: Int) -> Data? {
        // インデックスチェック
        guard index >= 0 && index < imageData.count else { return nil }
        
        // processedImageDataが存在し、インデックスが範囲内ならそれを返す
        if let processed = processedImageData,
           index < processed.count,
           !processed[index].isEmpty { // 空データチェックも念のため
            return processed[index]
        }
        
        // なければ生データを返す
        return imageData[index]
    }
    
    /// 加工済み画像を保存
    func saveProcessedImage(_ data: Data, at index: Int) {
        guard index >= 0 else { return }

        // processedImageDataがnilなら初期化
        if processedImageData == nil {
            processedImageData = []
        }

        // 配列サイズ調整（空データで埋め、getDisplayImageで空なら生データへフォールバック）
        while (processedImageData?.count ?? 0) <= index {
            processedImageData?.append(Data())
        }

        // データ保存
        processedImageData?[index] = data
        updatedAt = Date()
    }
    
    /// 加工済み画像をリセット（オリジナルに戻す）
    func resetProcessedImage(at index: Int) {
        guard index >= 0, let processed = processedImageData, index < processed.count else { return }
        processedImageData?[index] = Data() // 空にすることで生データへのフォールバックを有効化
        if index < filterTypes.count {
            filterTypes[index] = "original"
        }
        updatedAt = Date()
    }
}
