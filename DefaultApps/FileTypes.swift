import Foundation
import UniformTypeIdentifiers

struct FileType: Identifiable, Hashable {
    let id: String
    let name: String
    let ext: String?

    /// Safe: only built by `FileTypes.make`, which drops ids that are not valid UTIs.
    var utType: UTType { UTType(id)! }
}

enum FileTypes {
    static let curated: [String] = [
        "com.compuserve.gif",
        "public.png",
        "public.jpeg",
        "public.heic",
        "public.tiff",
        "com.microsoft.bmp",
        "public.svg-image",
        "org.webmproject.webp",
        "com.adobe.pdf",
        "com.adobe.photoshop-image",
        "net.daringfireball.markdown",
        "public.plain-text",
        "public.rtf",
        "public.html",
        "public.css",
        "public.json",
        "public.xml",
        "public.yaml",
        "public.comma-separated-values-text",
        "public.python-script",
        "public.shell-script",
        "public.swift-source",
        "public.c-source",
        "public.mpeg-4",
        "com.apple.quicktime-movie",
        "public.avi",
        "public.mp3",
        "public.mpeg-4-audio",
        "com.microsoft.waveform-audio",
        "public.aiff-audio",
        "public.zip-archive",
        "org.gnu.gnu-zip-archive",
        "public.tar-archive",
        "com.apple.disk-image-udif",
        "org.openxmlformats.wordprocessingml.document",
        "org.openxmlformats.spreadsheetml.sheet",
        "org.openxmlformats.presentationml.presentation",
        "public.vcard",
        "com.apple.ical.ics",
        "public.log",
        "public.font",
        "org.idpf.epub-container",
    ]

    static func make(from identifiers: [String]) -> [FileType] {
        var seen = Set<String>()
        var types: [String: FileType] = [:]  // keyed by name + extension
        for id in identifiers {
            guard let t = UTType(id), seen.insert(t.identifier).inserted,
                  let name = t.localizedDescription else { continue }
            let type = FileType(id: t.identifier, name: name, ext: t.preferredFilenameExtension)
            let key = type.ext.map { name + "." + $0 } ?? t.identifier
            // Same name and extension (e.g. public.mp2 and com.apple.music.mp2): keep the type
            // that files with that extension actually resolve to.
            if let ext = type.ext, types[key] != nil,
               UTType(filenameExtension: ext)?.identifier != t.identifier { continue }
            types[key] = type
        }
        return types.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func declaredIdentifiers() -> [String] {
        let fm = FileManager.default
        let dirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
        ]
        var ids = Set<String>()
        for dir in dirs {
            let base = URL(fileURLWithPath: dir)
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".app") {
                let docs = Bundle(url: base.appendingPathComponent(name))?
                    .infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
                for id in docs.flatMap({ ($0["LSItemContentTypes"] as? [String]) ?? [] }) {
                    guard let t = UTType(id), !t.isDynamic,
                          t.localizedDescription != nil,
                          t.preferredFilenameExtension != nil else { continue }
                    ids.insert(id)
                }
            }
        }
        return ids.sorted()
    }

    static func all() -> [FileType] {
        make(from: curated + declaredIdentifiers())
    }

    static func filter(_ types: [FileType], query: String) -> [FileType] {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.hasPrefix(".") { q.removeFirst() }
        guard !q.isEmpty else { return types }
        return types.filter { t in
            t.name.localizedStandardContains(q)
                || (t.ext?.localizedStandardContains(q) ?? false)
                || t.id.localizedStandardContains(q)
        }
    }
}
