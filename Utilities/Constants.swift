//
//  Constants.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import Foundation

enum Constants {
    // アプリ定数
    static let appName = "レポートスキャン"
    static let bundleIdentifier = "com.haruy.reportscan"

    // PDF設定
    static let pdfPageWidth: CGFloat = 595   // A4サイズ
    static let pdfPageHeight: CGFloat = 842  // A4サイズ

    // 日付フォーマッター（スレッドセーフ）
    // DateFormatterはスレッドセーフではないため、各スレッドでインスタンスを作成
    enum DateFormatters {
        private static let mediumDateTimeQueue = DispatchQueue(label: "com.haruy.reportscan.mediumDateTime")
        private static let documentNameQueue = DispatchQueue(label: "com.haruy.reportscan.documentName")

        private static let _mediumDateTime: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "ja_JP")
            return formatter
        }()

        private static let _documentName: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            formatter.locale = Locale(identifier: "ja_JP")
            return formatter
        }()

        static var mediumDateTime: ThreadSafeDateFormatter {
            ThreadSafeDateFormatter(formatter: _mediumDateTime, queue: mediumDateTimeQueue)
        }

        static var documentName: ThreadSafeDateFormatter {
            ThreadSafeDateFormatter(formatter: _documentName, queue: documentNameQueue)
        }
    }
}

// スレッドセーフなDateFormatterラッパー
struct ThreadSafeDateFormatter {
    private let formatter: DateFormatter
    private let queue: DispatchQueue

    init(formatter: DateFormatter, queue: DispatchQueue) {
        self.formatter = formatter
        self.queue = queue
    }

    func string(from date: Date) -> String {
        queue.sync {
            formatter.string(from: date)
        }
    }

    func date(from string: String) -> Date? {
        queue.sync {
            formatter.date(from: string)
        }
    }
}
