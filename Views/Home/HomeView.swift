import SwiftUI
import SwiftData
import ImageIO

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var navigationPath = NavigationPath()

    @Query private var allFolders: [DocumentFolder]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            FolderListView(viewModel: viewModel, navigationPath: $navigationPath)
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .folder(let folderId):
                        if let folder = allFolders.first(where: { $0.id == folderId }) {
                            DocumentListView(viewModel: viewModel, folder: folder, navigationPath: $navigationPath)
                        } else {
                            Text("フォルダが見つかりません")
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { documentId in
                    DocumentDetailView(documentId: documentId)
                }
        }
        .onAppear {
            viewModel.modelContext = modelContext
        }
    }
}

// ドキュメント詳細画面
struct DocumentDetailView: View {
    let documentId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var documents: [ScannedDocument]
    @State private var showingImageEditor = false
    @State private var showingOCRResult = false
    @State private var showingExport = false
    @State private var currentPageIndex = 0

    // 画像追加用の状態
    @State private var showingAddCamera = false
    @State private var showingAddPhotoPicker = false
    @State private var newCameraImages: [UIImage] = []
    @State private var newPickerImages: [UIImage] = []
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    @AppStorage("imageQuality") private var imageQuality: Double = 0.8

    init(documentId: UUID) {
        self.documentId = documentId
        let id = documentId
        _documents = Query(filter: #Predicate<ScannedDocument> { doc in
            doc.id == id
        })
    }

    var document: ScannedDocument? {
        documents.first
    }

    private var displayImageData: Data? {
        guard let document = document else { return nil }
        return document.getDisplayImage(at: currentPageIndex)
    }

    /// 次のページに移動可能かどうか
    private var canGoToNextPage: Bool {
        guard let count = document?.imageData.count, count > 0 else { return false }
        return currentPageIndex < count - 1
    }

    /// 前のページに移動可能かどうか
    private var canGoToPreviousPage: Bool {
        return currentPageIndex > 0
    }

    var body: some View {
        if let document = document {
            ScrollView {
                VStack(spacing: 12) {
                    // 画像表示エリア（固定高さ、ピンチズーム+パン対応）
                    ZStack {
                        Color(.systemGroupedBackground)
                            .cornerRadius(12)

                        if let imageData = displayImageData,
                           let uiImage = Self.downsampledImage(from: imageData) {
                            ZoomableImageView(
                                image: uiImage,
                                resetKey: "\(documentId)-\(currentPageIndex)"
                            )
                            .cornerRadius(12)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .overlay(
                                    Text("画像を読み込めません")
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    .frame(height: UIScreen.main.bounds.height * 0.45)
                    .clipped()

                    // ページネーション
                    if document.imageData.count > 1 {
                        pageNavigationView
                    }

                    // 情報セクション
                    infoSection

                    // アクションボタン
                    actionButtons(document: document)
                }
                .padding()
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .adaptiveSheet(isPresented: $showingImageEditor) {
                ImageEditorView(document: document)
            }
            .adaptiveSheet(isPresented: $showingOCRResult) {
                OCRResultView(document: document)
            }
            .adaptiveSheet(isPresented: $showingExport) {
                ExportView(document: document)
            }
            .adaptiveSheet(isPresented: $showingAddCamera) {
                DocumentScannerView(scannedImages: $newCameraImages, scannerError: .constant(nil))
            }
            .adaptiveSheet(isPresented: $showingAddPhotoPicker) {
                PhotoPickerView(selectedImages: $newPickerImages, loadError: .constant(nil))
            }
            .onChange(of: documentId) { _, _ in
                // 別のドキュメントに遷移した場合、ページインデックスをリセット
                currentPageIndex = 0
            }
            .onChange(of: document.imageData.count) { oldCount, newCount in
                // 画像数が変わった場合、インデックスが範囲外にならないよう調整
                guard oldCount != newCount else { return }
                let maxIndex = max(0, newCount - 1)
                if currentPageIndex > maxIndex {
                    currentPageIndex = maxIndex
                }
            }
            .onChange(of: newCameraImages) { _, images in
                if !images.isEmpty {
                    addImagesToDocument(images, document: document)
                    newCameraImages = []
                }
            }
            .onChange(of: newPickerImages) { _, images in
                if !images.isEmpty {
                    addImagesToDocument(images, document: document)
                    newPickerImages = []
                }
            }
            .alert("保存エラー", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        } else {
            Text("ドキュメントが見つかりません")
        }
    }
    
    // MARK: - Add Images Helper
    
    private func addImagesToDocument(_ images: [UIImage], document: ScannedDocument) {
        let capturedQuality = imageQuality

        for image in images {
            guard let data = image.jpegData(compressionQuality: capturedQuality) else { continue }
            document.addImage(data, filterType: "auto")
        }

        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "画像の追加に失敗しました: \(error.localizedDescription)"
            showSaveError = true
        }
    }

    // MARK: - Subviews

    private var pageNavigationView: some View {
        HStack {
            Button {
                if canGoToPreviousPage {
                    currentPageIndex -= 1
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)
            }
            .disabled(!canGoToPreviousPage)

            Spacer()

            Text("\(currentPageIndex + 1) / \(document?.imageData.count ?? 0)")
                .font(.headline)

            Spacer()

            Button {
                if canGoToNextPage {
                    currentPageIndex += 1
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)
            }
            .disabled(!canGoToNextPage)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                Text("\(document?.imageData.count ?? 0)ページ")
            }

            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                Text(formatDate(document?.updatedAt ?? Date()))
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func actionButtons(document: ScannedDocument) -> some View {
        VStack(spacing: 12) {
            // 1. 画像を編集
            Button {
                showingImageEditor = true
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text(AppStrings.Actions.editImage)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            // 2. 画像を追加ボタン（メニュー付き）
            Menu {
                Button {
                    showingAddCamera = true
                } label: {
                    Label(AppStrings.Scanner.cameraLabel, systemImage: "camera")
                }
                
                Button {
                    showingAddPhotoPicker = true
                } label: {
                    Label(AppStrings.Scanner.photoLabel, systemImage: "photo.on.rectangle")
                }
            } label: {
                HStack {
                    Image(systemName: "plus.rectangle.on.rectangle")
                    Text(AppStrings.Actions.addImage)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // 3. テキストを認識
            Button {
                showingOCRResult = true
            } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(AppStrings.Actions.recognizeText)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // 4. エクスポート
            Button {
                showingExport = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text(AppStrings.Actions.export)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Helper Methods

    /// 画面幅にダウンサンプリング（フル解像度デコードを回避し高速化）
    private static func downsampledImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let maxPixelSize = UIScreen.main.bounds.width * UIScreen.main.scale
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func formatDate(_ date: Date) -> String {
        Constants.DateFormatters.mediumDateTime.string(from: date)
    }
}

// MARK: - Zoomable Image View (UIScrollView ベース)

/// UIScrollViewを使ったピンチズーム+パン対応の画像ビュー。
/// 外側のSwiftUI ScrollViewと共存可能（ズーム時のみパンを消費、等倍時はスクロールをパススルー）。
class ZoomableScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        delegate = self
        minimumZoomScale = 1.0
        maximumZoomScale = 5.0
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        isScrollEnabled = false  // 等倍時は親ScrollViewにジェスチャーを譲る

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale <= 1.0 {
            imageView.frame = bounds
        }
        centerImage()
    }

    private func centerImage() {
        let offsetX = max((bounds.width - contentSize.width) / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        imageView.center = CGPoint(
            x: contentSize.width / 2 + offsetX,
            y: contentSize.height / 2 + offsetY
        )
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // 拡大中のみスクロール（パン）を有効にし、等倍では親に譲る
        isScrollEnabled = zoomScale > 1.01
        centerImage()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1.0, animated: true)
        } else {
            // タップ位置を中心に3倍ズーム
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let resetKey: String  // ページ切り替え時にズームをリセットするキー

    func makeUIView(context: Context) -> ZoomableScrollView {
        let view = ZoomableScrollView()
        view.imageView.image = image
        context.coordinator.currentKey = resetKey
        return view
    }

    func updateUIView(_ scrollView: ZoomableScrollView, context: Context) {
        // resetKeyが変わった場合（ページ切り替え等）にズームリセット
        if context.coordinator.currentKey != resetKey {
            context.coordinator.currentKey = resetKey
            scrollView.zoomScale = 1.0
            scrollView.isScrollEnabled = false
            scrollView.imageView.image = image
            scrollView.setNeedsLayout()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var currentKey: String = ""
    }
}

// MARK: - Loading Overlay Component

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.75))
            )
            .shadow(radius: 10)
        }
    }
}

// MARK: - Adaptive Sheet Modifier (iPad: fullScreenCover / iPhone: sheet)

struct AdaptiveSheetModifier<SheetContent: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var isPresented: Bool
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content.fullScreenCover(isPresented: $isPresented) {
                sheetContent()
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                sheetContent()
            }
        }
    }
}

extension View {
    func adaptiveSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(AdaptiveSheetModifier(isPresented: isPresented, sheetContent: content))
    }
}

