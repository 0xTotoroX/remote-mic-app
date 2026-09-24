# Onboarding 卡在「等待控制按键」：macOS 安全输入（Secure Input）候选根因核查

- 时间：2026-09-24
- 状态：**只读诊断，未修改任何源码、测试、配置或文档（本文档除外）**；候选根因成立，但链条中间两环尚未在小米遥控器上实测
- 影响范围：macOS Onboarding「遥控器」步骤的普通按键门禁；日常使用时菜单栏与设置里的按键状态显示
- 文档性质：本文档属于 `Bugs/` 下的诊断证据，**不是现行产品规范**，不得据此改变产品行为
- 核查结论摘要：安全输入是 macOS 上真实存在、且能造成本现象的机制；本仓库确实完全没有相关处理。第三方给出的方案方向正确、大多可用，但有 4 处需要修正，其中「语音键仍然可用」一条照抄进用户提示会直接误导用户。

## 一、反馈经过（原始内容）

反馈来自微信用户群，反馈人昵称按公开仓库的隐私边界省略。时间线：

| 时间 | 内容 |
| --- | --- |
| 15:25 | 反馈：Mac 适配时卡在控制键，问是否有人遇到过 |
| 15:31 | 附截图：Onboarding「遥控器」页面显示「小米遥控器 已连接」绿色通过，但「等待控制按键」一直转，下方橙卡是「还没有收到控制按键」 |
| 15:34 | 补充：重启了很多遍也不行，电脑整机重启过好几次 |
| 17:06 | 反馈：由 Claude Code 协助解决，原因是**启用了安全输入** |
| 17:06 | 追问：是哪里的安全输入 |
| 17:09 | 给出排查与处理办法：`ioreg -l -w 0 \| grep SecureInput` 读取占用进程 PID，`kill -9 <pid>` 强制结束该进程（代价是当前所有窗口都会关闭，需先保存数据），然后重新登录 Mac |
| 17:11 | 给出完整的产品侧改进建议（整理见第三节） |
| 17:12 | 本仓库作者反馈：之前就有用户卡在这一步，很可能也是这个原因，一直没有排查出来 |

## 二、第三方给出的完整改进建议（原文要点）

1. **检测**：用 `IsSecureEventInputEnabled()`（Carbon，公开 API）判断是否有进程开着安全输入；从 IORegistry 的 `IOConsoleUsers` 读 `kCGSSessionSecureInputPID` 拿到占用进程 PID，再用 `NSRunningApplication(processIdentifier:)` 取显示名。系统没有变化通知，只能轮询，建议只在 HID 已连接时每 1~2 秒检查一次，只在状态变化时记日志。
2. **首次引导**：遥控器已连接、还没收到普通按键、同时安全输入开着时，把等待卡片换成明确提示；占用者是普通 App 时提示关掉它或关掉「安全键盘输入」。释放后自动恢复，不需要用户点重试。
3. **诊断与日志**：新增失败原因 `remote.secure_input_active`，优先级排在 `remote.button_not_ready` 之前；诊断信息新增 `secure_input_active=true` 和 `secure_input_owner=loginwindow`，`diagnostic_schema` 版本号加 1；运行日志新增 `HID SECURE_INPUT active owner=...` 与 `HID SECURE_INPUT released`。
4. **日常使用**：按键状态显示「按键功能暂停：安全输入开启中（登录窗口）」而不是「已连接」；并说明语音键仍然可用（走 BLE ATVV 通道，不受影响）。
5. **不建议做的**：绕过安全输入（独占设备会返回 `kIOReturnNotPrivileged`）；自动结束 `loginwindow`（等于强制注销用户）。
6. **遗留待验证**：退出登录后安全输入是否释放、遥控器按键是否恢复可识别。

## 三、核查结果：属实的部分

