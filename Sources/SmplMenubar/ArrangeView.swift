import ServiceManagement
import SwiftUI

/// Columns run in the menu bar's own order: Always Hidden, Hidden, then the dot, then Visible.
struct ArrangeView: View {
    let model: Model

    private let order: [Section] = [.alwaysHidden, .hidden, .visible]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Header()

            if model.accessError {
                AccessBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            GlassEffectContainer(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(order) { section in
                        SectionCard(section: section, model: model)
                    }
                }
            }

            if !model.switchedOffElsewhere.isEmpty {
                SwitchedOffStrip(apps: model.switchedOffElsewhere)
                    .transition(.opacity)
            }

            Footer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 20)
        .frame(minWidth: 760, minHeight: 460)
        .animation(.smooth(duration: 0.3), value: model.accessError)
        .animation(.smooth(duration: 0.3), value: model.switchedOffElsewhere)
    }
}

// MARK: - Header

private struct Header: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("smpl.menubar")
                .font(.system(size: 28, weight: .black))
                .italic()
                .tracking(-0.5)
            Text("Drag apps between sections. The dot sits between Hidden and Visible.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: section.symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.headline)
                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(apps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(apps) { app in
                        AppRow(app: app)
                            .draggable(app.id) {
                                AppRow(app: app).frame(width: 200)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .animation(.smooth(duration: 0.3), value: apps)
            }
            .scrollIndicators(.never)
            .overlay {
                if apps.isEmpty {
                    Text("Drop apps here")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(isTargeted ? .regular.tint(.accentColor.opacity(0.18)).interactive() : .regular,
                     in: .rect(cornerRadius: 24))
        .scaleEffect(isTargeted ? 1.01 : 1)
        .animation(.smooth(duration: 0.2), value: isTargeted)
        .dropDestination(for: String.self) { ids, _ in
            withAnimation(.smooth(duration: 0.3)) {
                ids.forEach { model.move($0, to: section) }
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
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Banner & footer

private struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access needed").font(.headline)
                Text("smpl.menubar uses the same switch as System Settings → Menu Bar, which lives in a protected file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 20))
    }
}

/// Apps switched off in System Settings. smpl.menubar leaves them alone; drag one into a section to hand it over.
private struct SwitchedOffStrip: View {
    let apps: [MenuApp]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Off in System Settings").font(.subheadline.weight(.semibold))
                Text("Drag into a section to manage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(apps) { app in
                        Image(nsImage: app.icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 26, height: 26)
                            .opacity(0.6)
                            .help(app.name)
                            .draggable(app.id) {
                                AppRow(app: app).frame(width: 200)
                            }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: 18))
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
            Text("Hover the menu bar to peek · click the dot for everything")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }
}
