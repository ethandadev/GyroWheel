import SwiftUI

struct SettingsView: View {
    @Binding var editing: Bool
    @EnvironmentObject var controller: GameController
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var discovery: Discovery
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Settings") {
                    NavigationLink(destination: ConnectionSettingsView()) {
                        Label("Connection", systemImage: "network")
                    }
                    NavigationLink(destination: SteeringSettingsView()) {
                        Label("Driving & Assists", systemImage: "steeringwheel")
                    }
                    NavigationLink(destination: PedalsSettingsView()) {
                        Label("Pedal Calibration", systemImage: "slider.vertical.3")
                    }
                }
                
                Section("Interface") {
                    NavigationLink(destination: LayoutSettingsView(editing: $editing, dismissRoot: { dismiss() })) {
                        Label("Layout & HUD", systemImage: "rectangle.3.group")
                    }
                    NavigationLink(destination: ButtonsSettingsView()) {
                        Label("Macro Buttons", systemImage: "circle.grid.2x2")
                    }
                    NavigationLink(destination: AppearanceSettingsView()) {
                        Label("Appearance & Haptics", systemImage: "paintpalette")
                    }
                }

                Section("Data & Export") {
                    NavigationLink(destination: ImportExportView()) {
                        Label("Import / Export Layout", systemImage: "square.and.arrow.up.on.square")
                    }
                    Button(role: .destructive) { settings.resetAll() } label: { 
                        Label("Reset everything", systemImage: "trash") 
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Subviews

struct ConnectionSettingsView: View {
    @EnvironmentObject var controller: GameController
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var discovery: Discovery
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Nearby Macs (auto-discovery)") {
                if discovery.macs.isEmpty {
                    HStack { Text("Scanning…").foregroundStyle(.secondary); Spacer(); ProgressView() }
                } else {
                    ForEach(discovery.macs) { mac in
                        Button { controller.connect(to: mac); dismiss() } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text(mac.name).lineLimit(1)
                                Spacer()
                                Image(systemName: controller.target == mac.name && controller.status.isConnected
                                      ? "checkmark.circle.fill" : "arrow.right.circle")
                                    .foregroundStyle(controller.target == mac.name && controller.status.isConnected ? .green : .accentColor)
                            }
                        }
                    }
                }
            }

            Section("Connection (manual)") {
                HStack {
                    Text("Mac IP"); Spacer()
                    TextField("192.168.1.50", text: $settings.host)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Stepper("Port: \(settings.port)", value: $settings.port, in: 1...65535)
                Toggle("Auto-connect on launch", isOn: $settings.autoConnect)
                Picker("Update rate", selection: $settings.sendRateHz) {
                    Text("60 Hz").tag(60); Text("90 Hz").tag(90); Text("120 Hz").tag(120)
                }
            }
        }
        .navigationTitle("Connection")
    }
}

struct SteeringSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var controller: GameController

    var body: some View {
        Form {
            Section {
                Picker("Assist level", selection: $settings.assistLevel) {
                    Text("Off").tag(0); Text("Light").tag(1); Text("Strong").tag(2)
                }
                Toggle("Auto-recenter (anti-drift on straights)", isOn: $settings.recenterAssist)
                slider("Steering smoothing", $settings.smoothing, 0...0.9, "%.2f")
                slider("Steering speed limit", $settings.steerRateLimit, 0...12, "%.1f")
                slider("Throttle ease-off (s)", $settings.throttleEase, 0...0.6, "%.2f")
            } header: { Text("Assists") } footer: {
                Text("Light is recommended. Auto-recenter slowly re-zeros while you hold straight so hand-shake won't drift the car into a wall.")
            }

            Section("Steering") {
                slider("Sensitivity", $settings.sensitivity, 0.3...3.0, "%.2f")
                slider("Deadzone", $settings.deadzoneDegrees, 0...10, "%.1f°")
                slider("Full-lock angle", $settings.maxLockDegrees, 20...120, "%.0f°")
                slider("Response curve", $settings.steerCurve, 1.0...3.0, "%.2f")
                Toggle("Invert steering", isOn: $settings.invertSteering)
                Toggle("Auto-invert when flipped", isOn: $settings.autoInvert)
                Toggle("Calibrate on launch", isOn: $settings.calibrateOnLaunch)
                Button("Calibrate now — set current position as center") { controller.calibrate() }
            }
        }
        .navigationTitle("Driving")
    }
}

