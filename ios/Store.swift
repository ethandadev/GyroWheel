import StoreKit

@MainActor
final class Store: ObservableObject {
    @Published var isPro = true
    @Published var purchasing = false
    @Published var statusMessage: String? = nil
    
    // Pro is permanently unlocked.
    func purchase() async {}
    func restore() async {}
    func loadProducts() async {}
}
