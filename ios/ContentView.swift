import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var controller: GameController
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var discovery: Discovery
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var editing = false
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            background
            surface
            topBar
            if editing { editBar }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            controller.start()
            discovery.start()
            UIApplication.shared.isIdleTimerDisabled = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            showOnboarding = !settings.hasOnboarded
            if settings.autoConnect && !controller.status.isConnected { controller.connect() }
            if settings.calibrateOnLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { controller.calibrate() }
            }
        }
        .onDisappear {
            controller.stop()
            discovery.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:     controller.start()
            case .background: controller.stop()
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            switch UIDevice.current.orientation {
            case .landscapeLeft:  controller.setLandscapeFlipped(false)
            case .landscapeRight: controller.setLandscapeFlipped(true)
            default: break
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(editing: $editing) }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { settings.hasOnboarded = true; showOnboarding = false }
        }
    }

    @ViewBuilder
    private var background: some View {
        if settings.backgroundStyle == 1 {
            LinearGradient(colors: [Color(white: 0.10), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - Play surface (absolutely positioned, draggable in edit mode)
    private var surface: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(0..<settings.buttonCount), id: \.self) { i in
                    place(MacroButton(index: i, editing: editing),
                          settings.posXBinding(i), settings.posYBinding(i), geo.size)
                }
                if settings.showWheel {
                    place(WheelHUD(size: CGFloat(settings.wheelSize)),
                          settings.wheelXBinding, settings.wheelYBinding, geo.size)
                }
                place(ThrottleBrakeSlider(editing: editing)
                        .frame(width: CGFloat(settings.sliderWidth), height: CGFloat(settings.sliderHeight)),
                      settings.sliderXBinding, settings.sliderYBinding, geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: "surface")
        }
    }

    @ViewBuilder
    private func place<V: View>(_ view: V, _ x: Binding<Double>, _ y: Binding<Double>, _ s: CGSize) -> some View {
        view
            .modifier(DraggableInSurface(editing: editing, nx: x, ny: y, container: s))
            .position(x: x.wrappedValue * s.width, y: y.wrappedValue * s.height)
    }

    // MARK: - Fixed top bar
    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                statusPill
                connectButton
                Spacer()
                iconButton(editing ? "checkmark.circle.fill" : "slider.horizontal.3") { editing.toggle() }
                iconButton("gearshape.fill") { showSettings = true }
            }
            if !controller.status.isConnected && !discovery.macs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.caption2).foregroundStyle(.green)
                    ForEach(discovery.macs) { mac in
                        Button { controller.connect(to: mac) } label: {
                            Text(mac.name).font(.caption2).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.green.opacity(0.25)).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle().fill(controller.status.isConnected ? .green : .red).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.status.text).font(.caption).bold().foregroundStyle(.white)
                Text(controller.targetLabel + (controller.status.isConnected ? "  ↑\(controller.txRate)Hz" : ""))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.06)).clipShape(Capsule())
    }

    private var connectButton: some View {
        Button {
            Haptics.tap(settings.hapticOnConnect)
            controller.status.isConnected ? controller.disconnect() : controller.connect()
        } label: {
            Text(controller.status.isConnected ? "Disconnect" : "Connect")
                .font(.caption).bold().padding(.horizontal, 14).padding(.vertical, 8)
                .background(controller.status.isConnected ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                .foregroundStyle(.white).clipShape(Capsule())
        }
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.title3).foregroundStyle(.white)
                .padding(8).background(.white.opacity(0.06)).clipShape(Circle())
        }
    }

    // MARK: - Edit-mode bar
    private var editBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Label("Drag to arrange", systemImage: "hand.draw")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Button("Reset") { settings.resetLayout() }
                    .font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.12)).clipShape(Capsule()).foregroundStyle(.white)
                Button("Done") { editing = false }
                    .font(.caption).bold().padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.green).clipShape(Capsule()).foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.6)).clipShape(Capsule())
            .padding(.bottom, 14)
        }
    }
}

/// Steering-wheel graphic + live angle readout.
struct WheelHUD: View {
    let size: CGFloat
    @EnvironmentObject var controller: GameController
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "steeringwheel")
                .resizable().scaledToFit().frame(width: size, height: size)
                .foregroundStyle(ButtonPalette.color(settings.accentColorIndex))
                .opacity(settings.controlOpacity)
                .rotationEffect(.degrees(controller.steer * settings.maxLockDegrees))
                .animation(.linear(duration: 0.05), value: controller.steer)
            if settings.showAngleReadout {
                Text(String(format: "%.0f°  (%+.2f)", controller.steer * settings.maxLockDegrees, controller.steer))
                    .font(.system(.footnote, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// Adds drag-to-reposition (normalized) only while editing.
struct DraggableInSurface: ViewModifier {
    let editing: Bool
    @Binding var nx: Double
    @Binding var ny: Double
    let container: CGSize
    func body(content: Content) -> some View {
        if editing {
            content.gesture(
                DragGesture(coordinateSpace: .named("surface"))
                    .onChanged { v in
                        guard container.width > 0, container.height > 0 else { return }
                        nx = min(max(Double(v.location.x / container.width), 0.03), 0.97)
                        ny = min(max(Double(v.location.y / container.height), 0.06), 0.94)
                    }
            )
        } else {
            content
        }
    }
}
