# Y01.11 5.4.0 全平台发布（Android、电视、Windows、Linux，构建号 5104）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：用户 2026-10-16：“gate过了就推送，然后发布5.4.0稳定版本，全平台”
- 相关：Y01.10（5.3.0）；Z05.3（多语言）；G05.2（音量增强）；A08.13（本地弹幕输入框居中）；发布说明 [releases/v5.4.0.md](../../Y03-发布说明和README/releases/v5.4.0.md)

## 目标

- 新仓库 `wzgrx/PureLive` 打标签 `v5.4.0`，发布页上传六个包和 `SHA256SUMS.txt`。
- 最后改新仓库 master 的 `assets/version.json`、`assets/releases.json`；旧仓库 `wzgrx/pure_live` 的 master 只同步这两个文件（PROCESS 第 11 节第 8 条）。

## 版本

| 方面 | 5.3.0（Y01.10） | 5.4.0（本任务） |
|---|---|---|
| 版本 | `5.3.0+5103` | `5.4.0+5104` |
| Android versionCode | 7103、6103、9103 | 7104、6104、9104 |
| Windows | 安装版、便携 ZIP | 同 |
| Linux | `linux-x64.tar.gz` | 同 |
| 签名 | 维护者调试密钥 | 同一把（D-006） |