struct PedalsSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Swap throttle / brake", isOn: $settings.invertPedals)
                slider("Brake curve", $settings.brakeGamma, 1.0...3.0, "%.2f")
                slider("Throttle curve", $settings.throttleGamma, 1.0...3.0, "%.2f")
            } header: { Text("Pedals") } footer: {
                Text("Higher brake curve = gentle at first, firmer near the end — precision for trail-braking right at the lockup threshold.")
            }
        }
        .navigationTitle("Pedals")
    }
}

struct LayoutSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var editing: Bool
    var dismissRoot: () -> Void

    var body: some View {
        Form {
            Section {
                Button {
                    editing = true
                    dismissRoot()
                } label: {
                    Label("Edit layout on screen (drag to arrange)", systemImage: "hand.draw")
                }
                Toggle("Show steering wheel", isOn: $settings.showWheel)
                slider("Wheel size", $settings.wheelSize, 90...320, "%.0f")
                slider("Pedal width", $settings.sliderWidth, 60...160, "%.0f")
                slider("Pedal height", $settings.sliderHeight, 180...460, "%.0f")
                Button("Reset layout to default") { settings.resetLayout() }
            }
        }
        .navigationTitle("Layout & HUD")
    }
}

struct ButtonsSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Buttons Configuration") {
                Stepper("Count: \(settings.buttonCount)", value: $settings.buttonCount, in: 2...kMaxButtons)
                
                ForEach(Array(0..<settings.buttonCount), id: \.self) { i in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Button \(i + 1)").font(.subheadline).bold()
                            Spacer()
                            TextField("Label", text: settings.labelBinding(i))
                                .multilineTextAlignment(.trailing).frame(maxWidth: 110)
                        }
                        Picker("Color", selection: settings.colorBinding(i)) {
                            ForEach(Array(ButtonPalette.names.enumerated()), id: \.offset) { idx, name in
                                Text(name).tag(idx)
                            }
                        }
                        Picker("Behavior", selection: settings.modeBinding(i)) {
                            ForEach(ButtonMode.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        sliderRaw("Size", settings.sizeBinding(i), 50...150, "%.0f")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Macro Buttons")
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Look") {
                Picker("Background", selection: $settings.backgroundStyle) {
                    Text("Black").tag(0); Text("Gradient").tag(1)
                }
                
                Picker("Button shape", selection: $settings.buttonShape) {
                    Text("Circle").tag(0); Text("Rounded").tag(1)
                }
                colorPicker("Accent / wheel", $settings.accentColorIndex)
                colorPicker("Throttle color", $settings.throttleColorIndex)
                colorPicker("Brake color", $settings.brakeColorIndex)
                slider("Control opacity", $settings.controlOpacity, 0.4...1.0, "%.2f")
                Toggle("Show angle readout", isOn: $settings.showAngleReadout)
            }

            Section("Feedback") {
                Toggle("Button haptics", isOn: $settings.hapticsEnabled)
                Toggle("Haptic on connect", isOn: $settings.hapticOnConnect)
                Toggle("Telemetry haptics (lockup/slip)", isOn: $settings.telemetryHaptics)
            }
        }
        .navigationTitle("Appearance")
    }

    private func colorPicker(_ title: String, _ value: Binding<Int>) -> some View {
        Picker(title, selection: value) {
            ForEach(Array(ButtonPalette.names.enumerated()), id: \.offset) { idx, name in
                Text(name).tag(idx)
            }
        }
    }
}

struct ImportExportView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var jsonString: String = ""
    @State private var showSuccess = false
    @State private var showError = false

    var body: some View {
        Form {
            Section(header: Text("Layout Profile JSON")) {
                TextEditor(text: $jsonString)
                    .frame(height: 150)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            
            Section {
                Button("Generate / Export Layout") {
                    jsonString = settings.exportLayout()
                }
                Button("Copy to Clipboard") {
                    UIPasteboard.general.string = jsonString
                }
                
                Button("Import / Apply Layout") {
                    if settings.importLayout(json: jsonString) {
                        showSuccess = true
                    } else {
                        showError = true
                    }
                }
                .foregroundColor(.green)
                .bold()
            }
        }
        .navigationTitle("Import/Export")
        .alert("Import Successful", isPresented: $showSuccess) {
            Button("OK", role: .cancel) { }
        } message: { Text("The layout settings have been applied.") }
        .alert("Import Failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: { Text("Invalid layout JSON format.") }
    }
}

// MARK: - Helper views
private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ spec: String) -> some View {
    VStack(alignment: .leading) {
        Text("\(title): \(value.wrappedValue, specifier: spec)")
        Slider(value: value, in: range)
    }
}

private func sliderRaw(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ spec: String) -> some View {
    slider(title, value, range, spec)
}
