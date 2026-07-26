# AgentGrid 协议 v1

所有消息使用 UTF-8 JSON，通过局域网 WebSocket 传输。

普通信封字段：

- `version`：固定为 `1`。
- `messageId`：UUID。
- `type`：消息类型。
- `sentAt`：Unix 毫秒时间戳。
- `payload`：消息内容。

手机发往 Mac 的控制消息额外包含 `deviceId`、`sequence`、`nonce` 和 `signature`。签名算法为 HMAC-SHA256，签名原文由核心库的 `ControlSigner` 统一生成。

Mac 返回 `control.ack`，状态为 `accepted`、`rejected`、`stale` 或 `unsupported`。最终任务状态始终以 Mac 发出的权威快照为准。

