// Harvests the posts on an X page open in Chrome through the Accessibility API, one JSON line per post in the
// FluidUse `Bookmark` format ({"id", "author", "createdAt", "text", "media"}, plus "harvestedAt"), which
// TopicSortDemo reads.
//
//     xharvest --url=https://x.com/i/history --out=data/bookmarks.jsonl [--max=20000]
//
// Unlike FluidUse's `BookmarkSortCheck --harvest` (whose post parsing this follows, Apache-2.0), it reads the Chrome
// window whose current page is `--url`, not whichever X window happens to be frontmost, so other X
// windows can stay open. Re-running resumes: ids already in the output are skipped.
import AppKit
import ApplicationServices
import Foundation

struct Post: Codable {
    let id: String
    let author: String
    let createdAt: String
    let text: String
    let media: [String]
    /// When this run first saw the post (ISO 8601). Posts from one run are written in page order, newest first.
    var harvestedAt: String?
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func webArea(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" { return element }
    guard depth < 14 else { return nil }
    for child in children(element) {
        if let found = webArea(child, depth: depth + 1) { return found }
    }
    return nil
}

func articles(_ element: AXUIElement, into found: inout [AXUIElement]) {
    if attribute(element, kAXSubroleAttribute) as? String == "AXDocumentArticle" {
        found.append(element)
        return
    }
    for child in children(element) { articles(child, into: &found) }
}

let permalink = try! NSRegularExpression(pattern: #"^https://(?:x|twitter)\.com/([A-Za-z0-9_]+)/status/(\d+)$"#)
/// Controls whose text is chrome, not post content.
let skippedRoles: Set<String> = ["AXLink", "AXButton", "AXPopUpButton", "AXMenuButton", "AXToolbar", "AXScrollBar"]

func post(from article: AXUIElement) -> Post? {
    var identity: (author: String, id: String)?
    var date = ""
    var texts: [String] = []
    var media: [String] = []
    func visit(_ element: AXUIElement) {
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let url = (attribute(element, "AXURL") as? URL)?.absoluteString
        if role == "AXLink", let url {
            if identity == nil,
                let match = permalink.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
                let author = Range(match.range(at: 1), in: url), let id = Range(match.range(at: 2), in: url)
            {
                identity = (String(url[author]), String(url[id]))
                date = attribute(element, kAXDescriptionAttribute) as? String ?? ""
            }
            if url.contains("/photo/") { media.append("photo") }
            if url.contains("/video/") { media.append("video") }
        }
        // A quoted post is a link without a URL; its text belongs to this post.
        if skippedRoles.contains(role), role != "AXLink" || url != nil { return }
        if role == "AXStaticText", let value = attribute(element, kAXValueAttribute) as? String {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count > 1 { texts.append(text) }
        }
        for child in children(element) { visit(child) }
    }
    visit(article)
    guard let identity, !texts.isEmpty else { return nil }
    return Post(id: identity.id, author: identity.author, createdAt: date, text: texts.joined(separator: "\n"), media: media)
}

func value(_ name: String) -> String? {
    CommandLine.arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
}

guard let pageURL = value("url"), let outputPath = value("out") else {
    FileHandle.standardError.write(Data("usage: xharvest --url=<page url> --out=<file.jsonl> [--max=N]\n".utf8))
    exit(2)
}
let target = value("max").flatMap(Int.init) ?? 20000
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("No Accessibility permission for this terminal (System Settings → Privacy & Security → Accessibility).\n".utf8))
    exit(1)
}
guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else {
    FileHandle.standardError.write(Data("Chrome is not running\n".utf8))
    exit(1)
}
let app = AXUIElementCreateApplication(chrome.processIdentifier)
// Chromium builds its web-content accessibility tree only when asked.
AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

/// The web area of the Chrome window showing `pageURL` (ignoring query and fragment); Chromium fills web content in a few seconds after first asked.
func page(_ app: AXUIElement, _ pageURL: String) async -> AXUIElement? {
    for _ in 0..<30 {
        for window in (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            if let area = webArea(window), let url = (attribute(area, "AXURL") as? URL)?.absoluteString,
                url.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) == pageURL
            {
                return area
            }
        }
        try? await Task.sleep(for: .milliseconds(500))
    }
    return nil
}

guard var area = await page(app, pageURL) else {
    FileHandle.standardError.write(Data("No Chrome window shows \(pageURL)\n".utf8))
    exit(1)
}

var seen = Set<String>()
if let existing = try? String(contentsOfFile: outputPath, encoding: .utf8) {
    for line in existing.split(separator: "\n") {
        if let post = try? JSONDecoder().decode(Post.self, from: Data(line.utf8)) { seen.insert(post.id) }
    }
} else {
    FileManager.default.createFile(atPath: outputPath, contents: nil)
}
let output = FileHandle(forWritingAtPath: outputPath)!
output.seekToEndOfFile()
let startCount = seen.count
let runStamp = ISO8601DateFormatter().string(from: Date())
var stale = 0
while seen.count < target, stale < 12 {
    let before = seen.count
    var found: [AXUIElement] = []
    articles(area, into: &found)
    if found.isEmpty, let fresh = await page(app, pageURL) { area = fresh }  // the tree was rebuilt (e.g. after navigation)
    for article in found {
        guard var post = post(from: article), !seen.contains(post.id) else { continue }
        post.harvestedAt = runStamp
        seen.insert(post.id)
        output.write(try JSONEncoder().encode(post) + Data("\n".utf8))
    }
    stale = seen.count == before ? stale + 1 : 0
    FileHandle.standardError.write(Data("\r\(seen.count) posts (\(seen.count - startCount) new)   ".utf8))
    // Bringing the last loaded post into view makes X load the next page.
    if let last = found.last { AXUIElementPerformAction(last, "AXScrollToVisible" as CFString) }
    try await Task.sleep(for: .milliseconds(stale > 0 ? 2500 : 1200))
}
try output.close()
FileHandle.standardError.write(Data("\nharvested \(seen.count - startCount) new posts, \(seen.count) total → \(outputPath)\n".utf8))
