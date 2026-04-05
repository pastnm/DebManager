import SwiftUI
import UIKit

private struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ExportChoice: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.excludedActivityTypes = [.airDrop, .addToReadingList, .assignToContact, .openInIBooks]
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct FileExportSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        controller.shouldShowFileExtensions = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

struct DownloadsView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var showConvertSheet: DownloadedPackage?
    @State private var showDeleteAlert = false
    @State private var packageToDelete: DownloadedPackage?
    @State private var isConverting = false
    // Batch
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBatchConvert = false
    @State private var batchTarget: ArchType = .rootless
    @State private var sharePayload: SharePayload?
    @State private var exportPayload: SharePayload?
    @State private var exportChoice: ExportChoice?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if downloadManager.downloadedPackages.isEmpty {
                    emptyState
                } else {
                    packageList
                }

                // Batch converting overlay
                if downloadManager.isBatchConverting {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.5)
                        Text("converting".localized).font(.headline)
                        let p = downloadManager.batchProgress
                        Text("\(p.current)/\(p.total) — \(p.name)")
                            .font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    .padding(30)
                    .background(Color(white: 0.12).opacity(0.95))
                    .cornerRadius(20)
                }

                if let toast = downloadManager.toastMessage {
                    VStack { ToastView(message: toast); Spacer() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(), value: downloadManager.toastMessage)
                }
            }
            .navigationTitle("downloads".localized)
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(trailing: HStack(spacing: 16) {
                if !downloadManager.downloadedPackages.isEmpty {
                    Button(isSelecting ? "done".localized : "select".localized) {
                        withAnimation { isSelecting.toggle(); if !isSelecting { selectedIDs.removeAll() } }
                    }
                }
            })
            .sheet(item: $showConvertSheet) { pkg in
                ConvertSheet(package: pkg, isConverting: $isConverting) { target in
                    Task {
                        isConverting = true
                        await downloadManager.convertPackage(pkg, to: target)
                        isConverting = false
                        showConvertSheet = nil
                    }
                }
            }
            .sheet(item: $sharePayload) { payload in
                ActivityShareSheet(url: payload.url)
            }
            .sheet(item: $exportPayload) { payload in
                FileExportSheet(url: payload.url)
            }
            .alert("confirm_delete".localized, isPresented: $showDeleteAlert) {
                Button("delete".localized, role: .destructive) {
                    if let pkg = packageToDelete {
                        withAnimation(.spring()) { downloadManager.deletePackage(pkg) }
                    }
                }
                Button("cancel".localized, role: .cancel) {}
            }
            .confirmationDialog("convert_to".localized, isPresented: $showBatchConvert, titleVisibility: .visible) {
                ForEach(ArchType.allCases) { arch in
                    Button(arch.displayName) {
                        let selected = downloadManager.downloadedPackages.filter { selectedIDs.contains($0.id) }
                        Task { await downloadManager.convertBatch(packages: selected, to: arch) }
                        isSelecting = false; selectedIDs.removeAll()
                    }
                }
                Button("cancel".localized, role: .cancel) {}
            }
            .confirmationDialog(
                "share".localized,
                isPresented: Binding(
                    get: { exportChoice != nil },
                    set: { if !$0 { exportChoice = nil } }
                ),
                titleVisibility: .visible,
                presenting: exportChoice
            ) { choice in
                Button("share".localized) {
                    sharePayload = SharePayload(url: choice.url)
                    exportChoice = nil
                }
                Button("save".localized) {
                    exportPayload = SharePayload(url: choice.url)
                    exportChoice = nil
                }
                Button("cancel".localized, role: .cancel) {
                    exportChoice = nil
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle").font(.system(size: 56)).foregroundColor(.blue.opacity(0.4))
            Text("no_downloads".localized).font(.system(size: 18, weight: .semibold)).foregroundColor(.secondary)
            Text("no_downloads_sub".localized).font(.subheadline).foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
    }

    private var packageList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack {
                    Text("managed_debs".localized)
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).textCase(.uppercase)
                    Spacer()
                    Text("\(downloadManager.downloadedPackages.count)")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20).padding(.top, 8)

                // Batch action bar
                if isSelecting && !selectedIDs.isEmpty {
                    HStack(spacing: 12) {
                        Text("\(selectedIDs.count) selected").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Button { showBatchConvert = true } label: {
                            Label("convert".localized, systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.blue.opacity(0.15)).foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 4)
                }

                ForEach(downloadManager.downloadedPackages) { pkg in
                    if isSelecting {
                        SelectablePackageCard(package: pkg, isSelected: selectedIDs.contains(pkg.id)) {
                            if selectedIDs.contains(pkg.id) { selectedIDs.remove(pkg.id) }
                            else { selectedIDs.insert(pkg.id) }
                        }
                    } else {
                        DownloadedPackageCard(
                            package: pkg,
                            onShare: { shareDeb(pkg) },
                            onConvert: { showConvertSheet = pkg },
                            onDelete: { packageToDelete = pkg; showDeleteAlert = true }
                        )
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func shareDeb(_ pkg: DownloadedPackage) {
        let url = downloadManager.getFileURL(for: pkg)
        guard FileManager.default.fileExists(atPath: url.path) else {
            downloadManager.showToast("File not found"); return
        }

        let sharedURL: URL
        do {
            sharedURL = try makeSharableCopy(of: url)
        } catch {
            downloadManager.showToast("share".localized + ": \(error.localizedDescription)")
            return
        }
        exportChoice = ExportChoice(url: sharedURL)
    }

    private func makeSharableCopy(of url: URL) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("SharedDebs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let destination = dir.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: url, to: destination)
        return destination
    }
}

// MARK: - Selectable Card (batch mode)
struct SelectablePackageCard: View {
    let package: DownloadedPackage
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(package.package.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    BadgeLabel(text: package.package.version, color: .blue)
                    BadgeLabel(text: package.archType.displayName, color: archColor)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(white: isSelected ? 0.15 : 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var archColor: Color {
        switch package.archType { case .rootful: return .red; case .rootless: return .blue; case .roothide: return .purple }
    }
}

// MARK: - Downloaded Package Card
struct DownloadedPackageCard: View {
    let package: DownloadedPackage
    let onShare: () -> Void
    let onConvert: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.1)).frame(width: 44, height: 44)
                    Image(systemName: "doc.zipper").font(.system(size: 18)).foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(package.package.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(package.package.bundleID).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    HStack(spacing: 4) {
                        BadgeLabel(text: package.package.version, color: .blue)
                        BadgeLabel(text: package.archType.displayName, color: archColor)
                        if let sz = formattedSize { Text(sz).font(.system(size: 9)).foregroundColor(Color(white: 0.5)) }
                    }
                }
                Spacer()
            }
            .padding(12)

            HStack(spacing: 0) {
                ActionButton(icon: "square.and.arrow.up", label: "share".localized, color: .blue, action: onShare)
                Divider().frame(height: 32)
                ActionButton(icon: "arrow.triangle.2.circlepath", label: "convert".localized, action: onConvert)
                Divider().frame(height: 32)
                ActionButton(icon: "trash", label: "delete".localized, color: .red, action: onDelete)
            }
            .padding(.vertical, 4).background(Color(white: 0.08))
        }
        .background(Color(white: 0.11)).clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 16)
    }

    private var formattedSize: String? {
        let s = package.package.sizeFormatted
        return (s == "Zero KB" || s == "0" || s.isEmpty) ? nil : s
    }
    private var archColor: Color {
        switch package.archType { case .rootful: return .red; case .rootless: return .blue; case .roothide: return .purple }
    }
}

