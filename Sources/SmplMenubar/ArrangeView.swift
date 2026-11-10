import ServiceManagement
import SwiftUI

/// Columns run from most to least visible. Top to bottom in a column is left to right in the bar.
struct ArrangeView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header()

            if model.accessError {
                AccessBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(Section.allCases) { section in
                    SectionCard(section: section, model: model)
                }
            }

            Footer()
        }
        .padding(20)
        .frame(minWidth: 920, minHeight: 460)
        .animation(.smooth(duration: 0.3), value: model.accessError)
    }
}

// MARK: - Header

private struct Header: View {
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

private struct Footer: View {
    @State private var launchAtLogin = LoginItem.isOn
    @State private var needsApproval = LoginItem.needsApproval

    var body: some View {
        HStack {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin || needsApproval },
                set: { on in
                    LoginItem.set(on)
                    launchAtLogin = LoginItem.isOn
                    needsApproval = LoginItem.needsApproval
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            if needsApproval {
                Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer()
            Link("built by nitish", destination: URL(string: "https://github.com/TechSupportz/smpl-menubar")!)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}
