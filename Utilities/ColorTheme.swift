//
//  ColorTheme.swift
//  ReportScan
//
//  Created by Claude Code on 2026/01/29.
//

import SwiftUI

extension Color {
    // プライマリ（青系）
    static let primaryBlue = Color(red: 0.2, green: 0.4, blue: 0.8)
    static let primaryBlueDark = Color(red: 0.15, green: 0.3, blue: 0.6)
    static let primaryBlueLight = Color(red: 0.4, green: 0.6, blue: 0.9)

    // アクセント（SwiftUI組み込みの Color.accentColor と名前衝突を回避）
    static let appAccent = Color(red: 0.3, green: 0.5, blue: 0.9)

    // 背景
    static let backgroundPrimary = Color(UIColor.systemBackground)
    static let backgroundSecondary = Color(UIColor.secondarySystemBackground)

    // テキスト
    static let textPrimary = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
}
