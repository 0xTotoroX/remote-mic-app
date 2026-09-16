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
        #expect(RemoteDeviceNameReader.namesByFingerprint(identities: identities, paired: paired)
            == ["one": "Same", "two": "Same"])
        let renamed = [
            RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:01", name: "Renamed"),
            RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:02", name: "Same"),
        ]
        #expect(RemoteDeviceNameReader.namesByFingerprint(identities: identities, paired: renamed)
            == ["one": "Renamed", "two": "Same"])
    }

    @Test func duplicateHIDInterfacesAreAllowedButAmbiguousIdentityIsNot() {
        let one = RemoteDeviceNameReader.HIDIdentity(fingerprint: "one", address: "AA:BB:CC:DD:EE:01")
        let paired = [RemoteDeviceNameReader.PairedDevice(address: "AA:BB:CC:DD:EE:01", name: "Office")]
        #expect(RemoteDeviceNameReader.namesByFingerprint(identities: [one, one], paired: paired)
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
}
