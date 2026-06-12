//
//  AppStrings.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/30.
//

import Foundation

/// アプリ全体で使用するUI文字列を一元管理する構造体
struct AppStrings {
    
    // MARK: - General Actions
    struct Actions {
        static let editImage = "画像を編集"
        static let addImage = "画像を追加"
        static let recognizeText = "テキストを認識"
        static let export = "エクスポート"
        static let save = "保存"
        static let cancel = "キャンセル"
        static let delete = "削除"
        static let rename = "名前変更"
        static let close = "閉じる"
    }
    
    // MARK: - Documents
    struct Documents {
        static let title = "ドキュメント"
        static let untitled = "無題のドキュメント"
        static let notFound = "ドキュメントが見つかりません"
        static let deleteConfirmation = "このドキュメントを削除してもよろしいですか？この操作は取り消せません。"
        static let noDocuments = "ドキュメントがありません"
        static let addInstructions = "スキャンまたは写真から読み込んでドキュメントを追加しましょう"
    }
    
    // MARK: - Folders
    struct Folders {
        static let title = "マイフォルダ"
        static let createNew = "新規フォルダ"
        static let enterName = "新しいフォルダの名前を入力してください"
        static let deleteConfirmation = "このフォルダと中のすべてのドキュメントを削除してもよろしいですか？この操作は取り消せません。"
    }
    
    // MARK: - Filter Names
    struct Filters {
        static let auto = "自動補正"
        static let original = "オリジナル"
        static let magic = "くっきり"
        static let grayscale = "白黒"
    }

    // MARK: - Scanner & Photo Picker
    struct Scanner {
        static let cameraLabel = "カメラで撮影"
        static let photoLabel = "写真から選択"
        static let scanDocument = "書類をスキャン"
        static let importFromPhoto = "写真から読み込む"
    }

    // MARK: - OCR
    struct OCR {
        static let title = "テキストを認識"
        static let startButton = "認識を開始"
        static let processingTitle = "テキストを認識中..."
        static let processingDescription = "画像から文字を読み取っています。\nしばらくお待ちください。"
        static let description = "ドキュメント内のテキストを自動認識します。\n日本語と英語に対応しています。"
        static let noTextFoundTitle = "テキストが見つかりませんでした"
        static let noTextFoundMessage = "画像内に認識可能なテキストがありませんでした。"
        static let retry = "もう一度試す"
        static let recognizedTextTitle = "認識されたテキスト"
        static let copyToClipboard = "クリップボードにコピー"
        static let copySuccessTitle = "コピー完了"
        static let copySuccessMessage = "テキストをクリップボードにコピーしました"
        static let copyFailed = "クリップボードへのコピーに失敗しました"
        static let saveFailed = "OCRテキストの保存に失敗しました"
    }
    
    // MARK: - Errors
    struct Errors {
        static let unknown = "不明なエラーが発生しました"
        static let saveFailed = "保存に失敗しました"
    }
}
