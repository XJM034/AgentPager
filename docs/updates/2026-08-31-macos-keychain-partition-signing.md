# macOS 更新后重新授权：分区诊断与修复验收

## 当前范围

用户要求今天只解决 Mac 重复授权问题，不再扩展 UI。基线为 `173c430`、本机 0.3.0 Build 16；Android、Windows、共享协议、Key 内容和十分钟刷新规则保持不变。Build 16 在用户选择“始终允许”后已恢复，并通过同版本重启；此次继续解释并处理跨版本失败。

## 已确认的根因与早先验证缺口

1. 诊断时只读检查两个真实条目：GLM 与 Pairing 的分区列表均为 `cdhash:`，包含不同构建的指纹，没有 Apple 团队分区；当时 Build 16 的指纹与已授权条目相符。没有请求秘密数据或修改访问列表。
2. 诊断时已安装的 Build 16 使用 `AgentPager Local Development` 自签证书；Apple 签名验证不通过，`TeamIdentifier` 未设置。当时机器没有可用的 Apple Development 或 Developer ID 签名身份。
3. [Apple 的客户端签名分类实现](https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/clientid.cpp)对 Apple 开发者签名使用团队分区；无法分类的自签名仍落到代码指纹。[分区校验实现](https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/acls.cpp)在普通应用 ACL 以外另行检查此分区，并在不匹配时要求授权。因此同一证书、同一应用身份规则不足以让自签名的新二进制沿用授权。
4. 原 `scripts/test-macos-keychain-signing.py` 创建的临时钥匙串没有分区 ACL。新的元数据检查证实了这一差异；它的 A→B 读取成功只覆盖旧式数据库。Apple 实现在旧数据库版本上跳过分区检查，这解释了测试与真实登录钥匙串不一致。此前“隔离两个构建通过”不再作为真实更新授权复用证据。

只读反馈命令：

```sh
swift -suppress-warnings scripts/inspect-macos-keychain-access.swift --expect-stable
```

Build 16 实际结果为退出 1：`stablePartitionSigning=false`、`appleSigned=false`；两个真实条目都有分区 ACL，类别均为 `cdhash`。原始 Key、配对密钥、账号或密码不进入输出。

## 本轮代码与说明修正

- 新增只读签名/权限元数据检查入口。
- 打包脚本区分 Apple 团队签名与本机自签名，不再把任何固定证书都描述成更新免授权。
- 隔离签名脚本必须检查分区 ACL，缺失时退出 2 并明确报告覆盖不足；有分区的自签名更新应静默拒绝。
- 按 `claude-agents-bootstrap` 同步 macOS 规则镜像、开发流程与现行 GLM 说明；根规则与目录结构无需变化。

## 修复路径与权限边界

用户明确批准通过 Xcode 配置开发证书并备份后切换本机签名。实际打开 Xcode 时没有已登录账户；用户随后亲自完成登录。Xcode 识别免费个人团队，但证书管理中的创建项不可用，未尝试强制执行灰色操作。按 [Apple 自动签名流程](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html)，在被忽略的 `dist/` 内建立临时 macOS 命令行构建，通过 `xcodebuild -allowProvisioningUpdates` 成功取得 Apple Development 证书。没有购买会员、撤销旧证书、配置正式分发或公证，也没有请求设备注册或 App 上传。

只备份并更换本机签名指纹配置，证书私钥保持在系统钥匙串中，没有导出私钥。新证书的 Apple 信任链和团队身份已通过验证；有效期至 2027-08-31，但证书有效期不是钥匙串授权倒计时，也不构成届时一定弹窗或此前绝不弹窗的保证。未改写真实 GLM Key 或配对密钥、放宽条目 ACL、删除分区列表或更改系统信任。

签名配置与 Build 16 的完整备份位于本机 `~/Library/Application Support/AgentPager/Backups/2026-08-31-151910-before-apple-signing-build16/`；复制文件、文件权限、签名和主程序哈希已核对。之后每次安装仍独立备份旧 App，并正常退出后替换。

