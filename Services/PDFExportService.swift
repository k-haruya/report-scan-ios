//
//  PDFExportService.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import UIKit
import PDFKit

class PDFExportService {
    static func generatePDF(from images: [UIImage]) -> Data {
        let pageWidth = Constants.pdfPageWidth
        let pageHeight = Constants.pdfPageHeight
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = pdfRenderer.pdfData { context in
            for image in images {
                autoreleasepool {
                    // ゼロ除算を防止
                    guard image.size.width > 0, image.size.height > 0 else { return }

                    context.beginPage()

                    let aspectRatio = image.size.width / image.size.height

                    var drawRect: CGRect
                    if aspectRatio > pageWidth / pageHeight {
                        let height = pageWidth / aspectRatio
                        drawRect = CGRect(x: 0, y: (pageHeight - height) / 2, width: pageWidth, height: height)
                    } else {
                        let width = pageHeight * aspectRatio
                        drawRect = CGRect(x: (pageWidth - width) / 2, y: 0, width: width, height: pageHeight)
                    }

                    image.draw(in: drawRect)
                }
            }
        }

        return data
    }
}
