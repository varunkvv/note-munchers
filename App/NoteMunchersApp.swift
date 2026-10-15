import NoteCore
import SwiftUI

@main
struct NoteMunchersApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 820)
        #endif
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var launched = false

    var body: some View {
        ZStack {
            switch model.screen {
            case .home:
                HomeView(model: model)
            case .practice:
                if let practice = model.practice {
                    PracticeView(controller: practice, input: model.input, onLeave: model.leavePractice)
                }
            case .sessionEnd:
                if let summary = model.lastSummary {
                    SessionEndView(summary: summary, onHome: model.goHome)
                } else {
                    HomeView(model: model)
                }
            }
        }
        #if DEBUG
        .modifier(DemoLandscape(enabled: model.demo.landscape))
        #endif
        .sheet(isPresented: $model.showParent) {
            ParentView(model: model)
                .presentationSizing(.page)
        }
        // light mode on purpose: light-on-dark smears more for astigmatic eyes
        .preferredColorScheme(.light)
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .onAppear {
            guard !launched else { return }
            launched = true
            model.launch()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.sounds.resume() }
        }
    }
}

#if DEBUG
/// See `-demoLandscape` in DemoRunner.
struct DemoLandscape: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            GeometryReader { proxy in
                content
                    .frame(width: proxy.size.height, height: proxy.size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }
}
#endif
