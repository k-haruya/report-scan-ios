import SwiftUI
import SwiftData

@MainActor
@Observable
class HomeViewModel {
    var modelContext: ModelContext?

    // フォルダとドキュメントの選択状態
    var selectedFolder: DocumentFolder?
    var selectedDocument: ScannedDocument?

    // 新規作成/編集用
    var showingFolderNameAlert = false
    var folderNameInput = ""
    var editingFolder: DocumentFolder?

    var showingDocumentNameAlert = false
    var documentNameInput = ""
    var editingDocument: ScannedDocument?

    // 削除確認
    var showingDeleteFolderAlert = false
    var folderToDelete: DocumentFolder?

    var showingDeleteDocumentAlert = false
    var documentToDelete: ScannedDocument?

    // エラー状態
    var showingErrorAlert = false
    var errorMessage = ""

    init() {}

    // MARK: - Error Handling

    private func handleSaveError(_ error: Error, operation: String) {
        errorMessage = "\(operation)に失敗しました: \(error.localizedDescription)"
        showingErrorAlert = true
    }

    private func handleContextError(operation: String) {
        errorMessage = "\(operation)に失敗しました: データベース接続が確立されていません"
        showingErrorAlert = true
    }

    private func ensureContext(for operation: String) -> ModelContext? {
        guard let context = modelContext else {
            handleContextError(operation: operation)
            return nil
        }
        return context
    }

    // MARK: - Folder Operations

    func createFolder(name: String) {
        guard let context = ensureContext(for: "フォルダの作成") else { return }
        let folder = DocumentFolder(name: name)
        context.insert(folder)

        do {
            try context.save()
        } catch {
            handleSaveError(error, operation: "フォルダの作成")
        }
    }

    func updateFolder(_ folder: DocumentFolder, name: String) {
        guard let context = ensureContext(for: "フォルダの更新") else { return }
        folder.name = name
        folder.updatedAt = Date()

        do {
            try context.save()
        } catch {
            handleSaveError(error, operation: "フォルダの更新")
        }
    }

    func deleteFolder(_ folder: DocumentFolder) {
        guard let context = ensureContext(for: "フォルダの削除") else { return }
        let folderId = folder.id
        context.delete(folder)

        do {
            try context.save()
            if selectedFolder?.id == folderId {
                selectedFolder = nil
            }
        } catch {
            handleSaveError(error, operation: "フォルダの削除")
        }
    }

    func showCreateFolderDialog() {
        folderNameInput = ""
        editingFolder = nil
        showingFolderNameAlert = true
    }

    func showEditFolderDialog(_ folder: DocumentFolder) {
        folderNameInput = folder.name
        editingFolder = folder
        showingFolderNameAlert = true
    }

    func confirmFolderName() {
        let trimmedName = folderNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let folder = editingFolder {
            updateFolder(folder, name: trimmedName)
        } else {
            createFolder(name: trimmedName)
        }

        showingFolderNameAlert = false
    }

    // MARK: - Document Operations

    func updateDocumentTitle(_ document: ScannedDocument, title: String) {
        guard let context = ensureContext(for: "ドキュメント名の変更") else { return }
        document.title = title
        document.updatedAt = Date()

        do {
            try context.save()
        } catch {
            handleSaveError(error, operation: "ドキュメント名の変更")
        }
    }

    func deleteDocument(_ document: ScannedDocument) {
        guard let context = ensureContext(for: "ドキュメントの削除") else { return }
        let documentId = document.id

        // アニメーションと同期させてList更新クラッシュを防止
        withAnimation {
            context.delete(document)

            do {
                try context.save()
                if selectedDocument?.id == documentId {
                    selectedDocument = nil
                }
            } catch {
                handleSaveError(error, operation: "ドキュメントの削除")
            }
        }
    }

    func moveDocument(_ document: ScannedDocument, to folder: DocumentFolder?) {
        guard let context = ensureContext(for: "ドキュメントの移動") else { return }
        document.folder = folder
        document.updatedAt = Date()

        do {
            try context.save()
        } catch {
            handleSaveError(error, operation: "ドキュメントの移動")
        }
    }

    func showEditDocumentDialog(_ document: ScannedDocument) {
        documentNameInput = document.title
        editingDocument = document
        showingDocumentNameAlert = true
    }

    func confirmDocumentName() {
        let trimmedName = documentNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let document = editingDocument {
            updateDocumentTitle(document, title: trimmedName)
        }

        showingDocumentNameAlert = false
    }

    // MARK: - Delete Confirmations

    func showDeleteFolderConfirmation(_ folder: DocumentFolder) {
        folderToDelete = folder
        showingDeleteFolderAlert = true
    }

    func confirmDeleteFolder() {
        if let folder = folderToDelete {
            deleteFolder(folder)
        }
        folderToDelete = nil
        showingDeleteFolderAlert = false
    }

    func showDeleteDocumentConfirmation(_ document: ScannedDocument) {
        documentToDelete = document
        showingDeleteDocumentAlert = true
    }

    func confirmDeleteDocument() {
        if let document = documentToDelete {
            deleteDocument(document)
        }
        documentToDelete = nil
        showingDeleteDocumentAlert = false
    }
}
