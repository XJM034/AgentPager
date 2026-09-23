import type { PluginServerContext } from '@getpaseo/plugin/server';
import { createPaseoClient } from '@getpaseo/client';
import { readFileSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { startDiscovery } from './server/discovery.mjs';

export default function contribute(server: PluginServerContext) {
  const configPath = process.env.AGENTPAGER_PASEO_CONFIG ??
    join(homedir(), '.config', 'agentpager', 'paseo.json');
  let config;
  try {
    if ((statSync(configPath).mode & 0o777) !== 0o600) return () => {};
    config = JSON.parse(readFileSync(configPath, 'utf8'));
    if (config.enabled === false) return () => {};
    const url = new URL(config.paseoURL);
    if (url.protocol !== 'ws:' || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
        url.username || url.password || !/^[a-f0-9]{64}$/i.test(config.token) ||
        !/^[a-zA-Z0-9-]{1,128}$/.test(config.hostID) ||
        !Number.isInteger(config.port) || config.port <= 1024 || config.port > 65535) return () => {};
  } catch { return () => {}; }

  // Public SDK root only. No private database, RPC driver, stdin takeover or model calls.
  const client = createPaseoClient({
    url: config.paseoURL,
    password: config.paseoPassword,
    authHeader: config.paseoAuthHeader,
    clientId: `agentpager-${config.hostID}`,
    connectTimeoutMs: 5000,
    reconnect: { enabled: true, baseDelayMs: 1500, maxDelayMs: 30000 },
    suppressSendErrors: true,
    logger: { debug() {}, info() {}, warn() {}, error() {} },
  });
  // Registration must happen during contribute(), before Paseo captures hook registrations.
  const discovery = startDiscovery(server, client, config, client.connect());
  const ready = discovery.ready.catch(() => {
    console.warn('AgentPager: Paseo discovery unavailable');
  });
  return async () => {
    await discovery.close();
    await client.close();
    await ready;
  };
}
