import SwiftUI

/// First-launch welcome + connection setup. Shown until the user taps Start.
struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var discovery: Discovery
    @EnvironmentObject var controller: GameController
    let onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.10), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            TabView(selection: $page) {
                welcome.tag(0)
                macStep.tag(1)
                connectStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    private var welcome: some View {
        page(icon: "steeringwheel",
             title: "GyroWheel",
             body: "Turn your phone into a gyroscope steering wheel with throttle, brake, and macro buttons. Tilt to steer; everything streams to your Mac.",
             cta: "Next") { page = 1 }
    }

    private var macStep: some View {
        page(icon: "desktopcomputer",
             title: "Start the Mac receiver",
             body: "On your Mac, run the GyroWheel receiver. It prints (or shows) the Mac's IP address. Keep the phone and Mac on the same Wi-Fi.",
             cta: "Next") { page = 2 }
    }

    private var connectStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi").font(.system(size: 40)).foregroundStyle(.green)
            Text("Find your Mac").font(.title2).bold().foregroundStyle(.white)
            Text("Run the GyroWheel receiver on your Mac (same Wi-Fi). It appears here automatically.")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).padding(.horizontal, 36)

            if discovery.macs.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Searching…").foregroundStyle(.white.opacity(0.7))
                }.padding(.vertical, 6)
            } else {
                ForEach(discovery.macs) { mac in
                    Button { controller.connect(to: mac); onFinish() } label: {
                        HStack {
                            Image(systemName: "desktopcomputer")
                            Text(mac.name).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .padding().background(Color.green.opacity(0.25)).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.2))

            HStack {
                Text("Or enter IP").foregroundStyle(.white.opacity(0.8)).font(.subheadline)
                Spacer()
                TextField("192.168.1.50", text: $settings.host)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .foregroundStyle(.white).frame(width: 170)
            }
            Stepper("Port: \(settings.port)", value: $settings.port, in: 1...65535).foregroundStyle(.white)

            Button(action: onFinish) {
                Text("Start driving")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color.green).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: 460)
        .padding(24)
    }

    private func page(icon: String, title: String, body: String,
                      cta: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(.white)
            Text(title).font(.largeTitle).bold().foregroundStyle(.white)
            Text(body).font(.body).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center).padding(.horizontal, 48)
            Button(action: action) {
                Text(cta).font(.headline).padding(.horizontal, 40).padding(.vertical, 12)
                    .background(Color.white.opacity(0.15)).foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(28)
    }
}
