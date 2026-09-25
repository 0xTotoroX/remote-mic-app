# 主页键的调度中心快捷键未生效

## 现场与证据

- 测试包 1.9.21 / 228.5；主页键自定义为 Control+上箭头，用户确认实体键盘组合可用，但遥控器无法打开调度中心。
- 2026-09-25T08:56:02.494Z、08:56:03.438Z、08:56:04.489Z 运行日志均记录主页键单击，随后 `SHORTCUT ACTION submitted key_code=126 modifier_flags=262144 standalone=false success=true`。这只证明事件提交，不证明系统执行。
- 连续快速按下另有 `awaiting_stable_release stable_release_ms=600`，但不能解释已提交的单次动作也无效。模拟快捷键未生效的具体原因尚未定位。

## 配置修正与验证

复用既有“打开自定义 APP → 只打开 APP”，选择系统 `/System/Applications/Mission Control.app`，无需新增产品代码、重建 App 或私有接口。原生界面显示“主页键 · 单击 · 调度中心”；2026-09-25 用户实按后确认“出现了”。

随后按用户要求配置主页键长按打开本机 `/Applications/ChatGPT.app`。原生导出显示其 bundle 标识为 `com.openai.codex`；仅启动或激活应用，不自动选择内部模式。此长按只完成配置与导出核对，实机效果待确认。添加长按后短按在松键时执行，长按触发后松开不补发单击。

配置保存至 `scripts/typeless-vhid/settings.json`。导出脚本仅放行这两个已审查的纯启动应用档案；核验原始导出与去除音频设备标识后的快照相等，并确认未知路径、输入框数据及悬空档案引用会被拒绝。
