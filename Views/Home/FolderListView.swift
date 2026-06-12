import SwiftUI
import SwiftData

struct FolderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: HomeViewModel
    @Binding var navigationPath: NavigationPath

    @Query(sort: \DocumentFolder.updatedAt, order: .reverse) private var folders: [DocumentFolder]

    @State private var showingSettings = false

    var body: some View {
        List {
            // フォルダセクション
            Section {
                if folders.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("フォルダを作成してドキュメントを整理しましょう")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(folders) { folder in
                        Button {
                            navigateToFolder(folder)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name)
                                        .font(.headline)
                                    if !folder.documents.isEmpty {
                                        Text("\(folder.documents.count)件のドキュメント")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            .padding(.vertical, 4)
                        }
                        .foregroundStyle(.primary) // Buttonのデフォルトスタイルを上書き
                        // 長押しメニュー
                        .contextMenu {
                            Button {
                                viewModel.showEditFolderDialog(folder)
                            } label: {
                                Label("名前変更", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                viewModel.showDeleteFolderConfirmation(folder)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.showDeleteFolderConfirmation(folder)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }

                            Button {
                                viewModel.showEditFolderDialog(folder)
                            } label: {
                                Label("名前変更", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            } header: {
                Text("マイフォルダ")
            }
        }
        .navigationTitle("レポートスキャン")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.headline)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.showCreateFolderDialog()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.headline)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("新規フォルダ", isPresented: $viewModel.showingFolderNameAlert) {
            TextField("フォルダ名", text: $viewModel.folderNameInput)
            Button("キャンセル", role: .cancel) {}
            Button(viewModel.editingFolder == nil ? "作成" : "保存") {
                viewModel.confirmFolderName()
            }
        } message: {
            Text(viewModel.editingFolder == nil ? "新しいフォルダの名前を入力してください" : "フォルダ名を変更します")
        }
        .alert("フォルダを削除", isPresented: $viewModel.showingDeleteFolderAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                viewModel.confirmDeleteFolder()
            }
        } message: {
            Text("このフォルダと中のすべてのドキュメントを削除してもよろしいですか？この操作は取り消せません。")
        }
        .alert("エラー", isPresented: $viewModel.showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onAppear {
            viewModel.modelContext = modelContext
        }
    }
    
    private func navigateToFolder(_ folder: DocumentFolder) {
        navigationPath.append(NavigationDestination.folder(folder.id))
    }
}

// ナビゲーション用の列挙型
enum NavigationDestination: Hashable {
    case folder(UUID)
}
