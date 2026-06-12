//
//  SettingsView.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("imageQuality") private var imageQuality: Double = 0.8
    @AppStorage("ocrLanguage") private var ocrLanguage: String = "ja-JP"
    @AppStorage("autoSaveOCR") private var autoSaveOCR: Bool = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                imageQualitySection
                ocrSection
                aboutSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var imageQualitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("画質")
                    Spacer()
                    Text("\(Int(imageQuality * 100))%")
                        .foregroundColor(.secondary)
                }

                Slider(value: $imageQuality, in: 0.5...1.0, step: 0.1)

                Text("画像の保存品質を設定します。品質が高いほどファイルサイズが大きくなります。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("画像設定")
        }
    }

    private var ocrSection: some View {
        Section {
            Picker("認識言語", selection: $ocrLanguage) {
                Text("日本語").tag("ja-JP")
                Text("英語").tag("en-US")
                Text("日本語 + 英語").tag("ja-JP,en-US")
            }

            Toggle("OCR後に自動保存", isOn: $autoSaveOCR)

            Text("テキスト認識の言語設定と自動保存の動作を設定します。")
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text("OCR設定")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("アプリ名")
                Spacer()
                Text(Constants.appName)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("バージョン")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("アプリ情報")
        }
    }
}
