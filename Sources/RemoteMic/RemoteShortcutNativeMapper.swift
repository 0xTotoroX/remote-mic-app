import Foundation

/// Candidate integration for one Xiaomi remote. Raw reports remain available to
/// HIDRemoteMonitor; native keys must disappear before the virtual chord arrives.
final class RemoteShortcutNativeMapper {
    static let sources: [RemoteButton: UInt64] = [
        .ok: 0x700000028, .menu: 0x700000065, .tv: 0x700000035,
    ]

    private let services: RemoteVoiceFunctionMapper.ServiceProvider
    private let logger: (String) -> Void
    // An empty array records that a source had no mapping before we owned it.
    private var originals: [UInt64: [UInt64: [HIDUsageMapping]]] = [:]
    private var operationID = 0

    init(
        services: @escaping RemoteVoiceFunctionMapper.ServiceProvider = RemoteVoiceFunctionMapper.systemServices,
        logger: @escaping (String) -> Void = { AppLogger.shared.write($0) }
    ) {
        self.services = services
        self.logger = logger
    }

    @discardableResult
    func apply(buttons: Set<RemoteButton>) -> Bool {
        operationID += 1
        let targets = services()
        let requested = Set(buttons.compactMap { Self.sources[$0] })
        // This local candidate has only been validated with a single Xiaomi.
        // Do not apply a selected profile's mappings to another physical remote.
        let eligible = requested.isEmpty || targets.count == 1
        var success = eligible && (requested.isEmpty || !targets.isEmpty)
        for service in targets {
            success = update(service, sources: eligible ? requested : []) && success
        }
        logger(
            "SHORTCUT NATIVE MAPPING operation_id=\(operationID) phase=completed " +
                "result=\(success ? "applied" : "failed") sources=\(requested.count) " +
                "matched=\(targets.count) receiver=unknown"
        )
        return success
    }

    func restore() {
        guard !originals.isEmpty else { return }
        _ = apply(buttons: [])
    }

    private func update(_ service: RemoteVoiceMappingService, sources: Set<UInt64>) -> Bool {
        guard let id = service.registryID else { return sources.isEmpty }
        let current = service.readMappings()
        let previous = originals[id] ?? [:]
        var owned = previous
        for source in sources where owned[source] == nil {
            owned[source] = current.filter { $0.source == source }
        }
        guard !owned.isEmpty else { return true }
        let changed = Set(owned.keys)
        var desired = current.filter { !changed.contains($0.source) }
        for source in changed.sorted() {
            desired += sources.contains(source)
                ? [HIDUsageMapping(source: source, destination: 0)]
                : owned[source, default: []]
        }
        if write(desired, to: service, checking: changed) {
            let remaining = owned.filter { sources.contains($0.key) }
            originals[id] = remaining.isEmpty ? nil : remaining
            return true
        }
        // Preserve ownership if rollback fails so a later disable/exit retries it.
        let restored = write(current, to: service, checking: changed)
        originals[id] = restored ? previous : owned
        logger(
            "SHORTCUT NATIVE MAPPING operation_id=\(operationID) phase=rollback " +
                "result=\(restored ? "restored" : "failed")"
        )
        return false
    }

    private func write(
        _ desired: [HIDUsageMapping],
        to service: RemoteVoiceMappingService,
        checking sources: Set<UInt64>
    ) -> Bool {
        guard service.setMappings(desired) else { return false }
        let actual = service.readMappings()
        return sources.allSatisfy { source in
            actual.filter { $0.source == source } == desired.filter { $0.source == source }
        }
    }
}
