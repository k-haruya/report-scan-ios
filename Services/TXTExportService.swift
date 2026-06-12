//
//  TXTExportService.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import Foundation

class TXTExportService {
    static func generateTXT(from text: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw TXTExportError.encodingFailed
        }
        return data
    }

    enum TXTExportError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "テキストのエンコードに失敗しました"
            }
        }
    }
}
