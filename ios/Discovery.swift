import Foundation
import Network
import Combine

/// A GyroWheel receiver found on the local network via Bonjour.
struct DiscoveredMac: Identifiable, Hashable {
    let name: String
    let endpoint: NWEndpoint
    var id: String { name }
}

/// Browses for `_gyrowheel._udp` services advertised by the Mac receivers.
final class Discovery: ObservableObject {
    static let serviceType = "_gyrowheel._udp"

    @Published var macs: [DiscoveredMac] = []
    @Published var browsing = false
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: Discovery.serviceType, domain: nil), using: params)

        b.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready, .setup: self?.browsing = true
                default: self?.browsing = false
                }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found: [DiscoveredMac] = results.compactMap { result in
                if case let .service(name, _, _, _) = result.endpoint {
                    return DiscoveredMac(name: name, endpoint: result.endpoint)
                }
                return nil
            }
            DispatchQueue.main.async {
                self?.macs = found.sorted { $0.name < $1.name }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        macs = []
        browsing = false
    }
}
