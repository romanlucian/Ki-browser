import AppKit
import ClearframeCore
import Foundation
import SwiftUI

struct DownloadsPopover: View {
    @ObservedObject var center: DownloadCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Downloads", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                Spacer()
                if center.items.contains(where: { !$0.status.isActive }) {
                    Button("Clear Finished") { center.clearFinished() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                }
            }

            if center.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(DownloadCenter.emptyStateTitle)
                        .font(.headline)
                    Text(DownloadCenter.emptyStateMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Clearframe asks where to save every file and does not keep permanent download history yet.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(center.items) { item in
                            DownloadItemView(item: item, center: center, detailWidth: 275)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()
            Button {
                center.openDownloadsFolder()
            } label: {
                Label("Open Downloads Folder", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .font(.callout.weight(.medium))
        }
        .padding(16)
        .frame(width: 420)
    }
}

struct DownloadShelf: View {
    @ObservedObject var center: DownloadCenter

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Label("Downloads", systemImage: "arrow.down.circle.fill").font(.caption.bold())
                Spacer()
                if center.items.contains(where: { !$0.status.isActive }) {
                    Button("Clear Finished") { center.clearFinished() }.buttonStyle(.plain).font(.caption)
                }
                Button { center.isShelfVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Hide downloads")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if center.items.isEmpty {
                        Text(DownloadCenter.emptyStateMessage)
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(center.items) { item in
                        DownloadItemView(item: item, center: center, detailWidth: 210)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct DownloadItemView: View {
    let item: DownloadItem
    @ObservedObject var center: DownloadCenter
    let detailWidth: CGFloat

    var body: some View {
        HStack(spacing: 9) {
            if item.status.isActive {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: statusSymbol).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).font(.caption.weight(.semibold)).lineLimit(1)
                Text(item.status.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let destination = item.destinationURL {
                    Text(destination.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(width: detailWidth, alignment: .leading)
            if item.status.isActive {
                Button("Cancel") { center.cancel(item) }.buttonStyle(.plain).font(.caption)
            } else if item.status == .finished {
                Button("Reveal") { center.reveal(item) }.buttonStyle(.plain).font(.caption)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var statusSymbol: String {
        switch item.status {
        case .finished: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "arrow.down.circle"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .finished: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}

