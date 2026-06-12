import SwiftUI
import SwiftData

struct DocumentListView: View {
    @Bindable var viewModel: HomeViewModel
    let folder: DocumentFolder
    @Binding var navigationPath: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("imageQuality") private var imageQuality: Double = 0.8

    // スキャン関連の状態
    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var scannedImages: [UIImage] = []
    @State private var selectedPhotos: [UIImage] = []
    
    // 処理中の状態（LoadingOverlay用）
    @State private var isSaving = false
    @State private var loadingMessage = ""
    
    // エラー
    @State private var showScannerError = false
    @State private var scannerError: String?
    @State private var showPhotoPickerError = false
    @State private var photoPickerError: String?
    @State private var showingNameInput = false
    @State private var newDocumentName = ""
    @State private var saveErrorMessage = ""
    @State private var showSaveError = false
    @State private var saveTask: Task<Void, Never>?

    /// フォルダのリレーションから直接取得（DB全体スキャン不要）
    private var filteredDocuments: [ScannedDocument] {
        folder.documents.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ZStack {
            documentList
                .navigationTitle(folder.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                showingScanner = true
                            } label: {
                                Label(AppStrings.Scanner.cameraLabel, systemImage: "camera")
                            }
                            
                            Button {
                                showingPhotoPicker = true
                            } label: {
                                Label(AppStrings.Scanner.photoLabel, systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            
            if isSaving {
                LoadingOverlay(message: loadingMessage)
            }
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScannerView(scannedImages: $scannedImages, scannerError: $scannerError)
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPickerView(selectedImages: $selectedPhotos, loadError: $photoPickerError)
        }
        .onChange(of: scannedImages) { _, images in
            if !images.isEmpty {
                promptForDocumentName()
            }
        }
        .onChange(of: selectedPhotos) { _, images in
            if !images.isEmpty {
                promptForDocumentName()
            }
        }
        .onChange(of: scannerError) { _, error in
            if error != nil {
                showScannerError = true
            }
        }
        .onChange(of: photoPickerError) { _, error in
            if error != nil {
                showPhotoPickerError = true
            }
        }
        // 以下エラーアラートなどは省略せず（ここにある修飾子はそのまま維持したいが、replace範囲が広いと危険）
        .modifier(DocumentListAlerts(
            viewModel: viewModel,
            showingNameInput: $showingNameInput,
            newDocumentName: $newDocumentName,
            showSaveError: $showSaveError,
            saveErrorMessage: $saveErrorMessage,
            showScannerError: $showScannerError,
            scannerError: $scannerError,
            showPhotoPickerError: $showPhotoPickerError,
            photoPickerError: $photoPickerError,
            onSaveDocument: { saveDocument() },
            onResetScanState: resetScanState
        ))
        .onAppear {
            viewModel.modelContext = modelContext
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var documentList: some View {
        List {
            if filteredDocuments.isEmpty {
                emptyState
            } else {
                documentRows
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(AppStrings.Documents.noDocuments, systemImage: "doc")
        } description: {
            Text(AppStrings.Documents.addInstructions)
        }
    }

    private var documentRows: some View {
        ForEach(filteredDocuments) { document in
            Button {
                navigateToDocument(document)
            } label: {
                DocumentRowView(document: document)
            }
            .foregroundStyle(.primary) // デフォルトスタイル上書き
            // 長押しメニュー
            .contextMenu {
                Button {
                    viewModel.showEditDocumentDialog(document)
                } label: {
                    Label(AppStrings.Actions.rename, systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    viewModel.showDeleteDocumentConfirmation(document)
                } label: {
                    Label(AppStrings.Actions.delete, systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    viewModel.showDeleteDocumentConfirmation(document)
                } label: {
                    Label(AppStrings.Actions.delete, systemImage: "trash")
                }

                Button {
                    viewModel.showEditDocumentDialog(document)
                } label: {
                    Label(AppStrings.Actions.rename, systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Helper Methods

    private func promptForDocumentName() {
        newDocumentName = "スキャン \(Constants.DateFormatters.documentName.string(from: Date()))"
        showingNameInput = true
    }

    private func saveDocument() {
        let trimmedName = newDocumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let imagesToSave = !scannedImages.isEmpty ? scannedImages : selectedPhotos
        guard !imagesToSave.isEmpty else { return }

        // ローディング表示
        loadingMessage = "画像を保存中... (\(imagesToSave.count)枚)"
        isSaving = true
        
        // バックグラウンドで画像変換
        saveTask = Task {
            // 画像品質を処理開始時にキャプチャ
            let capturedQuality = imageQuality
            
            // 画像データに変換（バックグラウンド）
            let imageDataArray = await Task.detached(priority: .userInitiated) {
                imagesToSave.compactMap { $0.jpegData(compressionQuality: capturedQuality) }
            }.value
            
            // 画像変換失敗のチェック
            var warningMessage: String?
            if imageDataArray.count < imagesToSave.count {
                let droppedCount = imagesToSave.count - imageDataArray.count
                warningMessage = "\(droppedCount)枚の画像の変換に失敗しました。残りの画像は保存されます。"
            }

            guard !imageDataArray.isEmpty else {
                await MainActor.run {
                    isSaving = false
                    saveErrorMessage = "すべての画像の変換に失敗しました。"
                    showSaveError = true
                }
                return
            }
            
            await MainActor.run {
                loadingMessage = "データベースに保存中..."
            }

            // SwiftData操作は必ずMainActor上で実行
            await MainActor.run {
                let document = ScannedDocument(title: trimmedName, imageData: imageDataArray)
                document.folder = folder

                modelContext.insert(document)

                do {
                    try modelContext.save()
                    isSaving = false

                    // 保存成功後に警告を表示
                    if let warning = warningMessage {
                        saveErrorMessage = warning
                        showSaveError = true
                    }

                    resetScanState()
                } catch {
                    isSaving = false
                    // 保存失敗時はドキュメントをコンテキストから削除
                    modelContext.delete(document)
                    saveErrorMessage = "ドキュメントの保存に失敗しました: \(error.localizedDescription)"
                    showSaveError = true
                }
            }
        }
    }
    
    private func resetScanState() {
        scannedImages.removeAll()
        selectedPhotos.removeAll()
        newDocumentName = ""
    }

    private func navigateToDocument(_ document: ScannedDocument) {
        navigationPath.append(document.id)
    }
}

// MARK: - Alert Modifier (型チェック負荷軽減)

private struct DocumentListAlerts: ViewModifier {
    @Bindable var viewModel: HomeViewModel
    @Binding var showingNameInput: Bool
    @Binding var newDocumentName: String
    @Binding var showSaveError: Bool
    @Binding var saveErrorMessage: String
    @Binding var showScannerError: Bool
    @Binding var scannerError: String?
    @Binding var showPhotoPickerError: Bool
    @Binding var photoPickerError: String?
    let onSaveDocument: () -> Void
    let onResetScanState: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("ドキュメント名を変更", isPresented: $viewModel.showingDocumentNameAlert) {
                TextField("ドキュメント名", text: $viewModel.documentNameInput)
                Button("キャンセル", role: .cancel) {}
                Button("保存") { viewModel.confirmDocumentName() }
            }
            .alert("新規ドキュメント", isPresented: $showingNameInput) {
                TextField("ドキュメント名", text: $newDocumentName)
                Button("キャンセル", role: .cancel) { onResetScanState() }
                Button("保存") { onSaveDocument() }
            } message: {
                Text("ドキュメントの名前を入力してください")
            }
            .alert("ドキュメントを削除", isPresented: $viewModel.showingDeleteDocumentAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) { viewModel.confirmDeleteDocument() }
            } message: {
                Text("このドキュメントを削除してもよろしいですか？この操作は取り消せません。")
            }
            .alert("保存エラー", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .alert("スキャンエラー", isPresented: $showScannerError) {
                Button("OK", role: .cancel) { scannerError = nil }
            } message: {
                Text(scannerError ?? "不明なエラーが発生しました")
            }
            .alert("写真読み込みエラー", isPresented: $showPhotoPickerError) {
                Button("OK", role: .cancel) { photoPickerError = nil }
            } message: {
                Text(photoPickerError ?? "不明なエラーが発生しました")
            }
    }
}


