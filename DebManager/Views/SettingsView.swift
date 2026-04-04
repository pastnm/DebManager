import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        appHeader
                        aboutSection
                        developerSection
                        footer
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("settings".localized)
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }

    private var appHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [.blue, .cyan, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 88, height: 88)
                    .shadow(color: .blue.opacity(0.4), radius: 16, y: 8)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 40)).foregroundColor(.white)
            }
            Text("Deb Manager").font(.system(size: 24, weight: .bold))
            Text("app_desc".localized).font(.subheadline).foregroundColor(.secondary)
            Text("version".localized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color(white: 0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 20)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("about".localized)
            VStack(spacing: 0) {
                settingsRow(icon: "app.badge.fill", iconColor: .blue, title: "app_name".localized, value: "Deb Manager")
                Divider().padding(.leading, 52)
                settingsRow(icon: "number", iconColor: .purple, title: "version".localized, value: "1.0.0")
                Divider().padding(.leading, 52)
                settingsRow(icon: "cpu", iconColor: .orange, title: "supported_arch".localized, value: "arm, arm64, arm64e")
                Divider().padding(.leading, 52)
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.15)).frame(width: 32, height: 32)
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 16)).foregroundColor(.green)
                    }
                    Text("trollstore_compatible".localized).font(.system(size: 15))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(Color(white: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
        }
    }

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("developer".localized)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    AsyncImage(url: URL(string: "https://pbs.twimg.com/profile_images/1541096226539593728/Yzk8MX-N_400x400.jpg")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56).clipShape(Circle())
                        default:
                            devIconFallback
                        }
                    }
                    .overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 2))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Developer").font(.system(size: 18, weight: .bold))
                        Text("Nasser | NoTimeToChill").font(.system(size: 14)).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(16)

                Divider().padding(.leading, 16)

                Button {
                    openURL(URL(string: "https://x.com/nowesr1")!)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.18)).frame(width: 32, height: 32)
                            Image(systemName: "link").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("follow_twitter".localized).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                            Text("@nowesr1").font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.blue)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            .background(Color(white: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("app_desc".localized).font(.system(size: 12)).foregroundColor(.secondary.opacity(0.5))
            HStack(spacing: 4) {
                Text("Made with")
                Image(systemName: "heart.fill").font(.system(size: 10)).foregroundColor(.red)
                Text("by Nasser | NoTimeToChill")
            }
            .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.top, 12)
    }

    private var devIconFallback: some View {
        ZStack {
            Circle().fill(Color.blue).frame(width: 56, height: 56)
            Text("N").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary).textCase(.uppercase)
            .padding(.horizontal, 20).padding(.bottom, 8)
    }

    private func settingsRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(iconColor)
            }
            Text(title).font(.system(size: 15))
            Spacer()
            Text(value).font(.system(size: 14)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