- 本仓库确实**完全没有**安全输入相关处理：全仓搜索 `SecureInput` / `SecureEventInput` / `secure_input` 在 `Sources/`、`Tests/`、`Testing/`、`Resources/` 与根文档中均为**零命中**。
- `remote.button_not_ready` 确实存在（`Sources/RemoteMic/FirstUseDiagnostics.swift:132`），是截图里橙卡「还没有收到控制按键」的原因；`remote` 步骤的判定链是 `remoteConnected` → `remoteButtonObserved`（同文件 `:388`）。
- `diagnostic_schema=3`（同文件 `:479`）属实，`redactedText` 的字段清单里确实没有任何安全输入字段。
- 截图与代码逐条对得上：绿勾 = 蓝牙连接状态卡；蓝圈 = `onboarding.remote.button_waiting`「等待控制按键」（`Sources/RemoteMic/OnboardingView.swift:1030-1046`，标题在 `:1040`）；橙卡 = `onboarding.recovery.remote.button_not_ready.*`。
- 现象与外部案例高度同构，可确认为真实机制：
  - Apple TN2150：只要任意进程启用安全输入，系统就停止向「键盘拦截进程」传递键盘事件；三类拦截方式**包含独占（seize）打开 HID 设备和 CGEventTap**。
  - 罗技官方支持文档：macOS 启用 Secure Input 时 Logi Options+ 会出现设备识别异常，并给出同样的 `ioreg ... grep SecureInput` 排查步骤。
  - Cursr issue #135：鼠标正常、键盘不工作、权限全部正常、界面零报错，根因是 Secure Input。
  - openradar 48953777：`kCGSSessionSecureInputPID` 的准确性问题（见第六节第 3 条）。

## 四、代码事实：本仓库的按键链路

这几条是整个核查的支点：

1. **按键检测不经过 CGEventTap。** 检测走 `HIDRemoteMonitor` 的 `IOHIDManager` InputReport 回调（`hidInputReport`）；`KeyboardEventSuppressor`（`Sources/RemoteMic/KeyboardEventSuppressor.swift:48`）只负责**抑制**系统原生事件，不负责检测按键。
2. **优先独占，失败降级。** `activateDevice` 先 `IOHIDDeviceOpen(device, kIOHIDOptionsTypeSeizeDevice)`（`Sources/RemoteMic/HIDRemoteMonitor.swift:382-385`），失败后降级为 `kIOHIDOptionsTypeNone` 观察模式（`:395`）。
3. **界面无法区分独占成功与降级成功。** `button_mapping.status.connected`（独占成功）与 `connected_fallback`（降级成功且抑制器在运行）的中文都是「按键功能已连接」（`Resources/zh-Hans.lproj/Localizable.strings:47`、`:52`）。因此**只看截图不能判定落在哪条分支，必须读日志**。
4. **现有专属提示覆盖不到本场景。** `deviceOpenFailureMessageKey` 只在 `result == kIOReturnExclusiveAccess` 时返回非 nil（`Sources/RemoteMic/HIDRemoteMonitor.swift:873-881`），对应文案「遥控器被其他输入工具占用…Karabiner-Elements」。若安全输入让独占打开返回的是 `kIOReturnNotPrivileged`，就**命中不了**这条，只会退回泛化的 `remote.button_not_ready`——这正好解释了用户为什么看不到任何有用提示。
5. **语音键检测依赖全局事件监视器。** 小米遥控器语音键是「遥控器 F5 → `RemoteVoiceFunctionMapper` 重映射成 Fn → 宿主用全局事件监视器收 `flagsChanged`」（`Sources/RemoteMic/PreferredInputSourceMonitor.swift:65`）。全局事件监视器底层就是事件 tap，**属于安全输入要挡的那一类**。

由此得到候选链条：**安全输入被某进程持有 → 独占打开遥控器被拒 → 降级为非独占打开（界面仍显示「按键功能已连接」）→ 收不到 HID 报告 → 永远等不到按键**。

## 五、本机只读验证

- `IsSecureEventInputEnabled()` 编译并调用成功（本机返回 `false`）；本仓库已有文件 `import Carbon`（`Sources/RemoteMic/OnboardingInputSourceSwitcher.swift:2`），因此**引入该 API 不需要新增框架依赖**。
- **没有占用时，IORegistry 里连 `kCGSSessionSecureInputPID` 这个字段都不存在**（本机实测确认）。因此后续读取逻辑必须按「字段不存在 = 没有占用」处理，不能记为 `unknown`，否则会把正常用户也报成未知状态。

## 六、第三方方案中需要修正的部分

