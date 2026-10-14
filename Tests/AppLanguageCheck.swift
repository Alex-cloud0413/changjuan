import Foundation

@main
struct AppLanguageCheck {
    static func main() {
        let suite = CommandLine.arguments[1]
        let defaults = UserDefaults(suiteName: suite)!
        if CommandLine.arguments.contains("--write") {
            defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
            defaults.synchronize() // Only isolated test storage; force process-boundary verification.
            return
        }
        if CommandLine.arguments.contains("--read") {
            precondition(AppLanguage.read(from: defaults) == .english)
            defaults.removePersistentDomain(forName: suite)
            print("Language selection survived a process restart")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(AppLanguage.read(from: defaults, fallback: .chinese) == .chinese)
        defaults.set("unsupported-future-language", forKey: AppLanguage.preferenceKey)
        precondition(AppLanguage.read(from: defaults, fallback: .chinese) == .chinese)
        defaults.set("en", forKey: AppLanguage.preferenceKey)
        precondition(AppLanguage.read(from: defaults) == .english)
        defaults.set("zh-Hans", forKey: AppLanguage.preferenceKey)
        precondition(AppLanguage.read(from: defaults) == .chinese)
        precondition(AppLanguage.chinese.text("查看使用方法") == "查看使用方法")
        precondition(AppLanguage.english.text("查看使用方法") == "How to use")
        precondition(AppLanguage.english.format("第 %ld 步，共 %ld 步", 2, 3) == "Step 2 of 3")
        precondition(AppLanguage.chinese.format("第 %ld 步，共 %ld 步", 2, 3) == "第 2 步，共 3 步")
        precondition(AppLanguage.english.format("长图 %ld / %ld", 1, 2) == "Image 1 / 2")
        precondition(AppLanguage.english.format("长卷已保存为 %ld 张长图", 2) == "Long Scroll saved 2 images")
        precondition(AppLanguage.english.text("无法读取画面：frame-001.jpg") == "Unable to read frame: frame-001.jpg")
        precondition(AppLanguage.english.text("第 2 页没有采集到可连续拼接的内容。请在切换后点「继续」，再缓慢滚动；原始画面已保留。").hasPrefix("Page 2 has no continuous"))
        precondition(AppLanguage.english.text("Unknown OS error 42") == "Unknown OS error 42")
        precondition(AppLanguage.initialLanguage(isExistingInstallation: true, preferredLanguages: ["en-US"]) == .chinese)
        precondition(AppLanguage.initialLanguage(isExistingInstallation: false, preferredLanguages: ["en-US"]) == .english)
        precondition(AppLanguage.initialLanguage(isExistingInstallation: false, preferredLanguages: ["zh-Hans"]) == .chinese)
        precondition(AppLanguage.initialLanguage(isExistingInstallation: false, preferredLanguages: ["fr-FR"]) == .english)
        for (source, translation) in AppLanguage.englishText {
            precondition(!source.isEmpty && !translation.isEmpty)
            precondition(AppLanguage.chinese.text(source) == source)
            precondition(AppLanguage.english.text(source) == translation)
        }
        print("Language behavior checks passed (17), plus \(AppLanguage.englishText.count) bilingual entries")
    }
}
