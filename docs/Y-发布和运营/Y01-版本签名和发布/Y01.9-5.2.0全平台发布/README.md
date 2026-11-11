# Y01.9 5.2.0 全平台发布（Android、电视、Windows、Linux，构建号 5102）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：用户 2026-10-16：“发布5.2.0稳定版本，全平台”
- 相关：Y01.8（5.1.0）；R01.3（真实操作的掉帧）、A03.5（全局阻尼和弹簧转场）、A01.6（液态玻璃折射）；发布说明 [releases/v5.2.0.md](../../Y03-发布说明和README/releases/v5.2.0.md)

## 目标

- 新仓库 `wzgrx/PureLive` 打标签 `v5.2.0`，发布页上传六个包和 `SHA256SUMS.txt`。
- 最后改新仓库 master 的 `assets/version.json`、`assets/releases.json`；旧仓库 `wzgrx/pure_live` 的 master 只同步这两个文件（PROCESS 第 11 节第 8 条）。

## 版本

| 方面 | 5.1.0（Y01.8） | 5.2.0（本任务） |
|---|---|---|
| 版本 | `5.1.0+5101` | `5.2.0+5102` |
| Android versionCode | 7101、6101、9101 | 7102、6102、9102 |
| Windows | 安装版、便携 ZIP | 同 |
| Linux | `linux-x64.tar.gz` | 同 |
| 签名 | 维护者调试密钥 | 同一把（D-006） |
