# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**ReportScan (レポートスキャン)** is an iOS document scanning application targeted at Japanese university students. The app provides document scanning, OCR (Japanese + English), advanced image filtering (shadow removal), and multi-format export (PDF/TXT/Word) with folder organization capabilities.

- **Bundle ID**: com.haruy.reportscan
- **Target**: iOS 17.0+
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData
- **Scan Engine**: VisionKit (`VNDocumentCameraViewController`)
- **OCR Engine**: Vision.framework
- **Image Processing**: Core Image + vImage (Division Normalization Algorithm)
- **Development Environment**: Xcode 15.0+

## Project Status

**Active Development (Beta Phase)**. 
Major features (Scanning, OCR, Image Filtering, File Export, Folder Management) are implemented.
Current focus is on performance optimization, UI/UX refinement, and stability.

## Architecture & Tech Stack

### Tech Stack
- **UI**: SwiftUI with MVVM pattern
- **Persistence**: SwiftData with `@Attribute(.externalStorage)` for large image handling
- **Image Processing**: Custom **Division Normalization** algorithm for shadow removal and text enhancement
- **Concurrency**: Swift Concurrency (`async/await`, `Task`, `Actor`) for background processing
- **Performance**: 
    - `LazyVGrid` and thumbnail downsampling for scroll performance
    - `autoreleasepool` to manage memory spikes during batch processing
    - `loading` states for smooth navigation

### Directory Structure
```
ReportScan/
├── ReportScanApp.swift           # Entry point with SwiftData container
├── Models/
│   ├── ScannedDocument.swift     # @Model: document with external storage images
│   └── DocumentFolder.swift      # @Model: folder container
├── Views/
│   ├── Home/                     # Home screen, FolderListView, DocumentListView
│   ├── Scan/                     # DocumentScannerView, PhotoPickerView
│   ├── Edit/                     # ImageEditorView, FilterPreviewView, OCRResultView
│   ├── Export/                   # ExportView
│   ├── Components/               # Reusable components (LoadingOverlay, etc.)
│   └── Settings/                 # SettingsView
├── ViewModels/
│   └── HomeViewModel.swift       # Central state management
├── Services/
│   ├── ImageFilterService.swift  # Core Image & Division Normalization logic
│   ├── FilterConfig.swift        # Filter parameters (tuned via FilterTuner)
│   ├── OCRService.swift          # Vision.framework OCR
│   ├── PDFExportService.swift    # PDF generation
│   ├── TXTExportService.swift    # Text export
│   └── WordExportService.swift   # .docx generation using ZIPFoundation
├── Utilities/
│   └── Constants.swift, AppStrings.swift, ColorTheme.swift
└── Resources/
    ├── Assets.xcassets           # App Icon and images
    └── Localizable.strings       # Japanese localization
```

## Key Implementation Details

### 1. Image Processing (Division Normalization)
The core feature is the shadow removal algorithm implemented in `ImageFilterService.swift`.
- **Concept**: Estimated background = Image * GaussianBlur. Normalized = Image / Estimated Background.
- **Pipeline**:
    1. **Perspective Correction**: Built-in VisionKit feature.
    2. **Division Normalization**: Removes shadows and uneven lighting.
    3. **Pre/Post Noise Reduction**: Median blur to reduce salt-and-pepper noise.
    4. **Sharpening**: Unsharp mask to enhance edges.
    5. **Adaptive Thresholding**: Converts to high-contrast B&W.
- **Tuning**: Parameters are tuned using the separate `FilterTuner` tool (Mac CLI).

### 2. Data Persistence (Speed & Memory)
- **Lazy Loading**: `ScannedDocument` uses `@Attribute(.externalStorage)` for `imageData` and `processedImageData`. This prevents OOM crashes when listing documents.
- **Persistence Strategy**: Filtered images are saved (`processedImageData`) only when "Save" is pressed in the editor. Viewing uses pre-processed images for zero-latency performance. Original images are always kept for non-destructive editing.

### 3. Navigation UX
- **Manual Navigation**: `DocumentListView` and `FolderListView` use `Button` instead of `NavigationLink` to control transition timing.
- **Loading Overlay**: Navigation triggers a 0.1s delay with a `LoadingOverlay` ("読み込み中...") to prevent UI freezing during view construction. `HomeView` handles the overlay via `ZStack`.

### 4. Memory Optimization
- **Downsampling**: `UIImage.resize` uses `CGImageSourceCreateThumbnailAtIndex` to load images at target size immediately, avoiding full-resolution decode.
- **Alpha Channel**: Images are saved with `.opaque = true` to remove alpha channel, saving 25% memory.

## Development Workflow

### Build & Run
- Open `ReportScan.xcodeproj`
- Select physical device (Camera does not work on Simulator) or Simulator (for UI/Logic testing)
- **Note**: `ZIPFoundation` package should resolve automatically.

### Common Tasks
- **Adding a new filter**: Modify `ImageFilterService.swift` and `FilterConfig.swift`.
- **Changing UI text**: Edit `AppStrings.swift` or `Localizable.strings`.
- **Debugging Filters**: Use the Mac CLI tool (`FilterTuner` folder) to experiment with parameters before applying to iOS app.

## Known Issues / Future Work
- **Scanner in Simulator**: VisionKit camera view is black in Simulator. Use real device.
- **Memory**: Processing 10+ images at once can verify high memory usage. `autoreleasepool` is in place but monitor usage.
