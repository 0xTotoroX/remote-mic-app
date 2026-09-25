import Testing
@testable import RemoteMic

@Suite("Native shortcut key neutralization")
struct RemoteShortcutNativeMapperTests {
    @Test func restoringOneButtonAndExitingPreserveOtherMappings() {
        let oldOK = HIDUsageMapping(source: 0x700000028, destination: 42)
        let unrelated = HIDUsageMapping(source: 4, destination: 5)
        let box = ShortcutMappingBox(mappings: [oldOK, unrelated])
        let mapper = RemoteShortcutNativeMapper(services: { [box.service] }, logger: { _ in })

        #expect(mapper.apply(buttons: [.ok, .menu, .tv]))
        for source in RemoteShortcutNativeMapper.sources.values {
            #expect(box.mappings.contains(HIDUsageMapping(source: source, destination: 0)))
        }
        // Idempotent reapplication must not replace the original with usage zero.
        #expect(mapper.apply(buttons: [.ok, .menu, .tv]))
        #expect(mapper.apply(buttons: [.menu]))
        #expect(box.mappings.contains(oldOK))
        #expect(!box.mappings.contains { $0.source == 0x700000035 })

        let updated = HIDUsageMapping(source: 4, destination: 6)
        box.mappings.removeAll { $0.source == 4 }
        box.mappings.append(updated)
        mapper.restore()
        #expect(Set(box.mappings.map(\.source)) == Set([oldOK.source, updated.source]))
        #expect(box.mappings.contains(oldOK))
        #expect(box.mappings.contains(updated))
    }

    @Test func ignoredWriteFailsReadbackAndDoesNotClaimSuccess() {
        let box = ShortcutMappingBox(mappings: [])
        box.ignoreWrites = true
        var log: [String] = []
        let mapper = RemoteShortcutNativeMapper(services: { [box.service] }, logger: { log.append($0) })
        #expect(!mapper.apply(buttons: [.ok]))
        #expect(box.mappings.isEmpty)
        #expect(log.contains { $0.contains("phase=rollback result=restored") })
        box.ignoreWrites = false
        #expect(mapper.apply(buttons: [.ok]))
        mapper.restore()
        #expect(box.mappings.isEmpty)
    }

    @Test func failedRestoreRetainsOwnershipForRetry() {
        let original = HIDUsageMapping(source: 0x700000028, destination: 30)
        let box = ShortcutMappingBox(mappings: [original])
        let mapper = RemoteShortcutNativeMapper(services: { [box.service] }, logger: { _ in })
        #expect(mapper.apply(buttons: [.ok]))
        box.acceptsWrites = false
        #expect(!mapper.apply(buttons: []))
        box.acceptsWrites = true
        mapper.restore()
        #expect(box.mappings == [original])
    }

    @Test func multipleRemotesRestoreOwnedKeysWithoutApplyingAnotherProfile() {
        let first = ShortcutMappingBox(mappings: [])
        let second = ShortcutMappingBox(mappings: [], id: 2)
        var services = [first.service]
        let mapper = RemoteShortcutNativeMapper(services: { services }, logger: { _ in })
        #expect(mapper.apply(buttons: [.ok]))
        services.append(second.service)
        #expect(!mapper.apply(buttons: [.ok]))
        #expect(first.mappings.isEmpty)
        #expect(second.mappings.isEmpty)
        services = []
        #expect(!mapper.apply(buttons: [.ok]))
        services = [second.service]
        #expect(mapper.apply(buttons: [.ok]))
        mapper.restore()
        #expect(second.mappings.isEmpty)
    }
}

private final class ShortcutMappingBox {
    var mappings: [HIDUsageMapping]
    let id: UInt64
    var acceptsWrites = true
    var ignoreWrites = false

    init(mappings: [HIDUsageMapping], id: UInt64 = 1) {
        self.mappings = mappings
        self.id = id
    }

    lazy var service = RemoteVoiceMappingService(
        registryID: id,
        readMappings: { [unowned self] in mappings },
        setMappings: { [unowned self] desired in
            guard acceptsWrites else { return false }
            if !ignoreWrites { mappings = desired }
            return true
        }
    )
}
