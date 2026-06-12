# ReportScan

📄 A document scanner app for iOS, built for students.

![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-blue?logo=swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17.0+-black?logo=apple)
[![App Store](https://img.shields.io/badge/App_Store-Available-0D96F6?logo=appstore&logoColor=white)](https://apps.apple.com/jp/app/id6758909865)

[**📲 Available on the App Store**](https://apps.apple.com/jp/app/id6758909865) — completely free, no ads, no subscriptions.

[日本語のREADMEはこちら](README.md) | Companion parameter-tuning CLI → [report-scan-filter-tuner](https://github.com/k-haruya/report-scan-filter-tuner)

## Screenshots

| | Before | After | OCR | Export |
|---|---|---|---|---|
| <img src="docs/screenshots/01_hero.png" width="160"> | <img src="docs/screenshots/02_before.png" width="160"> | <img src="docs/screenshots/03_after.png" width="160"> | <img src="docs/screenshots/04_ocr.png" width="160"> | <img src="docs/screenshots/05_export.png" width="160"> |

## What it does

ReportScan digitizes paper documents with the camera or photo library, applies automatic enhancement (perspective correction, shadow removal, text sharpening), recognizes text (Japanese + English OCR), and exports to PDF / Word (.docx) / plain text, with folder-based organization. All processing runs on-device — no data ever leaves the phone.

## Technical highlights

- **Custom shadow-removal pipeline** — Division Normalization (background-division) combined with adaptive thresholding, implemented as **Metal CI Kernels** on Core Image. Parameters were tuned systematically with a purpose-built macOS CLI ([report-scan-filter-tuner](https://github.com/k-haruya/report-scan-filter-tuner)) that sweeps the parameter space against sample photos.
- **Memory engineering** — SwiftData `@Attribute(.externalStorage)` for lazy-loading large image blobs, `autoreleasepool` around batch filtering to flatten memory peaks, and `CGImageSourceCreateThumbnailAtIndex` downsampling for lists. Eliminated all OOM crashes observed during development.
- **Responsive UI** — image rotation renders instantly via SwiftUI view state and is committed losslessly at save time through EXIF orientation metadata (0 ms perceived latency). Zoom/pan/scroll gesture conflicts were resolved by embedding a UIKit `UIScrollView` whose `isScrollEnabled` toggles with zoom scale.
- **Swift Concurrency in practice** — deliberate use of MainActor isolation, `Task` vs `Task.detached`, and `nonisolated` static functions for background thumbnail generation.
- **Privacy by design** — Vision-based OCR and all image processing run entirely on-device.

The second half of the [Japanese README](README.md) is a detailed engineering log (~30 numbered entries) documenting problems encountered and how they were solved — coordinate-shift bugs in the Core Image pipeline, deprecated CIKL-to-Metal migration, OCR input-image trade-offs, App Store review and more.

## Tech stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (MVVM) |
| Persistence | SwiftData |
| Scanning | VisionKit (`VNDocumentCameraViewController`) |
| OCR | Vision framework |
| Image processing | Core Image + custom Metal CI Kernels |
| Word export | ZIPFoundation (builds .docx) |

## Project structure

```
ReportScan/
├── Models/          # SwiftData @Model (ScannedDocument, DocumentFolder)
├── Views/           # SwiftUI views (Home / Scan / Edit / Export / Settings)
├── ViewModels/      # MVVM logic
├── Services/        # ImageFilterService, OCRService, PDF/TXT/Word exporters
├── Utilities/       # Constants, strings, color theme
└── Resources/       # Assets, localization
```

## Build

1. Clone the repository
2. Open `ReportScan.xcodeproj` in Xcode 15+
3. Wait for the ZIPFoundation package to resolve
4. Run on a physical device (the camera does not work in the Simulator)

## License

All rights reserved. The source is published for portfolio purposes.
