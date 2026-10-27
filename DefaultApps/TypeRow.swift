import AppKit
import SwiftUI

struct TypeRow: View {
    let row: HandlerStore.Row
    var canRevert = false
    @ScaledMetric private var iconSize = 28.0
    @ScaledMetric private var appIconSize = 14.0

    var body: some View {
        HStack(spacing: 8) {
            TypeIcon(row: row, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.type.name).font(.body).lineLimit(1)
                    if let ext = row.type.ext {
                        Text(".\(ext)").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let app = row.current, !app.exists {
                    Text("\(app.name) was moved or deleted.").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if let app = row.current {
                    HStack(spacing: 4) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: appIconSize, height: appIconSize)
                        Text(app.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text("No default app").font(.caption).foregroundStyle(.secondary)
                }
            }
            if canRevert {
                Spacer(minLength: 0)
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var text = row.type.name
        if let app = row.current {
            text += app.exists ? ", opens with \(app.name)" : ", \(app.name) was moved or deleted"
        } else {
            text += ", no default app"
        }
        return canRevert ? text + ", revert available" : text
    }
}

/// Blank document with the current app's icon on it. NSWorkspace's type icon embeds the
/// default app too, but macOS caches it, so it keeps showing the previous app after a change.
struct TypeIcon: View {
    let row: HandlerStore.Row
    let size: Double

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: .data))
            .resizable()
            .frame(width: size, height: size)
            .overlay {
                if let app = row.current {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: size * 0.5, height: size * 0.5)
                }
            }
    }
}
