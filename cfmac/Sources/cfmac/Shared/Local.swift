import SwiftUI

/// View-owned state. Behaves like `@State`, whose macro implementation ships only with
/// full Xcode; this keeps cfmac buildable with the Command Line Tools alone.
@MainActor
@propertyWrapper
struct Local<Value>: DynamicProperty {
    final class Storage: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var storage: Storage

    init(wrappedValue: Value) {
        _storage = StateObject(wrappedValue: Storage(wrappedValue))
    }

    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    var projectedValue: Binding<Value> {
        let storage = storage
        return Binding(get: { storage.value }, set: { storage.value = $0 })
    }
}
