import XCTest
import SwiftUI
import WidgetKit

// MARK: - IMPORTANT: keep in sync with RekindleWidget/RekindleWidget.swift
//
// These view structs are a deliberate MIRROR of `SmallWidgetView` / `MediumWidgetView`
// in the widget extension. A test target cannot `import` an app-extension target, and the
// real medium view is coupled to `MarkDoneIntent` / `PostponeIntent` (which pull in
// SharedModelContainer + the SwiftData models), so the views can't be shared via a single
// source file without dragging the whole extension into the test bundle.
//
// To keep this snapshot meaningful, these mirrors reproduce the real widget's layout and
// state branches exactly. Two intentional substitutions are made because the resources
// don't exist in the test bundle:
//   • the "WidgetLogo" image asset → a same-sized rounded gradient tile (layout-equivalent)
//   • the interactive Buttons(intent:) → visually identical static pills (non-interactive)
// If you change the real widget views, update these to match.

private enum WTheme {
    static let coral = Color(red: 0.98, green: 0.52, blue: 0.52)
    static let warmOrange = Color(red: 0.98, green: 0.65, blue: 0.45)
    static let sageGreen = Color(red: 0.55, green: 0.76, blue: 0.62)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.40)
    static let softTeal = Color(red: 0.40, green: 0.82, blue: 0.80)
    static let dustyBlue = Color(red: 0.52, green: 0.68, blue: 0.88)
    static let appBackground = Color(red: 0.98, green: 0.97, blue: 0.95)

    static let warmGradient = LinearGradient(
        colors: [coral, warmOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func avatarColor(for index: Int) -> Color {
        let colors = [coral, softTeal, dustyBlue, amber, sageGreen, warmOrange]
        return colors[index % colors.count]
    }
}

// Stand-in for the real widget's `Image("WidgetLogo")` (asset lives in the widget target).
// Same frame/clip so the header layout matches the shipping widget.
private struct LogoTile: View {
    var size: CGFloat
    var cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(WTheme.warmGradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            )
    }
}

// Minimal data model for rendering — mirrors `WidgetContact`.
private struct WContact: Identifiable {
    let id: String; let name: String; let initials: String; let status: String
    var isDone: Bool { status == "done" }
    var isPending: Bool { status == "pending" }
    var isPostponed: Bool { status == "postponed" }
    var isResolved: Bool { !isPending }
}

private let sampleContacts: [WContact] = [
    WContact(id: "1", name: "David Taylor", initials: "DT", status: "pending"),
    WContact(id: "2", name: "Hank Zakroff", initials: "HZ", status: "postponed"),
    WContact(id: "3", name: "Nora Lee",     initials: "NL", status: "done"),
]

// MARK: - Small Widget View (mirror of SmallWidgetView)

private struct SmallView: View {
    let contacts: [WContact]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Rekindle!")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(.primary)
                Spacer()
                LogoTile(size: 28, cornerRadius: 6)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(contacts.prefix(2).enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 8) {
                        Text(c.initials)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                c.isDone ? WTheme.sageGreen
                                    : c.isPostponed ? WTheme.amber
                                    : WTheme.avatarColor(for: i)
                            )
                            .clipShape(Circle())
                        Text(c.name)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(c.isResolved ? .secondary : .primary)
                            .strikethrough(c.isResolved)
                            .lineLimit(1)
                    }
                }
                if contacts.count > 2 {
                    Text("+\(contacts.count - 2) more")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            let done = contacts.filter(\.isDone).count
            HStack {
                Spacer()
                Text("\(done)/\(contacts.count) done")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(done == contacts.count ? WTheme.sageGreen : WTheme.coral)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((done == contacts.count ? WTheme.sageGreen : WTheme.coral).opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(WTheme.appBackground)
    }
}

// MARK: - Medium Widget View (mirror of MediumWidgetView)

private struct MediumView: View {
    let contacts: [WContact]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Rekindle!")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(.primary)
                Spacer()
                let done = contacts.filter(\.isDone).count
                Text("\(done)/\(contacts.count) done")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(done == contacts.count ? WTheme.sageGreen : WTheme.coral)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((done == contacts.count ? WTheme.sageGreen : WTheme.coral).opacity(0.15))
                    .clipShape(Capsule())
                LogoTile(size: 30, cornerRadius: 7)
            }
            VStack(spacing: 4) {
                ForEach(Array(contacts.prefix(3).enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 8) {
                        Text(c.initials)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(
                                c.isDone ? WTheme.sageGreen
                                    : c.isPostponed ? WTheme.amber
                                    : WTheme.avatarColor(for: i)
                            )
                            .clipShape(Circle())
                        Text(c.name)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(c.isResolved ? .secondary : .primary)
                            .strikethrough(c.isResolved)
                            .lineLimit(1)
                        Spacer()
                        if c.isDone {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("Done")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(WTheme.sageGreen)
                        } else if c.isPostponed {
                            HStack(spacing: 2) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 10))
                                Text("Postponed")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(WTheme.amber)
                        } else if c.isPending {
                            // Mirror of the real Button(intent:) pills (static here).
                            HStack(spacing: 6) {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Done")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(WTheme.sageGreen).clipShape(Capsule())

                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(WTheme.amber).clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if contacts.count > 3 {
                    Text("+\(contacts.count - 3) more")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(WTheme.appBackground)
    }
}

// MARK: - Test

@MainActor
final class WidgetSnapshotTests: XCTestCase {

    func capture(view: some View, size: CGSize, name: String) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 3.0
        guard let uiImage = renderer.uiImage else {
            XCTFail("Failed to render \(name)")
            return
        }
        let att = XCTAttachment(image: uiImage)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func testSmallWidget2x2() {
        // iOS small widget = 158×158 pt on most iPhones
        capture(
            view: SmallView(contacts: sampleContacts),
            size: CGSize(width: 158, height: 158),
            name: "widget_small_2x2"
        )
    }

    func testMediumWidget4x2() {
        // iOS medium widget = 338×158 pt on most iPhones
        capture(
            view: MediumView(contacts: sampleContacts),
            size: CGSize(width: 338, height: 158),
            name: "widget_medium_4x2"
        )
    }
}
