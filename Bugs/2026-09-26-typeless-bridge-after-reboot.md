# 重启后 Typeless 遥控器触发失效

## 复现与原因

2026-09-26 开机后，独立测试 App 228.5 和 Typeless 正在运行，遥控器已连接，pqrs 虚拟键盘扩展为 activated enabled。App 收到确定键，`SHORTCUT BRIDGE ... result=unavailable elapsed_ms=0`；桥进程及官方 VirtualHIDDevice daemon 都未运行，`/var/run/sayall-vhid-bridge.sock` 不存在。

此前只手动运行了两项后台进程，没有注册开机启动项；重启终止了它们。保存在 `/tmp` 的原始启动脚本也已消失。Git 源码和设置快照完整，不能替代本机服务注册。

## 修正

增加 `scripts/typeless-vhid/manage-autostart.sh`，通过管理员验证注册两项 root LaunchDaemon，复用已安装程序；开机运行、异常退出重启、10 秒重试节流、停止超时 5 秒。使用独立测试标签，不修改 pqrs 自己的启动项。提供只读 status、非特权 render、可逆 disable；不重置 App 配置，不更换驱动或 App。

安装前核验程序及各层父目录的 root 所有权与写权限、官方 daemon 签名和 pqrs Team ID。未知既有 plist、软链接目标、重复手动进程拒绝覆盖。桥仍仅接收安装时授权 UID 的 V/T/Q 白名单指令。

## 验证

- shell 语法、两份生成 plist 格式、启动参数与 UID、拒绝 root UID、`git diff --check` 通过。
- 首次安装因 `codesign -R` 内联表达式缺少 `=` 前缀在预检退出，未安装启动项；修正后签名与路径权限检查通过。
- 用户在终端完成管理员安装；2026-09-26 两项均为 `state = running`，分别 PID 12300/12305，均为 root，启动项 enabled，RunAtLoad/KeepAlive 已加载。plist 为 root:wheel 0644；socket 属于当前 UID 501，模式 0600。
- 实体遥控器验收待用户反馈；服务运行不等于 Typeless 已执行。
- 需要最终真实重启验收，不由 Agent 自动重启用户电脑。

## 回退

在 Mac 终端执行 `sudo /bin/bash scripts/typeless-vhid/manage-autostart.sh disable` 停止并禁用本次两项服务。二进制、plist、驱动和用户按键配置均保留。
