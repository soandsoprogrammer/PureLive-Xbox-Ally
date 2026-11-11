# Y01.10 5.3.0 全平台发布（Android、电视、Windows、Linux，构建号 5103）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：用户 2026-10-16：“发布5.3.0稳定版本，全平台”
- 相关：Y01.9（5.2.0）；K01.3（各平台官方登录）；发布说明 [releases/v5.3.0.md](../../Y03-发布说明和README/releases/v5.3.0.md)

## 目标

- 新仓库 `wzgrx/PureLive` 打标签 `v5.3.0`，发布页上传六个包和 `SHA256SUMS.txt`。
- 最后改新仓库 master 的 `assets/version.json`、`assets/releases.json`；旧仓库 `wzgrx/pure_live` 的 master 只同步这两个文件（PROCESS 第 11 节第 8 条）。

## 版本

| 方面 | 5.2.0（Y01.9） | 5.3.0（本任务） |
|---|---|---|
| 版本 | `5.2.0+5102` | `5.3.0+5103` |
| Android versionCode | 7102、6102、9102 | 7103、6103、9103 |
| Windows | 安装版、便携 ZIP | 同 |
| Linux | `linux-x64.tar.gz` | 同 |
| 签名 | 维护者调试密钥 | 同一把（D-006） |
