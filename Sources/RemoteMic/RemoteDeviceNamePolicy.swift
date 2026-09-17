import Foundation

enum RemoteDeviceNamePolicy {
    /// nil 表示本次没有读到有效名称；空字符串表示出厂名称，调用方应清除旧缓存。
    static func customName(
        from rawName: String?,
        model: XiaomiRemoteModel,
        serialNumber: String? = nil
    ) -> String? {
        guard let rawName else { return nil }
        let name = normalizedName(rawName)
        guard !name.isEmpty else { return nil }
        // A2854 can expose its serial as its initial Bluetooth name. Compare this device's
        // actual metadata exactly; never infer a serial from the name's shape or prefix.
        if model == .appleSiriRemoteA2854 || model == .appleSiriRemoteA2540,
           let serialNumber, !serialNumber.isEmpty, rawName == serialNumber {
            return ""
        }
        return isFactoryName(name, model: model) ? "" : name
    }

    static func displayName(
        for profile: RemoteDeviceProfile,
        among profiles: [RemoteDeviceProfile],
        defaultName: String
    ) -> String {
        let customName = normalizedName(profile.customName)
        let base: String
        let peers: [RemoteDeviceProfile]
        if customName.isEmpty {
            base = defaultName
            // 保留原型号编号：已改名的历史档案仍占据其保存顺序中的位置。
            peers = profiles.filter { $0.model == profile.model }
        } else {
            base = customName
            // 同名分组跨型号且包含离线档案；Swift 字符串比较区分大小写。
            peers = profiles.filter { normalizedName($0.customName) == customName }
        }
        guard peers.count > 1,
              let index = peers.firstIndex(where: { $0.id == profile.id })
        else { return base }
        return "\(base) \(index + 1)"
    }

    private static func normalizedName(_ name: String) -> String {
        name.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: "\t")))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    private static func isFactoryName(_ name: String, model: XiaomiRemoteModel) -> Bool {
        let lowercased = name.lowercased()
        switch model {
        case .rc001, .rc003:
            return XiaomiVoiceRemoteNameMatcher.matches(name) || [
                "小米蓝牙遥控器 2",
                "小米蓝牙遥控器 2 pro",
            ].contains(lowercased)
        case .appleSiriRemoteA2854, .appleSiriRemoteA2540:
            let commonNames = ["siri remote", "apple tv remote", "apple remote"]
            let modelNames = model == .appleSiriRemoteA2854
                ? ["苹果遥控器 type-c", "apple remote type-c"]
                : ["苹果遥控器 lightning", "apple remote lightning"]
            return commonNames.contains(lowercased) || modelNames.contains(lowercased)
        case .chromecaseVoiceRemote:
            return ["chromecase 遥控器", "chromecase remote"].contains(lowercased)
        case .unknown:
            // 小米发现阶段可能先读到名称、后读到型号；沿用已有发现白名单。
            return XiaomiVoiceRemoteNameMatcher.matches(name)
        }
    }
}
