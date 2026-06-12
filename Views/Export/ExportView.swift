//
//  ExportView.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftUI
import SwiftData

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let document: ScannedDocument

    @State private var selectedFormat: ExportFormat = .pdf
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showShareSheet = false
    @State private var fileToShare: URL?
    @State private var exportTask: Task<Void, Never>?
    @State private var showSuccessAlert = false
    @State private var exportedFormatName = ""

    private var hasValidOCRText: Bool {
        guard let ocrText = document.ocrText else { return false }
        return !ocrText.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isExporting {
                    exportingView
                } else if let error = exportError {
                    errorView(message: error)
                } else {
                    formatSelectionView
                }
            }
            .navigationTitle("エクスポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = fileToShare {
                    ShareSheet(items: [url]) { completed in
                        // 共有アクティビティが完了してから一時ファイルを削除
                        if completed {
                            showSuccessAlert = true
                        }
                        cleanupTempFile(url)
                    }
                }
            }
            .alert("エクスポート完了", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("\(exportedFormatName)ファイルを保存しました")
            }
            .onDisappear {
                exportTask?.cancel()
            }
        }
    }

    private func cleanupTempFile(_ url: URL) {
        Task {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                // 一時ファイルの削除失敗はログのみ（致命的ではない）
                print("一時ファイルの削除に失敗: \(error.localizedDescription)")
            }
            await MainActor.run {
                fileToShare = nil
            }
        }
    }

    // MARK: - Subviews

    private var formatSelectionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                formatOptionsSection
                exportButtonSection
            }
            .padding()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text(document.title)
                .font(.title3)
                .fontWeight(.bold)

            Text("\(document.imageData.count)ページ")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var formatOptionsSection: some View {
        VStack(spacing: 16) {
            Text("エクスポート形式を選択")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(ExportFormat.allCases, id: \.self) { format in
                FormatOptionCard(
                    format: format,
                    isSelected: selectedFormat == format,
                    hasOCRText: hasValidOCRText
                ) {
                    selectedFormat = format
                }
            }
        }
    }

    private var exportButtonSection: some View {
        Button {
            performExport()
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("エクスポート")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }

    private var exportingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            Text("エクスポート中...")
                .font(.headline)

            Text("\(selectedFormat.displayName)ファイルを生成しています")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("エクスポートエラー")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                exportError = nil
            } label: {
                Text("戻る")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Helper Methods

    private func performExport() {
        // 既にエクスポート中の場合は何もしない（レース条件防止）
        guard !isExporting else { return }

        exportTask?.cancel()
        isExporting = true
        exportError = nil

        // フォーマットをキャプチャ（処理中の変更を防止）
        let capturedFormat = selectedFormat

        exportTask = Task {
            do {
                try Task.checkCancellation()
                let fileURL = try await exportDocument(format: capturedFormat)

                try Task.checkCancellation()
                await MainActor.run {
                    guard !Task.isCancelled else {
                        isExporting = false
                        return
                    }
                    isExporting = false
                    fileToShare = fileURL
                    exportedFormatName = capturedFormat.displayName
                    showShareSheet = true
                }
            } catch is CancellationError {
                await MainActor.run {
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    /// ファイル名として安全な文字列に変換（パストラバーサル防止）
    private func sanitizeFileName(_ name: String) -> String {
        // 危険な文字とパス区切り文字を除去
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")

        // パストラバーサル攻撃パターン(..)を除去
        while sanitized.contains("..") {
            sanitized = sanitized.replacingOccurrences(of: "..", with: "_")
        }

        // 先頭/末尾の空白とドットを除去
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // 空の場合はデフォルト名を使用
        if sanitized.isEmpty {
            sanitized = "document"
        }

        // 長すぎる場合は切り詰め（拡張子分の余裕を残す）
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }

        return sanitized
    }

    private func exportDocument(format: ExportFormat) async throws -> URL {
        let safeTitle = sanitizeFileName(document.title)
        let uniqueId = UUID().uuidString.prefix(8)
        let fileName = "\(safeTitle)_\(uniqueId).\(format.fileExtension)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let data: Data

        switch format {
        case .pdf:
            // 各ページの表示用画像を取得（処理済みがあれば優先、なければ生データ）
            let images = (0..<document.imageData.count).compactMap { index in
                if let imageData = document.getDisplayImage(at: index) {
                    return UIImage(data: imageData)
                }
                return nil
            }
            guard !images.isEmpty else {
                throw ExportError.noValidImages
            }
            data = PDFExportService.generatePDF(from: images)

        case .txt:
            // OCRテキストがなければ自動実行
            var ocrText = document.ocrText ?? ""
            if ocrText.isEmpty {
                ocrText = try await performAutoOCR()
            }
            guard !ocrText.isEmpty else {
                throw ExportError.noOCRText
            }
            data = try TXTExportService.generateTXT(from: ocrText)

        case .docx:
            // OCRテキストがなければ自動実行
            var ocrText = document.ocrText ?? ""
            if ocrText.isEmpty {
                ocrText = try await performAutoOCR()
            }
            guard !ocrText.isEmpty else {
                throw ExportError.noOCRText
            }
            data = try WordExportService.generateDOCX(text: ocrText)
        }

        try data.write(to: fileURL)
        return fileURL
    }
    
    /// 自動でOCRを実行してテキストを取得
    private func performAutoOCR() async throws -> String {
        // MainActor上でSwiftDataから画像データを取得
        let imagesToOCR = await MainActor.run {
            (0..<document.imageData.count).compactMap { index in
                document.getDisplayImage(at: index)
            }
        }

        guard !imagesToOCR.isEmpty else {
            throw ExportError.noValidImages
        }

        // OCR言語設定を取得
        let ocrLanguageSetting = UserDefaults.standard.string(forKey: "ocrLanguage") ?? "ja-JP"
        var languages = ocrLanguageSetting.components(separatedBy: ",").filter { !$0.isEmpty }
        if languages.isEmpty {
            languages = ["ja-JP"]
        }

        var allText: [String] = []

        for imageData in imagesToOCR {
            guard let image = UIImage(data: imageData) else { continue }
            let text = try await OCRService.shared.recognizeText(from: image, languages: languages)
            if !text.isEmpty {
                allText.append(text)
            }
        }

        let combinedText = allText.joined(separator: "\n\n")

        // OCR結果を保存（SwiftData操作はMainActor上で）
        if !combinedText.isEmpty {
            await MainActor.run {
                document.ocrText = combinedText
                try? modelContext.save()
            }
        }

        return combinedText
    }
}

// MARK: - ExportFormat

enum ExportFormat: String, CaseIterable {
    case pdf = "PDF"
    case txt = "TXT"
    case docx = "DOCX"

    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .txt: return "テキスト"
        case .docx: return "Word文書"
        }
    }

    var fileExtension: String {
        rawValue.lowercased()
    }

    var icon: String {
        switch self {
        case .pdf: return "doc.fill"
        case .txt: return "doc.text"
        case .docx: return "doc.richtext"
        }
    }

    var description: String {
        switch self {
        case .pdf: return "画像をPDFファイルとして保存"
        case .txt: return "OCRテキストをテキストファイルとして保存"
        case .docx: return "OCRテキストをWord文書として保存"
        }
    }

    var requiresOCR: Bool {
        switch self {
        case .pdf: return false
        case .txt, .docx: return true
        }
    }
}

// MARK: - FormatOptionCard

struct FormatOptionCard: View {
    let format: ExportFormat
    let isSelected: Bool
    let hasOCRText: Bool
    let action: () -> Void

    // OCRが必要でまだ実行されていない場合は自動実行される旨を表示
    private var showsAutoOCRInfo: Bool {
        format.requiresOCR && !hasOCRText
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: format.icon)
                    .font(.title)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .frame(width: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(format.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(format.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if showsAutoOCRInfo {
                        Text("※エクスポート時にテキストを自動認識します")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: ((Bool) -> Void)?

    init(items: [Any], onCompletion: ((Bool) -> Void)? = nil) {
        self.items = items
        self.onCompletion = onCompletion
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onCompletion?(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - ExportError

enum ExportError: LocalizedError {
    case noOCRText
    case noValidImages

    var errorDescription: String? {
        switch self {
        case .noOCRText:
            return "テキストが認識されていません。ホーム画面で「テキストを認識」を実行してから再度お試しください。"
        case .noValidImages:
            return "有効な画像が見つかりません。ドキュメントが破損している可能性があります。"
        }
    }
}
