import AppKit
import UniformTypeIdentifiers

// usage: swift scripts/snapshot-defaults.swift <uti> [<uti> ...]
// Read-only: prints a markdown table of current default handlers. Never changes defaults.

print("| uti | description | default bundle id | default path | candidates |")
print("|---|---|---|---|---|")
for uti in CommandLine.arguments.dropFirst() {
    let type = UTType(uti)
    let description = type?.localizedDescription ?? "-"
    let defaultURL = type.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    let defaultID = defaultURL.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? "none"
    let defaultPath = defaultURL?.path ?? "none"
    let candidates = type.map { NSWorkspace.shared.urlsForApplications(toOpen: $0).count } ?? 0
    print("| \(uti) | \(description) | \(defaultID) | \(defaultPath) | \(candidates) |")
}
