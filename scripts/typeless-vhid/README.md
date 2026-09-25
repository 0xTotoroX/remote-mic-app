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
