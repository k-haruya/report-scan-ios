//
//  WordExportService.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import Foundation
import UIKit
import ZIPFoundation

class WordExportService {

    /// XML 1.0不正制御文字を除去（タブ・改行・復帰以外のU+0000〜U+001F）
    private static func stripInvalidXMLCharacters(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            scalar.value == 0x9 || scalar.value == 0xA || scalar.value == 0xD ||
            (scalar.value >= 0x20 && scalar.value <= 0xD7FF) ||
            (scalar.value >= 0xE000 && scalar.value <= 0xFFFD) ||
            (scalar.value >= 0x10000 && scalar.value <= 0x10FFFF)
        }.map { Character($0) })
    }

    /// XML特殊文字をエスケープ
    private static func escapeXML(_ text: String) -> String {
        stripInvalidXMLCharacters(text)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// OCRテキストをシンプルなdocxファイルとして生成
    static func generateDOCX(text: String) throws -> Data {
        // メモリ上でZIPアーカイブを作成
        let archive = try Archive(data: Data(), accessMode: .create, pathEncoding: .utf8)
        
        // [Content_Types].xml
        let contentTypes = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
"""
        try addEntry(to: archive, path: "[Content_Types].xml", content: contentTypes)

        // _rels/.rels
        let rootRels = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""
        try addEntry(to: archive, path: "_rels/.rels", content: rootRels)

        // word/_rels/document.xml.rels
        let docRels = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>
"""
        try addEntry(to: archive, path: "word/_rels/document.xml.rels", content: docRels)

        // word/document.xml - メインコンテンツ
        let escapedText = escapeXML(text)
        
        let paragraphs = escapedText.components(separatedBy: "\n").map { line in
            "<w:p><w:r><w:t>\(line)</w:t></w:r></w:p>"
        }.joined()

        let documentXml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
\(paragraphs)
</w:body>
</w:document>
"""
        try addEntry(to: archive, path: "word/document.xml", content: documentXml)

        // アーカイブをDataとして取得
        guard let archiveData = archive.data else {
            throw WordExportError.archiveDataFailed
        }
        
        return archiveData
    }
    
    /// アーカイブにエントリを追加
    private static func addEntry(to archive: Archive, path: String, content: String) throws {
        guard let data = content.data(using: .utf8) else {
            throw WordExportError.encodingFailed
        }
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            let start = Int(position)
            let end = start + size
            return data.subdata(in: start..<end)
        }
    }

    enum WordExportError: LocalizedError {
        case archiveDataFailed
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .archiveDataFailed:
                return "DOCXデータの生成に失敗しました"
            case .encodingFailed:
                return "テキストのエンコードに失敗しました"
            }
        }
    }
}

