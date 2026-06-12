//
//  ImageFilterService.swift
//  ReportScan
//
//  Division Normalization + Adaptive Thresholding + Color Preservation 対応版
//  メモリ最適化版: CIContext再利用 + 中間レンダリング
//

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum FilterType: String, CaseIterable {
    case auto = "auto"
    case original = "original"
    case magic = "magic"
    case grayscale = "grayscale"

    var displayName: String {
        switch self {
        case .auto: return "自動補正"
        case .original: return "オリジナル"
        case .magic: return "くっきり"
        case .grayscale: return "白黒"
        }
    }
}

class ImageFilterService {
    static let shared = ImageFilterService()

    // ========== メモリ最適化: CIContextをシングルトン化 ==========
    private let ciContext: CIContext = {
        // Metal GPU優先、なければCPU
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    // ========== 最適化されたパラメーター (2026-02-08 採用) ==========
    private struct OptimalParams {
        // Division Normalization
        static let backgroundBlurRadius: Float = 30.0
        // Adaptive Thresholding
        static let blurRadius: Float = 25.0
        static let thresholdOffset: Float = 0.30
        static let thresholdStrength: Float = 0.95
        static let darkFloor: Float = 0.80
        // ノイズ除去
        static let preMedianIteration: Int = 0
        static let postMedianIteration: Int = 1
        // シャープネス
        static let sharpness: Float = 0.5
        // 色味復元
        static let colorSaturationThreshold: Float = 0.25
        static let colorPreservation: Float = 1.0
        static let colorBoost: Float = 6.0
        // 最終コントラスト
        static let finalContrast: Float = 2.0
    }

    // ========== Metal CI カーネル ==========

    // ========== Metal CI カーネル（スレッドセーフな即時初期化） ==========

    private let metalLibData: Data?
    private let adaptiveThresholdKernel: CIColorKernel?
    private let divisionNormalizationKernel: CIColorKernel?
    private let colorPreservationKernel: CIColorKernel?

    private init() {
        // Metal ライブラリデータ読み込み
        let libData: Data?
        if let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
           let data = try? Data(contentsOf: url) {
            libData = data
        } else {
            libData = nil
            assertionFailure("Metal library (default.metallib) not found in bundle")
        }
        self.metalLibData = libData

        // カーネル初期化（即時実行でスレッド安全性を保証）
        if let data = libData {
            self.adaptiveThresholdKernel = try? CIColorKernel(functionName: "adaptiveThreshold", fromMetalLibraryData: data)
            self.divisionNormalizationKernel = try? CIColorKernel(functionName: "divisionNormalize", fromMetalLibraryData: data)
            self.colorPreservationKernel = try? CIColorKernel(functionName: "colorPreserve", fromMetalLibraryData: data)
        } else {
            self.adaptiveThresholdKernel = nil
            self.divisionNormalizationKernel = nil
            self.colorPreservationKernel = nil
        }
    }

    func applyFilter(_ type: FilterType, to image: UIImage) -> UIImage? {
        guard type != .original else { return image }

        // フル解像度で処理（リサイズなし）
        guard let ciImage = CIImage(image: image) else { return nil }

        let filteredImage: CIImage?

        switch type {
        case .original:
            return image

        case .auto:
            filteredImage = applyDocumentScanFilter(to: ciImage)

        case .magic:
            let corrected = applyPerspectiveCorrection(to: ciImage) ?? ciImage

            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = corrected
            colorControls.contrast = 1.3
            colorControls.brightness = 0.05

            guard let contrastOutput = colorControls.outputImage else { return nil }

            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = contrastOutput
            sharpen.sharpness = 0.5

            filteredImage = sharpen.outputImage

        case .grayscale:
            let corrected = applyPerspectiveCorrection(to: ciImage) ?? ciImage

            let mono = CIFilter.photoEffectMono()
            mono.inputImage = corrected
            filteredImage = mono.outputImage
        }

        guard let output = filteredImage,
              let cgImage = ciContext.createCGImage(output, from: output.extent) else {
            return nil
        }

        // メモリ最適化: アルファチャンネルを除去して不透明画像として返す
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: image.imageOrientation)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = image.scale

        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
    }

    /// OCR用: 台形補正のみを適用（他のフィルター処理なし）
    func applyPerspectiveCorrectionOnly(to image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard let corrected = applyPerspectiveCorrection(to: ciImage) else { return nil }
        guard let cgImage = ciContext.createCGImage(corrected, from: corrected.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: image.imageOrientation)
    }

    // MARK: - Document Scan Filter (8-Step Pipeline)

