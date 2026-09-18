import Foundation
import Testing
@testable import RemoteMic

@Suite("Xiaomi bridge foreign product rejection")
struct ForeignVoiceRemoteProductTests {
    @Test func otherProductNamesAreRejected() {
        let names = [
            "Chromecast Remote",
            "chromecast remote",
            "CHROMECAST-REMOTE",
            "chromecast_remote",
            "  Chromecast   Remote  ",
            "chromecast 遥控器",
            "RemoteG10",
            "Remote-G10",
            "G10",
        ]
        for name in names {
            #expect(ForeignVoiceRemoteProduct.isRejected(name: name))
        }
    }

    @Test func missingOrXiaomiNamesAreNotRejected() {
        let names: [String?] = [
            nil,
            "",
            "   ",
            "MI RC",
            "小米蓝牙语音遥控器",
            "ARN9",
            "客厅遥控器",
        ]
        for name in names {
            #expect(!ForeignVoiceRemoteProduct.isRejected(name: name))
        }
    }

    @Test func savedIdentityDoesNotOverrideOtherProductVeto() {
        let identifier = UUID()
        #expect(
            !BluetoothDiscoveryPolicy.accepts(
                identifier: identifier,
                targetIdentifier: identifier,
                advertisesVoiceService: true,
                name: "Chromecast Remote",
                advertisedName: nil
            )
        )
    }

    @Test func otherProductIsRejectedOnEveryDiscoveryPath() {
        let identifier = UUID()
        // 扫描广播名
        #expect(
            !BluetoothDiscoveryPolicy.accepts(
                identifier: identifier,
                targetIdentifier: nil,
                advertisesVoiceService: true,
                name: nil,
                advertisedName: "Chromecast Remote"
            )
        )
        // 系统已连接设备上报的名称
        #expect(
            !BluetoothDiscoveryPolicy.accepts(
                identifier: identifier,
                targetIdentifier: nil,
                advertisesVoiceService: true,
                name: "Chromecast Remote",
                advertisedName: nil
            )
        )
    }

    @Test func xiaomiAdmissionBehaviorIsUnchanged() {
        let other = UUID()
        // 已保存身份 + 名称对不上（用户改过名）仍采纳：身份优先于名称。
        #expect(
            BluetoothDiscoveryPolicy.accepts(
                identifier: other,
                targetIdentifier: other,
                advertisesVoiceService: false,
                name: "客厅遥控器",
                advertisedName: nil
            )
        )
        // 无身份但名称命中小米白名单。
        #expect(
            BluetoothDiscoveryPolicy.accepts(
                identifier: UUID(),
                targetIdentifier: nil,
                advertisesVoiceService: false,
                name: "小米蓝牙语音遥控器",
                advertisedName: nil
            )
        )
        // 无身份、完全没有名字时才退回按服务采纳。
        #expect(
            BluetoothDiscoveryPolicy.accepts(
                identifier: UUID(),
                targetIdentifier: nil,
                advertisesVoiceService: true,
                name: nil,
                advertisedName: nil
            )
        )
        // 未知名称（既非小米也非已知他牌）保持 PR #451 之前的行为：服务在即采纳。
        #expect(
            BluetoothDiscoveryPolicy.accepts(
                identifier: UUID(),
                targetIdentifier: nil,
                advertisesVoiceService: true,
                name: "客厅遥控器",
                advertisedName: nil
            )
        )
    }
}
