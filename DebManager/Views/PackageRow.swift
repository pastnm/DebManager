import SwiftUI

struct PackageRow: View {
    let package: Package
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(sectionGradient)
                    .frame(width: 44, height: 44)
                Image(systemName: sectionIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Tweak NAME - prominent
                Text(package.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                // Description if available, otherwise bundle ID
                if !package.description.isEmpty {
                    Text(package.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if package.name != package.bundleID {
                    Text(package.bundleID)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Compact badges
                HStack(spacing: 4) {
                    if !package.version.isEmpty && package.version != "—" {
                        BadgeLabel(text: package.version, color: .blue)
                    }
                    BadgeLabel(text: package.archLabel, color: archColor)
                    if let sz = formattedSize {
                        Text(sz)
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            downloadButton
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var formattedSize: String? {
        let s = package.sizeFormatted
        if s == "Zero KB" || s == "0" || s.isEmpty { return nil }
        return s
    }

    @ViewBuilder
    private var downloadButton: some View {
        if downloadManager.progress(for: package.uid) != nil {
            ProgressView().frame(width: 28, height: 28)
        } else if downloadManager.isDownloaded(package) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22)).foregroundColor(.green)
        } else {
            Button {
                Task { await downloadManager.downloadPackage(package) }
            } label: {
                Text("download".localized)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    private var archColor: Color {
        let a = package.archLabel
        if a.contains("arm64e") { return .purple }
        if a.contains("arm64") { return .orange }
        return .green
    }

    private var sectionIcon: String {
        let s = package.section.lowercased()
        if s.contains("theme") { return "paintbrush.fill" }
        if s.contains("tweak") { return "slider.horizontal.3" }
        if s.contains("util") { return "wrench.and.screwdriver.fill" }
        if s.contains("system") { return "gearshape.2.fill" }
        if s.contains("dev") { return "hammer.fill" }
        if s.contains("package") { return "shippingbox.fill" }
        if s.contains("jailbreak") { return "lock.open.fill" }
        return "app.fill"
    }

    private var sectionGradient: LinearGradient {
        let s = package.section.lowercased()
        if s.contains("theme") {
            return LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if s.contains("tweak") {
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if s.contains("util") {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if s.contains("jailbreak") {
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if s.contains("dev") {
            return LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Compact Badge
struct BadgeLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