    private func applyDocumentScanFilter(to ciImage: CIImage) -> CIImage? {
        var processedImage = ciImage

        // Step 1: 台形補正
        processedImage = applyPerspectiveCorrection(to: processedImage) ?? processedImage

        // ★ 色味復元用: 元画像を保存（鮮やかな色情報の抽出元）
        let colorReference = renderIntermediate(processedImage)

        // Step 2: Division Normalization (背景除算)
        // ★ 中間レンダリングでメモリ解放
        if let normalized = applyDivisionNormalization(to: processedImage) {
            processedImage = renderIntermediate(normalized)
        }

        // ★ 基準Extent保存: renderIntermediate後のサイズ (0, 0, W, H)
        // 以降のフィルター（Sharpen等）がextentを拡張するため、
        // renderIntermediate前にこのサイズにcropして座標ズレを防止
        let baseExtent = processedImage.extent

        // ★ 色味復元用: DivisionNorm後を保存（彩度判定 + darkFloor判定用）
        let divNormReference = processedImage

        // Step 3: 事前ノイズ除去 → OFF (preMedian=0)

        // Step 4: シャープネス
        processedImage = applySharpening(to: processedImage) ?? processedImage

        // Step 5: Adaptive Thresholding（darkFloor + 彩度チェック付き）
        // ★ baseExtentにcropしてからrenderIntermediateで座標を揃える
        if let thresholded = applyAdaptiveThreshold(to: processedImage, divNormRef: divNormReference) {
            processedImage = renderIntermediate(thresholded.cropped(to: baseExtent))
        }

        // Step 6: 事後ノイズ除去 (Median Filter × 1)
        processedImage = applyPostNoiseReduction(to: processedImage) ?? processedImage

        // Step 7: 色味復元（ハイブリッド方式）
        processedImage = applyColorPreservation(to: processedImage, colorReference: colorReference, divNormReference: divNormReference) ?? processedImage

        // Step 8: 最終コントラスト強調
        processedImage = applyFinalContrast(to: processedImage) ?? processedImage

        return processedImage
    }

    /// 中間レンダリング: CIImageチェーンを確定してメモリを解放
    private func renderIntermediate(_ ciImage: CIImage) -> CIImage {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return ciImage
        }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Processing Steps

    private func applyPerspectiveCorrection(to ciImage: CIImage) -> CIImage? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.3
        request.maximumObservations = 1

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let results = request.results,
              let rectangle = results.first else {
            return ciImage
        }

        let imageSize = ciImage.extent
        let topLeft = CGPoint(
            x: rectangle.topLeft.x * imageSize.width,
            y: rectangle.topLeft.y * imageSize.height
        )
        let topRight = CGPoint(
            x: rectangle.topRight.x * imageSize.width,
            y: rectangle.topRight.y * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: rectangle.bottomLeft.x * imageSize.width,
            y: rectangle.bottomLeft.y * imageSize.height
        )
        let bottomRight = CGPoint(
            x: rectangle.bottomRight.x * imageSize.width,
            y: rectangle.bottomRight.y * imageSize.height
        )

        let perspectiveCorrection = CIFilter.perspectiveCorrection()
        perspectiveCorrection.inputImage = ciImage
        perspectiveCorrection.topLeft = topLeft
        perspectiveCorrection.topRight = topRight
        perspectiveCorrection.bottomLeft = bottomLeft
        perspectiveCorrection.bottomRight = bottomRight

        return perspectiveCorrection.outputImage
    }

    private func applyDivisionNormalization(to ciImage: CIImage) -> CIImage? {
        guard let kernel = divisionNormalizationKernel else { return ciImage }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = ciImage
        blur.radius = OptimalParams.backgroundBlurRadius
        guard let background = blur.outputImage else { return ciImage }

        let extent = ciImage.extent
        guard let normalized = kernel.apply(
            extent: extent,
            arguments: [ciImage, background]
        ) else { return ciImage }

        return normalized.cropped(to: extent)
    }

    private func applySharpening(to ciImage: CIImage) -> CIImage? {
        let unsharpMask = CIFilter.unsharpMask()
        unsharpMask.inputImage = ciImage
        unsharpMask.radius = 2.5
        unsharpMask.intensity = OptimalParams.sharpness
        return unsharpMask.outputImage
    }

    private func applyAdaptiveThreshold(to ciImage: CIImage, divNormRef: CIImage) -> CIImage? {
        guard let kernel = adaptiveThresholdKernel else { return ciImage }

        let originalExtent = ciImage.extent

        let boxBlur = CIFilter.boxBlur()
        boxBlur.inputImage = ciImage
        boxBlur.radius = OptimalParams.blurRadius
        guard let blurred = boxBlur.outputImage else { return ciImage }

        guard let thresholded = kernel.apply(
            extent: originalExtent,
            arguments: [
                ciImage,
                blurred,
                divNormRef,
                OptimalParams.thresholdOffset,
                OptimalParams.thresholdStrength,
                OptimalParams.darkFloor
            ]
        ) else { return ciImage }

        return thresholded.cropped(to: originalExtent.integral)
    }

    private func applyPostNoiseReduction(to ciImage: CIImage) -> CIImage? {
        var processed = ciImage

        if OptimalParams.postMedianIteration > 0 {
            let median = CIFilter.median()
            for _ in 0..<OptimalParams.postMedianIteration {
                median.inputImage = processed
                processed = median.outputImage ?? processed
            }
        }

        return processed
    }

    private func applyColorPreservation(to ciImage: CIImage, colorReference: CIImage, divNormReference: CIImage) -> CIImage? {
        guard let kernel = colorPreservationKernel else { return ciImage }

        let extent = ciImage.extent
        guard let result = kernel.apply(
            extent: extent,
            arguments: [
                ciImage,
                colorReference,
                divNormReference,
                OptimalParams.colorSaturationThreshold,
                OptimalParams.colorPreservation,
                OptimalParams.colorBoost
            ]
        ) else { return ciImage }

        return result.cropped(to: extent)
    }

    private func applyFinalContrast(to ciImage: CIImage) -> CIImage? {
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.contrast = OptimalParams.finalContrast
        colorControls.saturation = 1.0
        colorControls.brightness = 0.0
        return colorControls.outputImage
    }
}
