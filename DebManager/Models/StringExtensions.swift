import Foundation

private let zhHansTranslations: [String: String] = [
    "about": "关于",
    "add": "添加",
    "add_repo": "添加软件源",
    "add_repo_hint": "输入兼容 Cydia/Sileo 的软件源 URL",
    "already_downloaded": "已下载",
    "app_desc": "iOS .deb 软件包管理器",
    "app_name": "应用名称",
    "back": "返回",
    "browse": "浏览",
    "browse_repo": "浏览",
    "cancel": "取消",
    "confirm_delete": "确认删除此软件包？",
    "conversion_failed": "转换失败",
    "convert": "转换",
    "convert_to": "转换为",
    "converted": "转换完成！",
    "converted_to": "已转换为",
    "converting": "转换中...",
    "current_arch": "当前架构",
    "delete": "删除",
    "deleted": "已删除",
    "developer": "开发者",
    "done": "完成",
    "download": "下载",
    "download_failed": "下载失败",
    "downloaded_success": "下载成功",
    "downloading": "下载中...",
    "downloads": "下载",
    "follow_twitter": "在 𝕏 上关注",
    "language": "语言",
    "language_auto": "跟随设备语言",
    "loading": "加载中...",
    "managed_debs": "已管理的软件包",
    "no": "否",
    "no_downloads": "无已下载的软件包",
    "no_downloads_sub": "下载的 .deb 文件将显示在此处",
    "no_repos": "无软件源",
    "no_repos_sub": "添加软件源以开始浏览和下载 .deb 软件包",
    "no_results": "未找到结果。请尝试不同的搜索词。",
    "packages": "软件包",
    "packages_converted": "个软件包已转换",
    "remove": "移除",
    "repo_packages": "软件源软件包",
    "repo_url": "软件源 URL",
    "repos": "软件源",
    "save": "保存",
    "saved_to": "已保存到“文件”应用",
    "search": "搜索软件包...",
    "search_btn": "搜索",
    "search_results": "搜索结果",
    "searching": "搜索中...",
    "select": "选择",
    "settings": "设置",
    "share": "分享",
    "shared_via": "已打开分享面板",
    "start_search": "搜索 .deb 软件包",
    "start_search_sub": "从 iOS 软件源中查找插件、应用和工具",
    "supported_arch": "支持的架构",
    "supported_languages": "支持的语言",
    "target_arch": "目标架构",
    "trollstore_compatible": "兼容 TrollStore (巨魔)",
    "version": "版本 1.0.0",
    "yes": "是"
]

private func prefersSimplifiedChinese() -> Bool {
    let preferredLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier

    return preferredLanguage.hasPrefix("zh-Hans")
        || preferredLanguage.hasPrefix("zh-CN")
        || preferredLanguage.hasPrefix("zh-SG")
}

extension String {
    var localized: String {
        if prefersSimplifiedChinese(), let translation = zhHansTranslations[self] {
            return translation
        }

        NSLocalizedString(self, comment: "")
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
}
