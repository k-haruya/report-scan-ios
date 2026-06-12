//
//  OCRResultView.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftUI
import SwiftData

struct OCRResultView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let document: ScannedDocument

    @AppStorage("ocrLanguage") private var ocrLanguage: String = "ja-JP"
    @AppStorage("autoSaveOCR") private var autoSaveOCR: Bool = true

    @State private var recognizedText: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var hasPerformedOCR = false
    @State private var showCopiedAlert = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var ocrTask: Task<Void, Never>?

    // 同時実行数の制限
    private static let maxConcurrentOCR = 3

    var body: some View {
        NavigationStack {
            ZStack {
                if isProcessing {
                    processingView
                } else if !hasPerformedOCR {
                    startView
                } else {
                    resultView
                }
            }
            .navigationTitle(AppStrings.OCR.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Actions.close) {
                        dismiss()
                    }
                }

                if hasPerformedOCR && !isProcessing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppStrings.Actions.save) {
                            saveOCRText(manualSave: true)
                        }
                    }
                }
            }
            .alert(AppStrings.OCR.copySuccessTitle, isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(AppStrings.OCR.copySuccessMessage)
            }
            .alert("保存エラー", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .onAppear {
                loadExistingOCRText()
            }
            .onDisappear {
                ocrTask?.cancel()
            }
        }
    }

    // MARK: - Load Existing OCR

    private func loadExistingOCRText() {
        // 既存のOCRテキストがあれば表示
        if let existingText = document.ocrText, !existingText.isEmpty {
            recognizedText = existingText
            hasPerformedOCR = true
        }
    }

    // MARK: - Subviews

    private var startView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text(AppStrings.OCR.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(AppStrings.OCR.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                performOCR()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text(AppStrings.OCR.startButton)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    private var processingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            Text(AppStrings.OCR.processingTitle)
                .font(.headline)

            Text(AppStrings.OCR.processingDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var resultView: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                errorView(message: error)
            } else if recognizedText.isEmpty {
                emptyResultView
            } else {
                textEditorView
                actionButtonsView
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("エラーが発生しました")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                hasPerformedOCR = false
                errorMessage = nil
            } label: {
                Text(AppStrings.OCR.retry)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    private var emptyResultView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(AppStrings.OCR.noTextFoundTitle)
                .font(.headline)

            Text(AppStrings.OCR.noTextFoundMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                hasPerformedOCR = false
            } label: {
                Text(AppStrings.OCR.retry)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    private var textEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppStrings.OCR.recognizedTextTitle)
                    .font(.headline)
                Spacer()
                Text("\(recognizedText.count)文字")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)

            TextEditor(text: $recognizedText)
                .font(.body)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
        }
    }

    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            Button {
                copyToClipboard()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text(AppStrings.OCR.copyToClipboard)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }

            Button {
                performOCR()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("もう一度認識")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Helper Methods

    private func performOCR() {
        // 既に処理中の場合は何もしない（レース条件防止）
        guard !isProcessing else { return }

        // 既存のタスクをキャンセル
        ocrTask?.cancel()

        isProcessing = true
        errorMessage = nil
        recognizedText = ""

        ocrTask = Task {
            do {
                // 設定から言語を取得
                let languages = ocrLanguage.components(separatedBy: ",")
                // 生画像を使用（OCR精度向上のため画像処理パイプラインを通さない）
                let imageDataArray = document.imageData

                // 同時実行数を制限して並列OCR実行
                let results = try await withThrowingTaskGroup(of: (index: Int, text: String).self) { group in
                    var indexedResults: [(index: Int, text: String)] = []
                    var nextIndex = 0

                    // 最初のバッチを追加
                    for i in 0..<min(Self.maxConcurrentOCR, imageDataArray.count) {
                        let imageData = imageDataArray[i]
                        group.addTask {
                            try Task.checkCancellation()
                            guard let image = UIImage(data: imageData) else {
                                return (index: i, text: "")
                            }
                            // 台形補正のみ適用（手動切り抜き済みの場合は矩形が検出されずそのまま返される）
                            let correctedImage = await ImageFilterService.shared.applyPerspectiveCorrectionOnly(to: image) ?? image
                            let text = try await OCRService.shared.recognizeText(from: correctedImage, languages: languages)
                            return (index: i, text: text)
                        }
                        nextIndex = i + 1
                    }

                    // 結果を収集しながら新しいタスクを追加
                    for try await result in group {
                        try Task.checkCancellation()
                        indexedResults.append(result)

                        // まだ処理していない画像があれば追加
                        if nextIndex < imageDataArray.count {
                            let imageData = imageDataArray[nextIndex]
                            let currentIndex = nextIndex
                            group.addTask {
                                try Task.checkCancellation()
                                guard let image = UIImage(data: imageData) else {
                                    return (index: currentIndex, text: "")
                                }
                                // 台形補正のみ適用
                                let correctedImage = await ImageFilterService.shared.applyPerspectiveCorrectionOnly(to: image) ?? image
                                let text = try await OCRService.shared.recognizeText(from: correctedImage, languages: languages)
                                return (index: currentIndex, text: text)
                            }
                            nextIndex += 1
                        }
                    }
                    return indexedResults
                }

                // キャンセルチェック
                try Task.checkCancellation()

                // インデックス順にソートしてテキストを結合
                let sortedTexts = results
                    .sorted { $0.index < $1.index }
                    .map { $0.text }
                    .filter { !$0.isEmpty }

                await MainActor.run {
                    guard !Task.isCancelled else {
                        isProcessing = false
                        return
                    }

                    recognizedText = sortedTexts.joined(separator: "\n\n--- ページ区切り ---\n\n")
                    isProcessing = false
                    hasPerformedOCR = true

                    // 自動保存が有効な場合は自動保存
                    if autoSaveOCR && !recognizedText.isEmpty {
                        saveOCRText(manualSave: false)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    hasPerformedOCR = true
                }
            }
        }
    }

    private func saveOCRText(manualSave: Bool = true) {
        document.ocrText = recognizedText
        document.updatedAt = Date()

        do {
            try modelContext.save()
            // 手動保存の場合のみ閉じる（自動保存時は閉じない）
            if manualSave {
                dismiss()
            }
        } catch {
            saveErrorMessage = "\(AppStrings.OCR.saveFailed): \(error.localizedDescription)"
            showSaveError = true
        }
    }

    private func copyToClipboard() {
        guard !recognizedText.isEmpty else { return }
        UIPasteboard.general.string = recognizedText
        showCopiedAlert = true
    }
}
