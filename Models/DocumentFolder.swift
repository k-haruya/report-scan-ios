//
//  DocumentFolder.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftData
import Foundation

@Model
final class DocumentFolder {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ScannedDocument.folder)
    var documents: [ScannedDocument]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.documents = []
    }
}
