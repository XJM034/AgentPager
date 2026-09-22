import net from 'node:net';
import path from 'node:path';

/** @typedef {import('@getpaseo/client').PaseoAgent} PaseoAgent */
/** @typedef {{port: number, token: string, hostID: string}} IngressConfig */

// Category-only titles mirror ZCodeEventReducer.safeTitle; never forward source text.
/** @param {PaseoAgent} agent @param {string} hostID */
function summarize(agent, hostID) {
  if (agent?.provider !== 'omp' || agent.archivedAt || agent.status === 'closed' ||
      typeof agent.id !== 'string' || !agent.id || agent.id.length > 128) return null;
  const cwd = typeof agent.cwd === 'string' ? path.normalize(agent.cwd) : '';
  const home = /^\/Users\/[^/]+\/?$/.test(cwd);
  const projectName = home ? 'omp' : (path.basename(cwd).replace(/[\x00-\x1f\x7f]/g, '').slice(0, 48) || 'omp');
  const text = typeof agent.title === 'string' ? agent.title.toLowerCase() : '';
  /** @type {[RegExp, string][]} */
  const categories = [
    [/测试|验证|test|verify|gradle|xcode/, 'verification'],
    [/修复|修改|编辑|fix|edit|patch/, 'change'],
    [/实现|创建|开发|implement|create|build/, 'development'],
    [/读取|查看|阅读|read|view/, 'reading'],
    [/搜索|查找|检索|search|find|grep/, 'search'],
    [/解释|分析|诊断|explain|analyze|diagnose/, 'analysis'],
  ];
  return {
    hostID, agentID: agent.id, provider: 'omp', projectName,
    titleCategory: text ? (categories.find(([pattern]) => pattern.test(text))?.[1] ?? 'request') : '',
    status: ['idle', 'initializing', 'running'].includes(agent.status) ? agent.status : 'offline',
    archived: false,
  };
}

/**
 * @param {IngressConfig} config
 * @param {NonNullable<ReturnType<typeof summarize>>} summary
 * @param {Set<import('node:net').Socket>} sockets
 * @returns {Promise<void>}
 */
function send(config, summary, sockets) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host: '127.0.0.1', port: config.port });
    sockets.add(socket);
    const done = () => { sockets.delete(socket); socket.destroy(); resolve(); };
    socket.setTimeout(1500, done);
    socket.once('error', done);
    socket.once('end', done);
    socket.once('data', done);
    socket.once('connect', () => socket.write(JSON.stringify({ token: config.token, ...summary }) + '\n'));
    socket.once('close', () => { sockets.delete(socket); resolve(); });
  });
}

/** Official lifecycle callbacks plus public SDK catalog. Discovery only; no round controls.
 * @param {import('@getpaseo/plugin/server').PluginServerContext} server
 * @param {import('@getpaseo/client').PaseoApi} client
 * @param {IngressConfig} config
 * @param {Promise<void>} connected
 */
export function startDiscovery(server, client, config, connected = Promise.resolve()) {
  let stopped = false;
  /** @type {Promise<void> | undefined} */
  let active;
  /** @type {Map<string, NonNullable<ReturnType<typeof summarize>>>} */
  const queue = new Map();
  /** @type {Set<import("node:net").Socket>} */
  const sockets = new Set();
  /** @param {PaseoAgent} agent */
  function publish(agent) {
    if (stopped) return;
    const summary = summarize(agent, config.hostID);
    if (!summary) return;
    if (queue.size >= 200 && !queue.has(summary.agentID)) return;
    queue.set(summary.agentID, summary);
    if (!active) active = drain();
  }
  async function drain() {
    while (!stopped && queue.size) {
      const entry = queue.entries().next().value;
      if (!entry) break;
      const [id, summary] = entry;
      queue.delete(id);
      await send(config, summary, sockets);
    }
    active = undefined;
  }
  // Register before fetching so creations during the initial list are not lost.
  server.on('agent.created', async (event, context) => {
    if (stopped || event.agent.provider !== 'omp' || event.agent.parentAgentId) return;
    try {
      const result = await context.paseo.agents.ref(event.agent.id).refresh();
      if (!stopped && result?.agent) publish(result.agent);
    } catch { /* Monitoring must not fail a Paseo lifecycle callback. */ }
  });
  const unsubscribe = client.agents.subscribe((update) => {
    if (update.kind === 'upsert') publish(update.agent);
  });
  const ready = (async () => {
    await connected;
    if (stopped) return;
    /** @type {string | null | undefined} */
    let cursor;
    do {
      const page = await client.agents.list({
        filter: { includeArchived: false },
        page: { limit: 200, ...(cursor ? { cursor } : {}) },
        ...(!cursor ? { subscribe: { subscriptionId: 'agentpager-omp-discovery' } } : {}),
      });
      if (stopped) return;
      for (const entry of page.entries) {
        publish(entry.agent);
        // Backpressure for initial pages, without retaining raw upstream snapshots in a queue.
        if (queue.size >= 100) await active;
      }
      cursor = page.pageInfo.hasMore ? page.pageInfo.nextCursor : null;
    } while (cursor && !stopped);
    await active;
  })();
  return {
    ready,
    async flush() { await ready; while (active) await active; },
    async close() {
      stopped = true;
      unsubscribe();
      queue.clear();
      for (const socket of sockets) socket.destroy();
      await active;
    },
  };
}
