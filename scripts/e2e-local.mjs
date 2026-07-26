#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import { createHmac, randomUUID } from "node:crypto";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const hookExecutable = resolve(
  root,
  "dist/AgentGrid Bridge.app/Contents/MacOS/AgentGridHooks",
);
const pairing = await fetch("http://127.0.0.1:49362/pairing").then((response) => {
  if (!response.ok) {
    throw new Error(`配对端点返回 ${response.status}`);
  }
  return response.json();
});

const socket = new WebSocket(`ws://127.0.0.1:${pairing.port}`);
const taskID = `agentgrid-e2e-${Date.now()}`;
const deviceID = `agentgrid-e2e-${taskID}`;
let completed = false;
let closingExpected = false;
let livenessCheckStarted = false;
let sawRunning = false;
let sawApproval = false;
let controlAccepted = false;
let permissionAllowed = false;
let permissionStarted = false;
let controlSent = false;
const timeout = setTimeout(() => {
  socket.close();
  console.error("未在限定时间内收到 Hook 状态");
  process.exitCode = 1;
}, 5_000);

socket.addEventListener("open", () => {
  const events = [
    {
      cwd: root,
      hook_event_name: "SessionStart",
      session_id: taskID,
      source: "cli",
      model: "e2e",
    },
    {
      cwd: root,
      hook_event_name: "PreToolUse",
      session_id: taskID,
      source: "cli",
      tool_name: "apply_patch",
      tool_use_id: "tool-e2e",
      tool_input: { description: "本地端到端状态验证" },
    },
  ];

  for (const event of events) {
    const result = spawnSync(hookExecutable, {
      input: JSON.stringify(event),
      encoding: "utf8",
    });
    if (result.status !== 0) {
      clearTimeout(timeout);
      socket.close();
      throw new Error(result.stderr || `Hook 退出码 ${result.status}`);
    }
  }
});

function startPermissionRequest() {
  permissionStarted = true;
  const child = spawn(hookExecutable, [], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });
  child.on("close", (code) => {
    if (code !== 0) {
      clearTimeout(timeout);
      socket.close();
      throw new Error(stderr || `权限 Hook 退出码 ${code}`);
    }
    permissionAllowed = stdout.includes('"decision":"allow"');
    maybeFinish();
  });
  child.stdin.end(
    JSON.stringify({
      cwd: root,
      hook_event_name: "PermissionRequest",
      session_id: taskID,
      source: "cli",
      tool_name: "exec_command",
      tool_use_id: "permission-e2e",
      tool_input: { description: "仅用于验证手机反向审批链路" },
    }),
  );
}

function sendApproval() {
  controlSent = true;
  const messageId = randomUUID();
  const sentAt = Date.now();
  const sequence = 1;
  const nonce = randomUUID();
  const payload = { action: "approve", taskID };
  const payloadText = JSON.stringify(payload);
  const signingText = [
    "1",
    messageId.toLowerCase(),
    String(sentAt),
    deviceID,
    String(sequence),
    nonce,
    "control.request",
    payloadText,
  ].join("\n");
  const signature = createHmac(
    "sha256",
    Buffer.from(pairing.secret, "base64"),
  )
    .update(signingText)
    .digest("base64");

  socket.send(
    JSON.stringify({
      version: 1,
      messageId,
      type: "control.request",
      sentAt,
      deviceId: deviceID,
      sequence,
      nonce,
      payload,
      signature,
    }),
  );
}

function maybeFinish() {
  if (
    completed ||
    livenessCheckStarted ||
    !sawRunning ||
    !sawApproval ||
    !controlAccepted ||
    !permissionAllowed
  ) {
    return;
  }
  livenessCheckStarted = true;
  clearTimeout(timeout);
  closingExpected = true;
  socket.close();
  setTimeout(async () => {
    try {
      const response = await fetch("http://127.0.0.1:49362/pairing");
      if (!response.ok) {
        throw new Error(`Bridge 返回 ${response.status}`);
      }
      completed = true;
      console.log("端到端通过：状态同步、签名校验、反向审批与关闭帧存活");
    } catch (error) {
      console.error(`Bridge 在关闭帧后退出：${error.message}`);
      process.exitCode = 1;
    }
  }, 500);
}

socket.addEventListener("message", (event) => {
  const envelope = JSON.parse(String(event.data));
  if (
    envelope.type === "control.ack" &&
    envelope.payload.result === "accepted"
  ) {
    controlAccepted = true;
    maybeFinish();
    return;
  }
  if (envelope.type !== "state.snapshot") {
    return;
  }

  const task = envelope.payload.tasks.find((candidate) => candidate.id === taskID);
  if (task?.lifecycle === "running" && task?.activity === "editing") {
    sawRunning = true;
    if (!permissionStarted) {
      startPermissionRequest();
    }
  }
  if (task?.lifecycle === "waitingApproval") {
    sawApproval = true;
    if (!controlSent) {
      sendApproval();
    }
  }
  maybeFinish();
});

socket.addEventListener("error", () => {
  if (completed || closingExpected) {
    return;
  }
  clearTimeout(timeout);
  console.error("无法连接 AgentGrid Bridge");
  process.exitCode = 1;
});
