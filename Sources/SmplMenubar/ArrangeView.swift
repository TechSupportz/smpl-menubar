import ServiceManagement
import SwiftUI

/// Columns run from most to least visible. Top to bottom in a column is left to right in the bar.
struct ArrangeView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            main
            Footer()
        }
        .frame(minWidth: 920, minHeight: 460)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(model: model)

            if model.accessError {
                AccessBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(Section.allCases) { section in
                    SectionCard(section: section, model: model)
                }
            }
        }
        .padding(20)
        .animation(.smooth(duration: 0.3), value: model.accessError)
    }
}

// MARK: - Header

private struct Header: View {
    let model: Model

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("smpl.menubar")
                    .font(.system(size: 28, weight: .black))
                    .italic()
                    .tracking(-0.5)
                Text("Drag apps between sections, or up and down to reorder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Refresh Menu Bar", systemImage: "arrow.clockwise") { model.resync() }
                .help("Put every app back where Arrange says, in order")
                .disabled(model.accessError)
        }
    }
}

// MARK: - Section card

private struct SectionCard: View {
    let section: Section
    let model: Model
    @State private var isTargeted = false

    var body: some View {
        let apps = model.apps(in: section)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.title3.weight(.semibold))
                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: section.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(apps) { app in
                        ReorderableRow(app: app, section: section, model: model)
                            .transition(.opacity)
                    }
                }
                .animation(.smooth(duration: 0.3), value: apps)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .groupBox(highlighted: isTargeted)
        .dropDestination(for: String.self) { ids, _ in
            withAnimation(.smooth(duration: 0.3)) {
                ids.forEach { model.move($0, to: section) }
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// Dropping onto a row puts the dragged app just above it; a line shows where it lands.
private struct ReorderableRow: View {
    let app: MenuApp
    let section: Section
    let model: Model
    @State private var isTargeted = false

    var body: some View {
        AppRow(app: app)
            .draggable(app.id) {
                AppRow(app: app).frame(width: 200)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
                    .offset(y: -2)
                    .opacity(isTargeted ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            .dropDestination(for: String.self) { ids, _ in
                withAnimation(.smooth(duration: 0.3)) {
                    ids.forEach { model.move($0, to: section, before: app.id) }
                }
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

private struct AppRow: View {
    let app: MenuApp
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            Text(app.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.primary.opacity(isHovered ? 0.06 : 0), in: .rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Banner & footer

private struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("smpl.menubar needs Full Disk Access to hide apps.")
            Spacer(minLength: 12)
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .groupBox()
    }
}

private extension View {
    /// A System Settings–style group: a slightly raised fill with a hairline edge.
    func groupBox(highlighted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return background(highlighted ? Color.accentColor.opacity(0.12) : Color(nsColor: .quaternarySystemFill), in: shape)
            .overlay(shape.strokeBorder(highlighted ? Color.accentColor : Color(nsColor: .separatorColor)))
    }
}

/// A full-width strip under the sections: settings on the left, credits on the right.
private struct Footer: View {
    @State private var launchAtLogin = LoginItem.isOn
    @State private var needsApproval = LoginItem.needsApproval

    var body: some View {
        HStack(spacing: 0) {
            settings
            Spacer(minLength: 16)
            credits
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // A step darker than the window, so it reads as secondary to the sections above.
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var settings: some View {
            SettingCard(symbol: "power", title: "Launch at Login") {
                // Only when macOS needs you to approve it.
                if needsApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                }
            } control: {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin || needsApproval },
                    set: { on in
                        LoginItem.set(on)
                        launchAtLogin = LoginItem.isOn
                        needsApproval = LoginItem.needsApproval
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider().padding(.vertical, 10)

            SettingCard(symbol: "timer", title: "Hide items after", info: AnyView(HideInfo())) {
                EmptyView()
            } control: {
                HideDelayPicker()
            }

    }

    private var credits: some View {
            VStack(alignment: .trailing, spacing: 2) {
                Link("built by nitish", destination: URL(string: "https://github.com/TechSupportz/smpl-menubar")!)
                    .foregroundStyle(.secondary)
                Text(appVersion)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.trailing, 4)
    }
}

/// One setting: icon, title and an optional caption on the left, its control on the right.
private struct SettingCard<Caption: View, Control: View>: View {
    let symbol: String
    let title: String
    var info: AnyView?
    @ViewBuilder let caption: Caption
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                // Baseline-aligned, so the (i) sits level with the title's letters.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title).font(.body.weight(.medium)).fixedSize()
                    info
                }
                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 16)
        // At least this wide so the two settings line up; wider if the title needs it.
        .frame(minWidth: 240)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private var appVersion: String {
    "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
}

/// Choices for how long revealed items stay after the pointer leaves the menu bar.
enum HideDelay {
    static let key = "hideDelay"
    static let `default`: TimeInterval = 2
    static let choices: [TimeInterval] = [1, 2, 3, 5, 10]
}

private struct HideDelayPicker: View {
    @AppStorage(HideDelay.key) private var delay = HideDelay.default

    var body: some View {
        Picker("Hide items after", selection: $delay) {
            ForEach(HideDelay.choices, id: \.self) { Text("\(Int($0)) s").tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        .help("How long revealed apps stay after you leave the menu bar")
    }
}

/// The (i) beside Hide items after: when revealed apps hide.
private struct HideInfo: View {
    @State private var isShown = false

    var body: some View {
        Button { isShown.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("When revealed apps hide")
        .popover(isPresented: $isShown, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("When apps hide").font(.headline)
                rule("menubar.rectangle", "Apps you've revealed stay while your pointer is on the menu bar or one of their menus is open.")
                rule("timer", "Once you leave the bar and close their menus, they hide after this time.")
                rule("circle.fill", "If you clicked the dot to show them, clicking it again hides them straight away.")
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
            // The settings row it's anchored in keeps titles to one line; the popover inherits that.
            .lineLimit(nil)
        }
    }

    private func rule(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
