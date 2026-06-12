//
//  OCRService.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import Vision
import UIKit

actor OCRService {
    static let shared = OCRService()

    private static let timeoutSeconds: UInt64 = 60  // 60秒タイムアウト

    func recognizeText(from image: UIImage, languages: [String] = ["ja-JP", "en-US"]) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.performOCR(cgImage: cgImage, languages: languages)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
                throw OCRError.timeout
            }

            guard let result = try await group.next() else {
                throw OCRError.timeout
            }

            group.cancelAll()
            return result
        }
    }

    private func performOCR(cgImage: CGImage, languages: [String]) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = languages
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return ""
        }

        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    enum OCRError: LocalizedError {
        case invalidImage
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "画像の読み込みに失敗しました"
            case .timeout:
                return "テキスト認識がタイムアウトしました。画像が大きすぎる可能性があります"
            }
        }
    }
}
