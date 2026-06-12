//
//  ImageEditorView.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftUI
import SwiftData
import ImageIO
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

struct ImageEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let document: ScannedDocument

    @AppStorage("imageQuality") private var imageQuality: Double = 0.8

    @State private var selectedFilterType: FilterType = .auto  // デフォルトを自動補正に
    @State private var currentPageIndex = 0
    @State private var isProcessing = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var showDeleteImageAlert = false

    @State private var showingReorderView = false
    @State private var showingPerspectiveCorrection = false

    // ページごとの回転ステップ数（0=0°, 1=90°CW, 2=180°, 3=270°CW）
    @State private var pageRotations: [Int: Int] = [:]

    // ピンチズーム / ドラッグ用
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var lastDragOffset: CGSize = .zero

    private var currentImage: UIImage? {
        guard currentPageIndex >= 0,
              currentPageIndex < document.imageData.count else { return nil }
        return UIImage(data: document.imageData[currentPageIndex])
    }

    /// 現在のページの回転角度（度数）
    private var currentRotationDegrees: Double {
        Double((pageRotations[currentPageIndex] ?? 0) % 4) * 90.0
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    // 画像プレビュー
                    imagePreviewSection

                    Divider()

                    // フィルター選択
                    filterSelectionSection

                    // ページネーション
                    if document.imageData.count > 1 {
                        pageNavigationSection
                    }
                }
                .navigationTitle("画像を編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveFilteredImages()
                        }
                        .disabled(isProcessing)
                    }
                }
                .adaptiveSheet(isPresented: $showingReorderView) {
                    ReorderImagesView(document: document)
                }
                .adaptiveSheet(isPresented: $showingPerspectiveCorrection) {
                    if let image = currentImage {
                        PerspectiveCorrectionView(image: image) { correctedData in
                            applyPerspectiveCorrection(correctedData)
                        }
                    }
                }
                .alert("保存エラー", isPresented: $showSaveError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(saveErrorMessage)
                }
                .alert("このページを削除", isPresented: $showDeleteImageAlert) {
                    Button("キャンセル", role: .cancel) {}
                    Button("削除", role: .destructive) {
                        deleteCurrentImage()
                    }
                } message: {
                    Text("このページを削除してもよろしいですか？")
                }
                .onDisappear {
                    saveTask?.cancel()
                }
                .onAppear {
                    loadCurrentPageFilter()
                }
                .onChange(of: currentPageIndex) { _, _ in
                    loadCurrentPageFilter()
                    resetZoom()
                }
                .onChange(of: selectedFilterType) { _, newValue in
                    // 現在のページのフィルタータイプを更新
                    document.setFilterType(newValue.rawValue, at: currentPageIndex)
                }
            }
            
            // ローディングオーバーレイ
            if isProcessing {
                LoadingOverlay(message: "画像を保存中...")
            }
        }
    }
    
    /// 現在のページを削除
    private func deleteCurrentImage() {
        guard document.imageData.count > 1,
              currentPageIndex >= 0,
              currentPageIndex < document.imageData.count else { return }
        
        // 画像データを削除
        document.imageData.remove(at: currentPageIndex)
        
        // フィルタータイプも削除
        if currentPageIndex < document.filterTypes.count {
            document.filterTypes.remove(at: currentPageIndex)
        }
        
        // processedImageDataも削除
        if let processed = document.processedImageData,
           currentPageIndex < processed.count {
            document.processedImageData?.remove(at: currentPageIndex)
        }
        
        // ページインデックスを調整
        if currentPageIndex >= document.imageData.count {
            currentPageIndex = document.imageData.count - 1
        }

        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "ページの削除に失敗しました: \(error.localizedDescription)"
            showSaveError = true
        }
    }
    
    /// 現在のページのフィルタータイプを読み込む
    private func loadCurrentPageFilter() {
        let filterTypeString = document.getFilterType(at: currentPageIndex)
        selectedFilterType = FilterType(rawValue: filterTypeString) ?? .auto
    }

    // MARK: - Subviews

    private var imagePreviewSection: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = currentImage {
                    let rotationSteps = pageRotations[currentPageIndex] ?? 0
                    let isOddRotation = rotationSteps % 2 != 0
                    let imageAspect = image.size.width / image.size.height
                    let rotationScale = isOddRotation
                        ? min(1.0, 1.0 / imageAspect)
                        : 1.0
                    let effectiveScale = rotationScale * zoomScale
                    let containerSize = geometry.size

                    FilterPreviewView(
                        image: image,
                        filterType: selectedFilterType,
                        imageDataHash: document.imageData[currentPageIndex].hashValue
                    )
                    .frame(width: containerSize.width)
                    .rotationEffect(.degrees(Double(rotationSteps % 4) * 90.0))
                    .scaleEffect(effectiveScale)
                    .offset(dragOffset)
                    .animation(.easeInOut(duration: 0.2), value: rotationSteps)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoomScale = max(1.0, min(lastZoomScale * value, 5.0))
                            }
                            .onEnded { value in
                                zoomScale = max(1.0, min(lastZoomScale * value, 5.0))
                                lastZoomScale = zoomScale
                                // ズーム変更後にオフセットをバウンド内に収める
                                let newScale = rotationScale * zoomScale
                                let clamped = Self.clampOffset(dragOffset, containerSize: containerSize, effectiveScale: newScale)
                                if clamped != dragOffset {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragOffset = clamped
                                        lastDragOffset = clamped
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard zoomScale > 1.0 else { return }
                                let proposed = CGSize(
                                    width: lastDragOffset.width + value.translation.width,
                                    height: lastDragOffset.height + value.translation.height
                                )
                                dragOffset = Self.clampOffset(proposed, containerSize: containerSize, effectiveScale: effectiveScale)
                            }
                            .onEnded { _ in
                                lastDragOffset = dragOffset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            zoomScale = 1.0
                            lastZoomScale = 1.0
                            dragOffset = .zero
                            lastDragOffset = .zero
                        }
                    }
                } else {
                    Text("画像を読み込めません")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    /// ドラッグオフセットを画像が枠外に出ないよう制限する
    private static func clampOffset(_ offset: CGSize, containerSize: CGSize, effectiveScale: CGFloat) -> CGSize {
        let maxX = max(0, containerSize.width * (effectiveScale - 1) / 2)
        let maxY = max(0, containerSize.height * (effectiveScale - 1) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }

    private var filterSelectionSection: some View {
        VStack(spacing: 12) {
            Text("フィルター")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(FilterType.allCases, id: \.self) { filterType in
                        FilterOptionButton(
                            filterType: filterType,
                            isSelected: selectedFilterType == filterType
                        ) {
                            selectedFilterType = filterType
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            // 回転ボタン
            rotationButtonsSection
        }
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }
    
    private var rotationButtonsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                Button {
                    rotateCurrentImage(clockwise: false)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "rotate.left")
                            .font(.title2)
                        Text("左に回転")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .frame(width: 70, height: 56)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }

                Button {
                    rotateCurrentImage(clockwise: true)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "rotate.right")
                            .font(.title2)
                        Text("右に回転")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .frame(width: 70, height: 56)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }

                Button {
                    showingPerspectiveCorrection = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "crop")
                            .font(.title2)
                        Text("切り抜き")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .frame(width: 70, height: 56)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }

                // 画像削除ボタン（複数ページがある場合のみ表示）
                if document.imageData.count > 1 {
                    Button {
                        showDeleteImageAlert = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.title2)
                            Text("削除")
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                        .frame(width: 70, height: 56)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }
    
    /// 現在の画像を90度回転（Stateのみ変更、即座に反映）
    private func rotateCurrentImage(clockwise: Bool) {
        let current = pageRotations[currentPageIndex] ?? 0
        if clockwise {
            pageRotations[currentPageIndex] = (current + 1) % 4
        } else {
            pageRotations[currentPageIndex] = (current + 3) % 4  // -1 mod 4
        }
        resetZoom()
    }

    /// 台形補正の結果を適用
    private func applyPerspectiveCorrection(_ correctedData: Data) {
        guard currentPageIndex >= 0,
              currentPageIndex < document.imageData.count else { return }

        document.imageData[currentPageIndex] = correctedData

        // processedImageDataをクリア（再フィルター処理が必要）
        if let processed = document.processedImageData,
           currentPageIndex < processed.count {
            document.processedImageData?[currentPageIndex] = Data()
        }

        document.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "台形補正の保存に失敗しました: \(error.localizedDescription)"
            showSaveError = true
        }
    }

    private func resetZoom() {
        zoomScale = 1.0
        lastZoomScale = 1.0
        dragOffset = .zero
        lastDragOffset = .zero
    }

    /// JPEGデータのEXIF Orientationタグのみを変更（画像のデコード/エンコードは一切行わない）
    private static func rotateJPEGByExif(_ data: Data, clockwise: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }

        // 現在のEXIF Orientationを取得（デフォルト: 1 = 通常）
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let currentOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1

        // 現在の向きに対して90度回転した新しいOrientationを計算
        let newOrientation = Self.rotateExifOrientation(currentOrientation, clockwise: clockwise)

        // 新しいJPEGデータを作成（ピクセルデータはそのままコピー、メタデータのみ変更）
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, type, 1, nil) else { return nil }

        let newProperties: [CFString: Any] = [kCGImagePropertyOrientation: newOrientation]
        CGImageDestinationAddImageFromSource(destination, source, 0, newProperties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    /// EXIF Orientation値を90度回転させるテーブル
    private static func rotateExifOrientation(_ current: UInt32, clockwise: Bool) -> UInt32 {
        // EXIF Orientation: 1=Up, 3=Down(180°), 6=Right(90°CW), 8=Left(90°CCW)
        //                   2=UpMirrored, 4=DownMirrored, 5=LeftMirrored, 7=RightMirrored
        if clockwise {
            switch current {
            case 1: return 6  // Up → Right(90°CW)
            case 6: return 3  // Right → Down(180°)
            case 3: return 8  // Down → Left(270°CW)
            case 8: return 1  // Left → Up(0°)
            case 2: return 5
            case 5: return 4
            case 4: return 7
            case 7: return 2
            default: return 6
            }
        } else {
            switch current {
            case 1: return 8  // Up → Left(90°CCW)
            case 8: return 3  // Left → Down(180°)
            case 3: return 6  // Down → Right(270°CCW)
            case 6: return 1  // Right → Up(0°)
            case 2: return 7
            case 7: return 4
            case 4: return 5
            case 5: return 2
            default: return 8
            }
        }
    }

    private var pageNavigationSection: some View {
        VStack(spacing: 8) {
            Text("\(currentPageIndex + 1) / \(document.imageData.count)")
                .font(.headline)

            HStack {
                Button {
                    if currentPageIndex > 0 {
                        currentPageIndex -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(currentPageIndex == 0)

                Spacer()

                // 並び替えボタン
                Button {
                    showingReorderView = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down.square")
                        Text("並び替え")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer()

                Button {
                    if currentPageIndex < document.imageData.count - 1 {
                        currentPageIndex += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(document.imageData.isEmpty || currentPageIndex >= document.imageData.count - 1)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Helper Methods

    private func saveFilteredImages() {
        // 既に処理中の場合は何もしない
        guard !isProcessing else { return }

        isProcessing = true

        // 処理開始時に値をキャプチャ（MainActor上でSwiftDataモデルにアクセス）
        let capturedQuality = imageQuality
        let capturedFilterTypes = document.filterTypes
        let capturedRotations = pageRotations
        let capturedImageData = document.imageData

        saveTask = Task {
            // Step 1: 回転があるページはEXIF回転を適用
            var rotatedImageDataArray = capturedImageData
            for (index, data) in rotatedImageDataArray.enumerated() {
                let steps = capturedRotations[index] ?? 0
                guard steps % 4 != 0 else { continue }
                var current = data
                for _ in 0..<(steps % 4) {
                    if let rotated = Self.rotateJPEGByExif(current, clockwise: true) {
                        current = rotated
                    }
                }
                rotatedImageDataArray[index] = current
            }

            // Step 2: フィルター処理（autoreleasepoolでメモリピーク軽減）
            var processedImages: [Data] = []

            for (index, imageData) in rotatedImageDataArray.enumerated() {
                if Task.isCancelled { return }

                let resultData: Data? = autoreleasepool {
                    guard let image = UIImage(data: imageData) else { return nil }

                    let filterTypeString = index < capturedFilterTypes.count ? capturedFilterTypes[index] : "auto"
                    let filterType = FilterType(rawValue: filterTypeString) ?? .auto

                    let filteredImage: UIImage
                    if filterType == .original {
                        filteredImage = image
                    } else {
                        filteredImage = ImageFilterService.shared.applyFilter(filterType, to: image) ?? image
                    }

                    return filteredImage.jpegData(compressionQuality: capturedQuality)
                }

                // インデックス整合性維持: 失敗時は元データをフォールバック
                processedImages.append(resultData ?? imageData)
            }

            if Task.isCancelled { return }

            // Step 3: 保存（SwiftData操作は必ずMainActor上で実行）
            await MainActor.run {
                document.imageData = rotatedImageDataArray
                document.processedImageData = processedImages
                document.updatedAt = Date()

                do {
                    try modelContext.save()
                    isProcessing = false
                    dismiss()
                } catch {
                    isProcessing = false
                    saveErrorMessage = "フィルターの保存に失敗しました: \(error.localizedDescription)"
                    showSaveError = true
                }
            }
        }
    }
}

// MARK: - FilterOptionButton

struct FilterOptionButton: View {
    let filterType: FilterType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: iconName)
                            .font(.title2)
                            .foregroundColor(isSelected ? .white : .gray)
                    )

                Text(filterType.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
    }

    private var iconName: String {
        switch filterType {
        case .original:
            return "photo"
        case .magic:
            return "wand.and.stars"
        case .grayscale:
            return "circle.lefthalf.filled"
        case .auto:
            return "wand.and.rays"
        }
    }
}

// MARK: - Reorder View

struct ReorderImagesView: View {
    let document: ScannedDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var items: [ReorderItem] = []
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
    struct ReorderItem: Identifiable, Equatable {
        let id: UUID = UUID()
        let originalIndex: Int
        let image: UIImage
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    HStack {
                        Image(uiImage: item.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 110)
                            .cornerRadius(8)
                            .clipped()
                        
                        Text("ページ \(item.originalIndex + 1)")
                            .font(.title3)
                        
                        Spacer()
                        
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.gray)
                    }
                }
                .onMove(perform: moveItem)
            }
            .navigationTitle("ページの並び替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { saveOrder() }
                }
            }
            .onAppear {
                loadItems()
            }
            .alert("保存エラー", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    private func loadItems() {
        // サムネイルサイズでデコード（メモリ節約）
        items = (0..<document.imageData.count).compactMap { index in
            if let data = document.getDisplayImage(at: index),
               let image = Self.createThumbnail(from: data, maxSize: 200) {
                return ReorderItem(originalIndex: index, image: image)
            }
            return nil
        }
    }

    /// フル解像度をデコードせず、サムネイルサイズでデコード（省メモリ）
    private static func createThumbnail(from data: Data, maxSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    private func moveItem(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }
    
    private func saveOrder() {
        // 新しい順序に基づいてデータを再構築
        var newImageData: [Data] = []
        var newFilterTypes: [String] = []
        var newProcessedData: [Data] = []
        let hasProcessed = document.processedImageData != nil

        for item in items {
            let index = item.originalIndex

            // imageData
            if index < document.imageData.count {
                newImageData.append(document.imageData[index])
            }

            // filterTypes
            if index < document.filterTypes.count {
                newFilterTypes.append(document.filterTypes[index])
            } else {
                newFilterTypes.append("auto")
            }

            // processedImageData
            if hasProcessed {
                if let processed = document.processedImageData,
                   index < processed.count {
                    newProcessedData.append(processed[index])
                } else {
                    newProcessedData.append(Data())
                }
            }
        }

        // 更新
        document.imageData = newImageData
        document.filterTypes = newFilterTypes
        if hasProcessed {
            document.processedImageData = newProcessedData
        }
        document.updatedAt = Date()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = "並び替えの保存に失敗しました: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}

// MARK: - UIImage.Orientation → CGImagePropertyOrientation 変換

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

// MARK: - Perspective Correction View (切り抜き)

struct PerspectiveCorrectionView: View {
    let image: UIImage
    let onApply: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var topLeft: CGPoint = .zero
    @State private var topRight: CGPoint = .zero
    @State private var bottomLeft: CGPoint = .zero
    @State private var bottomRight: CGPoint = .zero
    @State private var isInitialized = false
    @State private var isProcessing = false
    @State private var currentImageRect: CGRect = .zero

    // ピンチズーム + パン用
    @State private var viewZoom: CGFloat = 1.0
    @State private var lastViewZoom: CGFloat = 1.0
    @State private var viewOffset: CGSize = .zero
    @State private var lastViewOffset: CGSize = .zero

    @AppStorage("imageQuality") private var imageQuality: Double = 0.8

    /// CIImage用の向き（遅延変換、メモリ追加なし）
    private var cgOrientation: CGImagePropertyOrientation {
        CGImagePropertyOrientation(image.imageOrientation)
    }

    /// 共有CIContext（Metal GPU、毎回生成しない）
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let imageRect = aspectFitRect(for: image.size, in: geometry.size)

                ZStack {
                    Color.black.ignoresSafeArea()

                    // 画像 + 選択領域 + ハンドル を一括で拡縮
                    ZStack {
                        // 画像
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)

                        // 選択領域の線
                        PerspectiveSelectionShape(
                            topLeft: topLeft,
                            topRight: topRight,
                            bottomLeft: bottomLeft,
                            bottomRight: bottomRight
                        )
                        .stroke(Color.blue, lineWidth: 2 / viewZoom)

                        // 選択領域の塗りつぶし
                        PerspectiveSelectionShape(
                            topLeft: topLeft,
                            topRight: topRight,
                            bottomLeft: bottomLeft,
                            bottomRight: bottomRight
                        )
                        .fill(Color.blue.opacity(0.1))

                        // 四隅のハンドル
                        cornerHandle(position: $topLeft, imageRect: imageRect)
                        cornerHandle(position: $topRight, imageRect: imageRect)
                        cornerHandle(position: $bottomLeft, imageRect: imageRect)
                        cornerHandle(position: $bottomRight, imageRect: imageRect)
                    }
                    .scaleEffect(viewZoom)
                    .offset(viewOffset)
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            viewZoom = max(0.4, min(lastViewZoom * value, 3.0))
                        }
                        .onEnded { value in
                            viewZoom = max(0.4, min(lastViewZoom * value, 3.0))
                            lastViewZoom = viewZoom
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            viewOffset = CGSize(
                                width: lastViewOffset.width + value.translation.width,
                                height: lastViewOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastViewOffset = viewOffset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewZoom = 1.0
                        lastViewZoom = 1.0
                        viewOffset = .zero
                        lastViewOffset = .zero
                    }
                }
                .onAppear {
                    if !isInitialized, imageRect.width > 0, imageRect.height > 0 {
                        currentImageRect = imageRect
                        initializeCorners(imageRect: imageRect)
                        isInitialized = true
                    }
                }
                .onChange(of: geometry.size) { _, newSize in
                    let newRect = aspectFitRect(for: image.size, in: newSize)
                    if !isInitialized, newRect.width > 0, newRect.height > 0 {
                        currentImageRect = newRect
                        initializeCorners(imageRect: newRect)
                        isInitialized = true
                    } else {
                        currentImageRect = newRect
                    }
                }
            }
            .navigationTitle("切り抜き範囲を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        applyCorrection()
                    }
                    .disabled(isProcessing)
                    .foregroundColor(.white)
                }
            }
            .overlay {
                if isProcessing {
                    LoadingOverlay(message: "切り抜き中...")
                }
            }
        }
    }

    // MARK: - Corner Handle

    private func cornerHandle(position: Binding<CGPoint>, imageRect: CGRect) -> some View {
        // ハンドルサイズをズームに合わせてスケール補正（常に同じ見た目サイズ）
        let handleSize: CGFloat = 28 / viewZoom
        let hitSize: CGFloat = 56 / viewZoom
        let strokeWidth: CGFloat = 3 / viewZoom

        return ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: hitSize, height: hitSize)

            Circle()
                .fill(Color.blue)
                .frame(width: handleSize, height: handleSize)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: strokeWidth)
                )
                .shadow(color: .black.opacity(0.5), radius: 3 / viewZoom)
        }
        .contentShape(Circle().scale(2))
        .position(position.wrappedValue)
        .highPriorityGesture(
            DragGesture()
                .onChanged { value in
                    let x = min(max(value.location.x, imageRect.minX), imageRect.maxX)
                    let y = min(max(value.location.y, imageRect.minY), imageRect.maxY)
                    position.wrappedValue = CGPoint(x: x, y: y)
                }
        )
    }

    // MARK: - Initialize Corners

    private func initializeCorners(imageRect: CGRect) {
        // Visionで矩形検出を試みる（向き情報を渡して正しい座標を取得）
        if let detected = detectRectangle(imageRect: imageRect) {
            topLeft = detected.topLeft
            topRight = detected.topRight
            bottomLeft = detected.bottomLeft
            bottomRight = detected.bottomRight
        } else {
            // 検出失敗時は画像の端から少し内側に初期配置
            let inset: CGFloat = 20
            topLeft = CGPoint(x: imageRect.minX + inset, y: imageRect.minY + inset)
            topRight = CGPoint(x: imageRect.maxX - inset, y: imageRect.minY + inset)
            bottomLeft = CGPoint(x: imageRect.minX + inset, y: imageRect.maxY - inset)
            bottomRight = CGPoint(x: imageRect.maxX - inset, y: imageRect.maxY - inset)
        }
    }

    /// Visionフレームワークで矩形を検出し、ビュー座標に変換
    /// orientation パラメータで EXIF 向きを伝えるため、画像コピーは不要
    private func detectRectangle(imageRect: CGRect) -> (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint)? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.1
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.1
        request.maximumObservations = 1
        request.minimumConfidence = 0.5

        // orientation を渡すことで、cgImage の生ピクセルでなく
        // 表示向きに合った座標が返る
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgOrientation,
            options: [:]
        )
        try? handler.perform([request])

        guard let result = request.results?.first else { return nil }

        // Vision座標(正規化、左下原点) → ビュー座標(左上原点)
        func toViewPoint(_ visionPoint: CGPoint) -> CGPoint {
            CGPoint(
                x: imageRect.minX + visionPoint.x * imageRect.width,
                y: imageRect.minY + (1.0 - visionPoint.y) * imageRect.height
            )
        }

        return (
            topLeft: toViewPoint(result.topLeft),
            topRight: toViewPoint(result.topRight),
            bottomLeft: toViewPoint(result.bottomLeft),
            bottomRight: toViewPoint(result.bottomRight)
        )
    }

    // MARK: - Apply Correction

    private func applyCorrection() {
        isProcessing = true

        Task {
            guard let correctedData = await performPerspectiveCorrection() else {
                isProcessing = false
                return
            }

            onApply(correctedData)
            isProcessing = false
            dismiss()
        }
    }

    private func performPerspectiveCorrection() async -> Data? {
        let imageRect = currentImageRect
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        let capturedQuality = imageQuality

        // 全処理を autoreleasepool で囲み、中間オブジェクトを即座に解放
        return autoreleasepool {
            guard let cgImage = image.cgImage else { return nil }

            // CIImage.oriented() は遅延変換 — 画像コピーを作らずメモリゼロ
            let ciImage = CIImage(cgImage: cgImage).oriented(cgOrientation)
            let imageSize = ciImage.extent.size

            // ビュー座標 → 画像ピクセル座標（CIImageは左下原点）
            func toImagePoint(_ viewPoint: CGPoint) -> CGPoint {
                let nx = (viewPoint.x - imageRect.minX) / imageRect.width
                let ny = (viewPoint.y - imageRect.minY) / imageRect.height
                return CGPoint(
                    x: nx * imageSize.width,
                    y: (1.0 - ny) * imageSize.height
                )
            }

            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = ciImage
            filter.topLeft = toImagePoint(topLeft)
            filter.topRight = toImagePoint(topRight)
            filter.bottomLeft = toImagePoint(bottomLeft)
            filter.bottomRight = toImagePoint(bottomRight)

            guard let outputImage = filter.outputImage else { return nil }

            // 共有CIContextを使用（毎回Metalコンテキスト生成を回避）
            guard let outputCGImage = Self.ciContext.createCGImage(
                outputImage, from: outputImage.extent
            ) else { return nil }

            let resultImage = UIImage(cgImage: outputCGImage)
            return resultImage.jpegData(compressionQuality: capturedQuality)
        }
    }

    // MARK: - Helpers

    private func aspectFitRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        let fitSize: CGSize
        if imageAspect > containerAspect {
            fitSize = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            fitSize = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }

        let x = (containerSize.width - fitSize.width) / 2
        let y = (containerSize.height - fitSize.height) / 2
        return CGRect(x: x, y: y, width: fitSize.width, height: fitSize.height)
    }
}

// MARK: - Perspective Selection Shape

struct PerspectiveSelectionShape: Shape {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.closeSubpath()
        return path
    }
}
