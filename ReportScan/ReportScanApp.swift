//
//  ReportScanApp.swift
//  ReportScan
//
//  Created by k-haruya on 2026/01/29.
//

import SwiftUI
import SwiftData

// MARK: - Schema Versioning (将来のマイグレーションに備える)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [DocumentFolder.self, ScannedDocument.self]
    }
}

enum ReportScanMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // 将来のマイグレーションステージをここに追加
        []
    }
}

@main
struct ReportScanApp: App {
    private let modelContainer: ModelContainer?
    private let initializationError: String?

    init() {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            self.modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: ReportScanMigrationPlan.self,
                configurations: [modelConfiguration]
            )
            self.initializationError = nil
        } catch {
            self.modelContainer = nil
            self.initializationError = "データベースの初期化に失敗しました: \(error.localizedDescription)"
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let container = modelContainer {
                HomeView()
                    .modelContainer(container)
            } else {
                DatabaseErrorView(errorMessage: initializationError ?? "不明なエラー")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // バックグラウンド遷移時に未保存のSwiftData変更を永続化
                try? modelContainer?.mainContext.save()
            }
        }
    }
}

// データベースエラー画面
struct DatabaseErrorView: View {
    let errorMessage: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("アプリを起動できません")
                .font(.title2)
                .fontWeight(.bold)

            Text(errorMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("アプリを再インストールするか、デバイスを再起動してください。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
