import AppKit
import UniformTypeIdentifiers

// usage: swift scripts/check-default.swift <uti> [--expect <bundle-id>]

let args = Array(CommandLine.arguments.dropFirst())
guard let uti = args.first else {
    print("usage: check-default.swift <uti> [--expect <bundle-id>]")
    exit(64)
}
var expect: String? = nil
if let i = args.firstIndex(of: "--expect"), i + 1 < args.count {
    expect = args[i + 1]
}

guard let type = UTType(uti) else {
    print("unknown type")
    exit(1)
}

print("type: \(type.identifier) | \(type.localizedDescription ?? "-") | .\(type.preferredFilenameExtension ?? "-")")

let defaultURL = NSWorkspace.shared.urlForApplication(toOpen: type)
let defaultID = defaultURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
print("default: \(defaultURL?.path ?? "none") (\(defaultID ?? "none"))")

let candidates = NSWorkspace.shared.urlsForApplications(toOpen: type)
print("candidates: \(candidates.count)")
for url in candidates {
    print("  \(Bundle(url: url)?.bundleIdentifier ?? "-") \(url.path)")
}

if let expect {
    if defaultID == expect {
        exit(0)
    }
    print("MISMATCH")
    exit(2)
}
