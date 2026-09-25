# Typeless 实验桥源码存档

`bridge.cpp` 保存候选构建 228.2 正在使用的本地桥源码；原文件位于临时目录。本目录用于恢复实验环境，不是正式安装器，不会被 App 构建自动编译或启动。

依赖：[pqrs Karabiner-DriverKit-VirtualHIDDevice v8.5.0](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/v8.5.0) 的公开源码（包含 `vendor/vendor/include`）以及同版已启用的官方驱动和 daemon。使用 Xcode C++ 编译器：

```sh
# 在仓库根目录执行；将路径替换为解压后的官方源码目录。
vhid_source=/path/to/Karabiner-DriverKit-VirtualHIDDevice-8.5.0
mkdir -p dist
xcrun clang++ -std=c++23 -O2 -pthread \
  -I "$vhid_source/include" -I "$vhid_source/vendor/vendor/include" \
  scripts/typeless-vhid/bridge.cpp -o dist/sayall-vhid-bridge
```

桥需要管理员权限，与官方 daemon 配合运行。唯一参数为允许连接的非 root 用户 UID；使用 `/var/run/sayall-vhid-bridge.sock`，权限 `0600`，并检查连接方 UID。只接受 `v`、`t`、`q`，发送固定的左 Control + 左 Option + V/T/Q。回执只表示提交虚拟键盘报告，不代表 Typeless 已执行。

这是原样保存的临时样机：缺少正式服务生命周期、客户端读超时和完整异常退出处理，不应作为长期 root 服务发布。恢复时需单独核对官方驱动、daemon、管理员授权及 App 权限；源码备份不能恢复系统授权。

App 侧桥接和原生按键中和仅在 Bundle ID `com.hd838a.RemoteMic.TypelessTest` 启用。正常构建的正式标识不会启用该路径。制作独立测试包时，将 `dist/SayAll.app` 复制为 `dist/SayAllTypelessTest.app`，修改副本标识和显示名称，并重新 ad-hoc 签名；已保存的 228.2 App 包是本次测试的精确二进制，重新构建结果不保证字节相同。

配置与验收边界见 [测试记录](../../Testing/TypelessVirtualHIDShortcuts.md)。完整三模式、文字上屏和稳定性尚未验收；此提交是可恢复的实验检查点，不是发布版本。

## 跟随分支保存设置

[`settings.json`](settings.json) 是测试版通过「设置 → 个性化配置 → 导出配置」生成的当前选中遥控器配置快照，使用 App 原生格式。保存按键映射、自定义快捷键、双击/长按、连续快速按、语音键、增益和通用偏好。设备唯一标识已清空；统计、诊断和系统授权不在此原生导出格式中。此快照不会追踪全部设备档案。

恢复时启动测试版、选中目标遥控器，通过「导入配置」选择 `settings.json`，然后重新选择本机音频设备。导入会替换当前个性化配置，若已有配置需保留，先导出一份。Typeless 的三组快捷键仍需在 Typeless 中配置，macOS 权限仍需独立授权。

后续修改功能或测试配置时，同步执行以下步骤，将配置与对应源码保存在同一分支：

1. 在测试版中选中正在使用的遥控器，通过「导出配置」保存到仓库外的临时 JSON。
2. 在仓库根目录运行 `python3 scripts/typeless-vhid/save-settings.py /path/to/export.json`。脚本清空音频设备标识并稳定排序，便于 Git 比较；新增字段或自定义应用路径需先审查。
3. 检查 `git diff -- scripts/typeless-vhid/settings.json`，确认变化与本次设置一致，再提交并推送到个人 Fork 的实验分支。

Git 保存的是每次导出、提交并推送的快照，不会自动监视 App 中的每次点击。脚本不会读取其他 App 设置，也不会直接修改运行中的无线麦或自动提交。个人设备信息与完整原始 plist 继续仅在本地备份中保留。

## Global Speed 双击配置

当前快照增加下列双击动作，复用用户在 Chrome Global Speed 页面快捷键中配置的数字小键盘键。此前的 Typeless 和方向键单击动作保留。

| 遥控器双击 | 发送的键 | Global Speed 动作 |
| --- | --- | --- |
| 上键 | Numpad8 | 播放速度增加 0.5 |
| 下键 | Numpad2 | 播放速度减少 0.5 |
| 左键 | Numpad4 | 后退 5 秒 |
| 右键 | Numpad6 | 前进 10 秒 |
| 确定键 | Numpad5 | 设置为 1 倍速 |

数值来源为用户提供的扩展设置截图；没有修改扩展本身。需要 Chrome 视频页面获得焦点且该网站允许扩展页面快捷键，输入框内不作为验收场景。双击绑定本身没有 Chrome 专用作用域，在其他 App 也会发送这些键。

现有手势识别在首次松键后等待约 300 毫秒判断第二次按下，因此上述五键单击会增加等待；快速连续两次单击将被识别为双击。左右键也不再走无双击时的原生透传路径。配置导入、可见映射及当前设备档案持久化已核对；视频速度和时间轴的实际遥控器验收待用户确认。
