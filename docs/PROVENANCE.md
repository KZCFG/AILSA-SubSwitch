# 来源与沿革

AILSA SubSwitch 源自 [Copool](https://github.com/AlickH/Copool)，使用的基线提交为
`3cb6ede534bdbff86804e9beaed567a190dac2f3`。本独立仓库从经过审查的当前源码快照开始，
不会抹去这一衍生关系，也不会把上游架构声称为 ASS 的原创成果。

## 复用与署名说明

- Copool 及其上游项目 [codex-tools](https://github.com/170-carry/codex-tools) 适用根目录
  `LICENSE` 中保留的 MIT 声明。Copool 的公开 `LICENSE` 已于 2026 年 9 月 17 日完成核验。
  作者也确认其原创 Swift 贡献采用 MIT 许可；相关私人通信不予公开。
- `LiquidProgress.swift` 改编自 CodexBar 的进度条结构。
- Cursor 与 Antigravity 读取器的实现参考了 CodexBar。对于所有相关复用内容，项目采取保守做法，
  完整保留 CodexBar 的 MIT 声明；尚未进行逐行的完整原创性比对。
- OpenCodex 是可选的外部数据源。其服务器及运行时代码不属于本应用，也不在本源码快照中。
- 应用图标是项目专用的 AI 辅助插画。各服务商的名称与标志仍归其各自所有者所有。

详见[随附的第三方声明](../Sources/AILSA_SS/Resources/THIRD_PARTY_NOTICES.md)。已移除的代理二进制文件与 Rust 源码、
复制的 Electron JavaScript 快照、私有产物及上游截图不包含在本公开快照中。

## 文件清单

[provenance.csv](provenance.csv) 将发布文件与记录中的上游基线进行比较，并标记为：相同、已修改或不存在于基线。
“Local”表示该文件不在基线中；这**不能独立证明其作者权属于本项目**。
图片按字节大小列出，而不是按代码行数列出。

如需重新生成，请使用包含上游基线提交的开发检出目录：

```bash
python3 scripts/generate_provenance.py --upstream /path/to/Copool
```

所选的上游检出目录必须包含该基线提交。干净的公开仓库有意不包含开发者的私有工作历史。
