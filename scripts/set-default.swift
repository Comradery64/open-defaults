import AppKit
import UniformTypeIdentifiers

// usage: swift scripts/set-default.swift <uti> <app path>
// WARNING: changes system default app associations.

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    print("usage: set-default.swift <uti> <app path>")
    exit(64)
}

guard let type = UTType(args[0]) else {
    print("unknown type")
    exit(1)
}

// The macOS 26 SDK only exposes the completion-handler form, so bridge it.
let setError: Error? = await withCheckedContinuation { cont in
    NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: args[1]), toOpen: type) { cont.resume(returning: $0) }
}
if let setError {
    print("set failed: \(setError)")
    exit(3)
}
print("set ok")

let defaultURL = NSWorkspace.shared.urlForApplication(toOpen: type)
let defaultID = defaultURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
print("type: \(type.identifier) | \(type.localizedDescription ?? "-") | .\(type.preferredFilenameExtension ?? "-")")
print("default: \(defaultURL?.path ?? "none") (\(defaultID ?? "none"))")

let candidates = NSWorkspace.shared.urlsForApplications(toOpen: type)
print("candidates: \(candidates.count)")
for url in candidates {
    print("  \(Bundle(url: url)?.bundleIdentifier ?? "-") \(url.path)")
}
