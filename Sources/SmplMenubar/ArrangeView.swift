import SwiftUI

struct ArrangeView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.accessError {
                HStack {
                    Label("smpl menubar needs Full Disk Access to change which apps are allowed in the menu bar.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(Section.allCases) { section in
                    Column(section: section, model: model)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 380)
    }
}

private struct Column: View {
    let section: Section
    let model: Model
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.headline)
                Text(section.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.apps(in: section)) { app in
                        Row(app: app).draggable(app.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(6)
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .dropDestination(for: String.self) { ids, _ in
                ids.forEach { model.move($0, to: section) }
                return true
            } isTargeted: { isTargeted = $0 }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Row: View {
    let app: MenuApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
            Text(app.name).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .contentShape(Rectangle())
    }
}
