import SwiftUI
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import HSACore

@main
struct HSAReceiptsApp: App {
    @StateObject private var store = ReceiptStore()
    @StateObject private var scanner = ScanCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(scanner)
        }
    }
}

enum AppTab: Hashable { case dashboard, receipts, reimburse, settings }

/// Drives the "add a receipt" flow from any screen.
@MainActor
final class ScanCoordinator: ObservableObject {
    @Published var showCamera = false
    @Published var showPhotoPicker = false
    @Published var showFileImporter = false
    @Published var photoSelection: [PhotosPickerItem] = []
    @Published var draft: ReceiptScanner.Draft?
    @Published var isAnalyzing = false
    @Published var selectedTab: AppTab = .dashboard

    var cameraAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func handle(images: [UIImage], addedBy: String) {
        guard !images.isEmpty else { return }
        isAnalyzing = true
        Task {
            draft = await ReceiptScanner.analyze(images: images, addedBy: addedBy)
            isAnalyzing = false
        }
    }

    func handlePhotos(addedBy: String) {
        let items = photoSelection
        photoSelection = []
        guard !items.isEmpty else { return }
        isAnalyzing = true
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            draft = await ReceiptScanner.analyze(images: images, addedBy: addedBy)
            isAnalyzing = false
        }
    }

    func handleFile(_ url: URL, addedBy: String, store: ReceiptStore) {
        isAnalyzing = true
        Task {
            do {
                draft = try await ReceiptScanner.analyze(fileAt: url, addedBy: addedBy)
            } catch {
                store.lastError = error.localizedDescription
            }
            isAnalyzing = false
        }
    }
}

/// Menu used in toolbars: scan, photo library, or Files.
struct AddReceiptMenu: View {
    @EnvironmentObject private var scanner: ScanCoordinator

    var body: some View {
        Menu {
            if scanner.cameraAvailable {
                Button { scanner.showCamera = true } label: { Label("Scan receipt", systemImage: "doc.viewfinder") }
            }
            Button { scanner.showPhotoPicker = true } label: { Label("Choose photo", systemImage: "photo.on.rectangle") }
            Button { scanner.showFileImporter = true } label: { Label("Import PDF or file", systemImage: "folder") }
        } label: {
            Label("Add receipt", systemImage: "plus.circle.fill")
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: ReceiptStore
    @EnvironmentObject private var scanner: ScanCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("userName") private var userName = ""
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        TabView(selection: $scanner.selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(AppTab.dashboard)
            ReceiptListView()
                .tabItem { Label("Receipts", systemImage: "doc.text.fill") }
                .tag(AppTab.receipts)
            ReimburseView()
                .tabItem { Label("Reimburse", systemImage: "dollarsign.arrow.circlepath") }
                .tag(AppTab.reimburse)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .task { await store.reload() }
        .onChange(of: scenePhase) { _, phase in
            // Pick up receipts your spouse added on their phone.
            if phase == .active { Task { await store.reload() } }
        }
        .overlay {
            if scanner.isAnalyzing {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Reading receipt…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .fullScreenCover(isPresented: $scanner.showCamera) {
            DocumentScannerView(
                onFinish: { images in
                    scanner.showCamera = false
                    scanner.handle(images: images, addedBy: userName)
                },
                onCancel: { scanner.showCamera = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $scanner.showPhotoPicker, selection: $scanner.photoSelection,
                      maxSelectionCount: 5, matching: .images)
        .onChange(of: scanner.photoSelection) { _, items in
            if !items.isEmpty { scanner.handlePhotos(addedBy: userName) }
        }
        .fileImporter(isPresented: $scanner.showFileImporter, allowedContentTypes: [.pdf, .image]) { result in
            if case .success(let url) = result { scanner.handleFile(url, addedBy: userName, store: store) }
        }
        .sheet(item: $scanner.draft) { draft in
            NavigationStack {
                ReceiptEditorView(receipt: draft.receipt, pendingAttachments: draft.attachments, isNew: true)
            }
        }
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })) {
            OnboardingView()
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.lastError != nil },
                                                            set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: ReceiptStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName = ""
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "cross.case.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
                        Text("HSA Receipts").font(.title.bold())
                        Text("Scan receipts, see which expenses are likely HSA-eligible, and track what you can still reimburse yourself for — shared with your household through iCloud Drive.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("Your name") {
                    TextField("e.g. Michael", text: $userName)
                        .textContentType(.givenName)
                }
                Section {
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Choose shared iCloud Drive folder", systemImage: "icloud")
                    }
                    Button("Use this iPhone for now") { finish() }
                } header: {
                    Text("Where to save receipts")
                } footer: {
                    Text("Tip: in the Files app, create a folder like iCloud Drive › HSA Receipts, share it with your spouse (Share › Collaborate), then pick that folder here on both phones.")
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    store.useFolder(url)
                    finish()
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        hasOnboarded = true
        dismiss()
    }
}