struct ActionButton: View {
    let icon: String; let label: String; var color: Color = .secondary; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 15))
                Text(label).font(.system(size: 9, weight: .medium))
            }.foregroundColor(color).frame(maxWidth: .infinity).padding(.vertical, 5)
        }
    }
}

struct ConvertSheet: View {
    let package: DownloadedPackage; @Binding var isConverting: Bool; let onConvert: (ArchType) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 36)).foregroundColor(.blue)
                    Text(package.package.name).font(.system(size: 17, weight: .semibold))
                    HStack(spacing: 4) {
                        Text("current_arch".localized + ":").foregroundColor(.secondary)
                        Text(package.archType.displayName).fontWeight(.semibold).foregroundColor(.orange)
                    }.font(.system(size: 14))
                }.padding(.top, 12)
                if isConverting {
                    VStack(spacing: 12) { ProgressView().scaleEffect(1.3); Text("converting".localized).font(.subheadline).foregroundColor(.secondary) }.padding(.vertical, 20)
                } else {
                    VStack(spacing: 10) {
                        Text("convert_to".localized).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).textCase(.uppercase)
                        ForEach(ArchType.allCases.filter { $0 != package.archType }) { arch in
                            Button { onConvert(arch) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(arch.displayName).font(.system(size: 15, weight: .semibold))
                                        Text(arch.archString).font(.system(size: 12)).opacity(0.7)
                                    }; Spacer()
                                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 22))
                                }.padding(14).foregroundColor(btnColor(arch))
                                .background(btnColor(arch).opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(btnColor(arch).opacity(0.2), lineWidth: 1))
                            }
                        }
                    }.padding(.horizontal, 20)
                }; Spacer()
            }.navigationTitle("convert".localized).navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("cancel".localized) { if !isConverting { dismiss() } }.disabled(isConverting))
        }
    }
    private func btnColor(_ a: ArchType) -> Color {
        switch a { case .rootful: return .red; case .rootless: return .blue; case .roothide: return .purple }
    }
}

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color.green.opacity(0.9)).clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4).padding(.top, 8)
    }
}