1. **「被挡住期间语音键仍然可用」不成立。** 按第四节第 5 条，语音键的**按下检测**依赖全局事件监视器，正是安全输入要挡的对象；只有 BLE ATVV 音频通道不受影响。宿主连「用户按下了」都感知不到，因此语音键整体不可用。照抄进提示会让用户以为「至少还能用语音」，反而增加困惑。可作为线索保留的是「音频通道本身不受影响」这一事实，但不能推出「语音键可用」。
2. **`diagnostic_schema` 不需要 +1。** `LOGGING.md` 明确写「仅增加可选字段可以保持版本不变；字段删除、重命名或语义变化时必须递增」。纯新增字段就升版本不符合本仓库规范。
3. **`kCGSSessionSecureInputPID` 可能指错人。** openradar 48953777 记录：后台 App 启用安全输入时，该字段记的是**当时的前台 App**。因此「占用者 = 登录窗口」只能作为线索，不能当作事实写进给用户的提示，否则用户会去退出一个无辜的 App。
4. **不应建议用户 `kill -9`。** 反馈中那条做法会关掉所有窗口、等同强制注销，不该进入产品文案。推荐的引导顺序是：退出对应 App（Cmd+Q，不是关窗口）→ 终端关闭「安全键盘输入」→ 锁屏后用**密码**（而非 Touch ID）重新解锁 → 最后才是注销重登。
5. **「还没按键」与「被安全输入挡住」必须分开。** 若把 `remote.secure_input_active` 无条件排在 `remote.button_not_ready` 之前，只是尚未按键的正常用户也会看到安全输入警告。应当只在「已连接、已等待足够时长或用户已尝试重新检测」时展示，或者作为附加说明而非替换原因。
6. **不要写成已确认根因。** 按 `LOGGING.md`，无法由公开接口确认的因果关系必须落在 `observed_failure` / `probable_cause` 框架里并给出 `probable_cause_confirmed=false`；安全输入是否已挡住本次按键，宿主侧只能观测到「安全输入处于开启状态」这一事实。

## 七、尚未验证的部分与所需证据

以下内容**没有证据支撑**，不作为结论：

- 「独占被拒」与「降级后收不到报告」这两环**都未在小米遥控器上实测**。仓库里「观察模式（非独占打开）下 HID 报告回调一次都不触发」这条结论来自**一台假冒的 Chromecast 遥控器**（`Testing/ChromecastVoicePitfalls.md:63-79`），不可直接外推到小米链路；正常状态下小米遥控器的独占是成功的。
- 需要混淆项：若安全输入同时影响了 `RemoteVoiceFunctionMapper` 写入 `UserKeyMapping`，则 `powerKeySuppressed` 为 false，会导致 `HIDPermissionGate.canMonitor` 失败（`Sources/RemoteMic/RemoteButtons.swift:756-764`）、HID 根本不启动，日志是 `HID START rejected power_suppressed=false`，界面不会显示「按键功能已连接」。这与截图表现不符，但不能排除共存。

定论所需的现场证据：

| 来源 | 要看的内容 |
| --- | --- |
| 运行日志 | `HID PERMISSIONS`、`HID START`、`HID CONNECTED mode=`（`seized` / `probed` / `manager_report`）、是否出现 `reason=exclusive_access`、`HID REPORT` 的条数与 `reason=discovery_no_known_button` |
| 卡住那一刻 | `ioreg -l -w 0 \| grep SecureInput`（有输出即为被占用，PID 仅作线索） |
| 复制的诊断 | `failure=` 与 `button_status=` 两行 |

另外**不得反推历史**：本仓库从未记录过该原因，此前曾卡在同一处的用户是否也是这个问题，目前没有任何证据。

## 八、若后续实施的范围（本次未做）

本项属于 Onboarding 产品行为变更，按规范需同步 `feature/first-run-onboarding/PRODUCT_SPEC.md` 与 macOS 平台附件、`Testing/FirstRunOnboarding.md`，并重跑完整 UI 截图基线（实体 18 / iPhone 20 / 网页 20，共 58 张）；界面文案还需满足「中文不小于 12pt」「不新增长下拉列表」等约束。排障内容建议补进 `TROUBLESHOOTING.md` 已有的「普通按键没有反应」一节，而不是新开一节。
