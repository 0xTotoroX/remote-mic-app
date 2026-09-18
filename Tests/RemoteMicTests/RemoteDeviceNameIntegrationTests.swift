import Foundation
import Testing
@testable import RemoteMic

@Suite("Remote device name integration")
struct RemoteDeviceNameIntegrationTests {
    @Test func renamedKnownDeviceCanBeRediscoveredWithoutNameOrServiceAdvertisement() {
        let target = UUID()
        #expect(BluetoothDiscoveryPolicy.accepts(
            identifier: target, targetIdentifier: target, advertisesVoiceService: false,
            name: "Office", advertisedName: nil
        ))
        #expect(!BluetoothDiscoveryPolicy.accepts(
            identifier: UUID(), targetIdentifier: target, advertisesVoiceService: true,
            name: "MI RC", advertisedName: "MI RC"
        ))
    }

    @Test func newDeviceStillNeedsVoiceServiceOrApprovedFactoryName() {
        #expect(BluetoothDiscoveryPolicy.accepts(
            identifier: UUID(), targetIdentifier: nil, advertisesVoiceService: true,
            name: "Office", advertisedName: nil
        ))
        #expect(BluetoothDiscoveryPolicy.accepts(
            identifier: UUID(), targetIdentifier: nil, advertisesVoiceService: false,
            name: "Office", advertisedName: "MI RC"
        ))
        #expect(!BluetoothDiscoveryPolicy.accepts(
            identifier: UUID(), targetIdentifier: nil, advertisesVoiceService: false,
            name: "Office", advertisedName: nil
        ))
    }

    @Test func systemNameChangesOnlyTheMatchingProfileAndSurvivesRestart() throws {
        let suite = "RemoteNames.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let first = settings.registerBluetoothRemote(identifier: UUID())
        let second = settings.registerBluetoothRemote(identifier: UUID())
        settings.updateRemoteProfileModel(first, model: .rc001)
        settings.updateRemoteProfileModel(second, model: .rc001)
        let original = settings.remoteDeviceProfiles
        #expect(settings.updateRemoteProfileSystemName(first, name: "Office"))
        #expect(!settings.updateRemoteProfileSystemName(first, name: "Office"))
        #expect(!settings.updateRemoteProfileSystemName(first, name: nil))
        #expect(!settings.updateRemoteProfileSystemName(first, name: " \n"))
        let restored = AppSettings(defaults: defaults)
        #expect(restored.remoteDeviceProfiles.first { $0.id == first }?.customName == "Office")
        #expect(restored.remoteDeviceProfiles.first { $0.id == second }?.customName == "")
        #expect(restored.remoteDeviceProfiles.map(\.id) == original.map(\.id))
        #expect(restored.remoteDeviceProfiles.map(\.bluetoothIdentifier) == original.map(\.bluetoothIdentifier))
        #expect(restored.remoteDeviceProfiles.map(\.mappings) == original.map(\.mappings))
        #expect(settings.updateRemoteProfileSystemName(first, name: "MI RC"))
        #expect(settings.remoteDeviceProfiles.first { $0.id == first }?.customName == "")
        #expect(!settings.updateRemoteProfileSystemName(UUID(), name: "Unknown device"))
    }

    @Test func hidNamesUseAddressesInsteadOfNamesOrEnumerationOrder() {
        let identities = [
            RemoteDeviceNameReader.HIDIdentity(fingerprint: "one", address: "AA:BB:CC:DD:EE:01"),
            RemoteDeviceNameReader.HIDIdentity(fingerprint: "two", address: "aa-bb-cc-dd-ee-02"),
        ]
        let paired = [
            RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:02", name: "Same"),
            RemoteDeviceNameReader.PairedDevice(address: "aa-bb-cc-dd-ee-01", name: "Same"),
        ]
        #expect(RemoteDeviceNameReader.namesByFingerprint(identities: identities, paired: paired).mapValues(\.name)
            == ["one": "Same", "two": "Same"])
        let renamed = [
            RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:01", name: "Renamed"),
            RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:02", name: "Same"),
        ]
        #expect(RemoteDeviceNameReader.namesByFingerprint(identities: identities, paired: renamed).mapValues(\.name)
            == ["one": "Renamed", "two": "Same"])
    }

    @Test func duplicateHIDInterfacesAreAllowedButAmbiguousIdentityIsNot() {
        let one = RemoteDeviceNameReader.HIDIdentity(fingerprint: "one", address: "AA:BB:CC:DD:EE:01")
        let paired = [RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:01", name: "Office")]
        #expect(RemoteDeviceNameReader.namesByFingerprint(identities: [one, one], paired: paired).mapValues(\.name)
            == ["one": "Office"])
        let conflict = RemoteDeviceNameReader.HIDIdentity(fingerprint: "one", address: "AA:BB:CC:DD:EE:02")
        #expect(RemoteDeviceNameReader.namesByFingerprint(identities: [one, conflict], paired: paired).isEmpty)
    }

    @Test func unavailableNamesAndInvalidAddressesNeverProduceGuessedMatches() {
        let identities = [
            RemoteDeviceNameReader.HIDIdentity(fingerprint: "one", address: "invalid"),
            RemoteDeviceNameReader.HIDIdentity(fingerprint: "two", address: nil),
            RemoteDeviceNameReader.HIDIdentity(fingerprint: "three", address: "AA:BB:CC:DD:EE:03"),
        ]
        let paired = [
            RemoteDeviceNameReader.PairedDevice(address: "invalid", name: "No"),
            RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:03", name: nil),
        ]
        #expect(RemoteDeviceNameReader.namesByFingerprint(identities: identities, paired: paired).isEmpty)
    }
    @Test func hidSerialMetadataStaysWithItsDeviceAndRejectsConflictingInterfaces() {
        let first = RemoteDeviceNameReader.HIDIdentity(
            fingerprint: "one", address: "AA:BB:CC:DD:EE:01", serialNumber: "TESTSERIAL001"
        )
        let second = RemoteDeviceNameReader.HIDIdentity(
            fingerprint: "two", address: "AA:BB:CC:DD:EE:02", serialNumber: "TESTSERIAL002"
        )
        let missing = RemoteDeviceNameReader.HIDIdentity(
            fingerprint: "one", address: "AA:BB:CC:DD:EE:01"
        )
        let paired = [
            RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:02", name: "TESTSERIAL001"),
            RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:01", name: "TESTSERIAL001"),
        ]
        let names = RemoteDeviceNameReader.namesByFingerprint(identities: [first, first, missing, second], paired: paired)
        #expect(names["one"]?.serialNumber == "TESTSERIAL001")
        #expect(names["two"]?.serialNumber == "TESTSERIAL002")
        #expect(names["two"]?.name == "TESTSERIAL001")
        let conflict = RemoteDeviceNameReader.HIDIdentity(
            fingerprint: "one", address: "AA:BB:CC:DD:EE:01", serialNumber: "OTHER-SERIAL"
        )
        let ambiguous = RemoteDeviceNameReader.namesByFingerprint(identities: [first, conflict], paired: paired)
        #expect(ambiguous["one"]?.serialNumber == nil)
        #expect(ambiguous["one"]?.name == "TESTSERIAL001")
    }

    @Test func appleSerialObservationClearsOldCacheAndRestoresHistoricalNumbering() throws {
        let suite = "RemoteNames.Serial.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        // Model persisted Apple profiles without enabling or starting the private adapter.
        let first = settings.registerHIDRemote(fingerprint: "one")
        let second = settings.registerHIDRemote(fingerprint: "two")
        settings.updateRemoteProfileModel(first, model: .appleSiriRemoteA2854)
        settings.updateRemoteProfileModel(second, model: .appleSiriRemoteA2854)
        let serial = "TESTSERIAL001"
        #expect(settings.updateRemoteProfileSystemName(first, name: serial))
        #expect(settings.updateRemoteProfileSystemName(second, name: serial))
        let original = settings.remoteDeviceProfiles
        #expect(settings.updateRemoteProfileSystemName(first, name: serial, serialNumber: serial))
        #expect(!settings.updateRemoteProfileSystemName(first, name: serial, serialNumber: serial))
        let reloaded = AppSettings(defaults: defaults)
        let profile = try #require(reloaded.remoteDeviceProfiles.first { $0.id == first })
        #expect(profile.customName == "")
        #expect(RemoteDeviceNamePolicy.displayName(
            for: profile, among: reloaded.remoteDeviceProfiles, defaultName: "Apple Remote Type-C"
        ) == "Apple Remote Type-C 1")
        #expect(reloaded.remoteDeviceProfiles.first { $0.id == second }?.customName == serial)
        #expect(reloaded.remoteDeviceProfiles.map(\.id) == original.map(\.id))
        #expect(reloaded.remoteDeviceProfiles.map(\.hidFingerprint) == original.map(\.hidFingerprint))
        #expect(reloaded.remoteDeviceProfiles.map(\.mappings) == original.map(\.mappings))
        #expect(settings.updateRemoteProfileSystemName(first, name: "Office", serialNumber: serial))
        #expect(!settings.updateRemoteProfileSystemName(first, name: nil, serialNumber: serial))
        #expect(settings.remoteDeviceProfiles.first { $0.id == first }?.customName == "Office")
        #expect(settings.updateRemoteProfileSystemName(first, name: serial, serialNumber: serial))
        #expect(settings.remoteDeviceProfiles.first { $0.id == first }?.customName == "")
    }
}
