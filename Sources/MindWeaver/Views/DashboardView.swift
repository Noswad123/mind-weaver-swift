import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack {
            dashboardBackground

            HStack(alignment: .center, spacing: 28) {
                dashboardCard(title: "Last Viewed Notes", systemImage: "clock.arrow.circlepath") {
                    if appModel.recentlyViewedNotes.isEmpty {
                        emptyText("Viewed notes will appear here.")
                    } else {
                        ForEach(appModel.recentlyViewedNotes) { note in
                            Button {
                                withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                                    appModel.dismissDashboard()
                                }
                                appModel.sidebarMode = .notes
                                appModel.select(note)
                            } label: {
                                dashboardNoteRow(note)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 390)

                centerLoom

                dashboardCard(title: "Highest Priority Tasks", systemImage: "sparkles") {
                    if appModel.highestPriorityTodos.isEmpty {
                        emptyText("Priority tasks will appear here.")
                    } else {
                        ForEach(appModel.highestPriorityTodos) { todo in
                            Button {
                                withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                                    appModel.dismissDashboard()
                                }
                                appModel.sidebarMode = .todos
                                appModel.selectTodo(todo)
                            } label: {
                                dashboardTodoRow(todo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 390)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 34)
        }
    }

    private var dashboardBackground: some View {
        ZStack {
            GeometryReader { geometry in
                if let image = mindWeaverImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    MWTheme.bgVoid
                }
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    MWTheme.bgVoid.opacity(0.50),
                    MWTheme.bgPanel.opacity(0.74),
                    MWTheme.pinkSignal.opacity(0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            MWTheme.appBackground.opacity(0.42)
        }
        .ignoresSafeArea()
    }

    private var mindWeaverImage: NSImage? {
        guard let url = resourceBundle.url(forResource: "mind-weaver", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private var centerLoom: some View {
        VStack(spacing: 0) {
            Image("mind-weaver", bundle: resourceBundle)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.black.opacity(0.42), radius: 22, y: 12)
        }
        .frame(width: 300)
    }

    private func dashboardCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(MWTheme.emberHot)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .mwPanel(cornerRadius: 18)
    }

    private func dashboardNoteRow(_ note: MWNote) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(note.displayPath)
                .font(.caption)
                .foregroundStyle(MWTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .mwPanel(cornerRadius: 10)
    }

    private func dashboardTodoRow(_ todo: MWTodo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(todo.title)
                .fontWeight(.semibold)
                .lineLimit(2)
            HStack(spacing: 8) {
                if !todo.displayPriority.isEmpty {
                    Text(todo.displayPriority)
                        .font(.caption2)
                        .bold()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(MWTheme.ember.opacity(0.22), in: Capsule())
                }
                Text(todo.noteTitle ?? todo.path ?? "Task index")
                    .font(.caption)
                    .foregroundStyle(MWTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .mwPanel(cornerRadius: 10)
    }

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(.callout)
            .foregroundStyle(MWTheme.textMuted)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
    }
}