## 真实升级与运行结果

- 15:26 安装 0.3.0 Build 17，Bundle 保持 `com.agentpager.bridge`，arm64。用户为首次更换签名的两个条目分别选择“始终允许”；系统日志确认两次主动授权，GLM 与 Pairing 的权限元数据均出现 Apple 团队分区。
- 15:27 Build 17 真实查询成功：5 小时剩余 100%、每周剩余 99%；合成 Hook 通信测试通过。
- 15:28 安装 Build 18。与 Build 17 的应用身份规则相同，主程序哈希及代码指纹不同；两个条目仍通过已有团队分区读取，没有添加 Build 18 的代码指纹授权。
- Build 18 升级后于 15:28:29 返回新额度；随后正常退出并重启，于 15:28:56 再次返回新额度。两个窗口均为 100% / 99%，这是本次观测值，不是固定产品数值。升级及重启对应进程的系统授权提示计数均为 0，Hook 通信测试再次通过。
- 最终两个十分钟自动刷新周期通过：15:29 → 15:39 → 15:49，三个时点均“可用”，第二次周期完成于 15:49:23 的只读观察。期间没有持续模拟手机连接或主动刷新。15:30–15:34 原生界面读数不可取，15:35 重新打开设置后恢复；没有调用刷新，最后成功时间仍是 15:29，之后两次定时查询才前移。
- 15:49:30 核对覆盖升级、重启与两个周期的 `securityd` 日志，Build 18 两个进程的授权提示合计为 0；已安装二进制及原有 Hook 配置指纹均未改变。观察脚本正常完成并退出，没有留下模拟手机连接。

Build 18 已安装主程序 SHA-256 为 `72ace6b47e697099809adb3075233ce75f56ae49f425c45855b2c4fb8420127c`。Build 17 备份位于本机 `~/Library/Application Support/AgentPager/Backups/2026-08-31-152811-0.3.0-build17-before-build18/`。临时构建工程、证书指纹配置、签名元数据与安装产物不进入 Git。

## 本轮验证

- `swift test`：182 项通过（170 Core、12 Bridge），应用逻辑没有改动。
- `zsh -n scripts/package-macos.sh`、Python 语法检查、文档本地链接检查、`git diff --check` 与规则镜像检查通过。
- 修正后的隔离探针实际退出 2，报告 `partition_acl_covered=false`，不再冒充真实升级验证通过。临时证书、私钥和钥匙串已清理，默认钥匙串与搜索列表保持不变。
- Build 16 的真实自动刷新已观察到 14:51 → 15:01 → 15:11，状态持续“可用”；期间未点击刷新、未保留模拟手机连接。15:11:23 由只读原生界面观察到第二次成功时间前移。此结果确认当前已授权版本的两个十分钟周期正常，不代表跨版本问题已解决。
- 按重启后的 PID 31016 查询覆盖上述两个周期的系统日志，钥匙串提示事件为 0；日志为 `dist/glm-build16-two-cycle-prompt-events.json`。
- 上述 Build 16 诊断阶段未替换 App；后续切换签名与安装按前节记录执行。Android、Windows、共享协议及十分钟刷新逻辑未修改。Redmi 实机画面及更长时间运行未复验。

检查日志与元数据均在被忽略的 `dist/glm-keychain-partition-diagnosis.*`、`dist/glm-signing-coverage-corrected-final.log`、`dist/glm-partition-diagnosis-swift-tests.log`、`dist/glm-build16-automatic-cycles.jsonl` 及 `dist/apple-signing-*`。最终验收摘要为 `dist/apple-signing-build18-final-acceptance.json`。本轮提交范围仅为诊断、打包提示、检查脚本和文档，目标为个人定制分支 `alexx_custom`；证书、私钥、本机签名配置和 App 不进入 Git。

本机跨版本重复授权问题已通过上述验收。正常查询没有十分钟的授权有效期；签名团队更换、用户重置访问权限或钥匙串状态变化仍可能需要处理，不能将本轮结果描述为任何环境下永久免授权。
