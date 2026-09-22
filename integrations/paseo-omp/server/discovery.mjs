import net from 'node:net';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

/** @typedef {import('@getpaseo/client').PaseoAgent} PaseoAgent */
/** @typedef {ReturnType<typeof summarize> & {connectionID: string, revision: number, activity: string | null}} Summary */
/** @typedef {{port: number, token: string, hostID: string}} IngressConfig */

// Category-only titles mirror ZCodeEventReducer.safeTitle; never forward source text.
/** @param {PaseoAgent} agent @param {string} hostID */
function summarize(agent, hostID) {
  if (agent?.provider !== 'omp' || agent.labels?.['paseo.parent-agent-id']?.trim() ||
      agent.archivedAt || agent.status === 'closed' ||
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
 * @param {NonNullable<Summary>} summary
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

/** Official lifecycle callbacks plus public SDK catalog and live timeline. No model or control calls.
 * @param {import('@getpaseo/plugin/server').PluginServerContext} server
 * @param {import('@getpaseo/client').PaseoApi} client
 * @param {IngressConfig} config
 * @param {Promise<void>} connected
 */
export function startDiscovery(server, client, config, connected = Promise.resolve()) {
  let stopped = false;
  const connectionID = randomUUID();
  let revision = 0;
  /** @type {Promise<void> | undefined} */
  let active;
  /** @type {NonNullable<Summary>[]} */
  const queue = [];
  /** @type {Set<import("node:net").Socket>} */
  const sockets = new Set();
  /** @type {Map<string, {summary: NonNullable<ReturnType<typeof summarize>>, timestamp: number,
   * turnID: string | null, retiredTurns: Set<string>, retiredThrough: number,
   * pending: Map<string, string>, version: number, turnTimestamp: number, ended: boolean, activity: string | null, seq: number,
   * unsubscribe?: import('@getpaseo/client').PaseoAgentTimelineSubscription}>} */
  const sessions = new Map();
  /** Release demand for sessions that leave the catalog; this does not synthesize outcomes.
   * @param {string} id */
  function retire(id) {
    sessions.get(id)?.unsubscribe?.();
    sessions.delete(id);
    for (let i = queue.length - 1; i >= 0; i--) {
      if (queue[i].agentID === id) queue.splice(i, 1);
    }
  }
  /** @param {string} id */
  function emit(id) {
    const state = sessions.get(id);
    if (!state || stopped) return;
    const waiting = !state.ended && state.pending.size ?
      ([...state.pending.values()].every(kind => kind === 'tool') ? 'waitingApproval' : 'waitingAnswer') : null;
    const summary = { ...state.summary, status: waiting ?? state.summary.status,
      connectionID, revision: ++revision, activity: waiting ? null : state.activity };
    const last = queue.at(-1);
    // Coalesce content within one lifecycle only. Preserve completion followed immediately
    // by another round so the phone sees both transitions and its sound baseline advances.
    if (last?.agentID === id && last.status === summary.status) queue[queue.length - 1] = summary;
    else if (queue.length < 200) queue.push(summary);
    else return;
    if (!active) active = drain();
  }
  /** @param {PaseoAgent} agent */
  function publish(agent) {
    if (stopped) return;
    if (agent.archivedAt || agent.status === 'closed') { retire(agent.id); return; }
    const summary = summarize(agent, config.hostID);
    if (!summary) return;
    const timestamp = Date.parse(agent.updatedAt) || 0;
    let state = sessions.get(agent.id);
    if (state && timestamp < state.timestamp) return;
    if (!state) {
      if (sessions.size >= 200) return;
      state = {summary, timestamp, turnID: null, retiredTurns: new Set(), retiredThrough: -1,
        pending: new Map(), version: 0, turnTimestamp: -1, ended: false, activity: null, seq: -1};
      sessions.set(agent.id, state);
      const subscription = client.agents.ref(agent.id).timeline?.subscribe(event => activity(agent.id, event));
      state.unsubscribe = subscription;
      subscription?.ready.catch(() => { /* Discovery remains available if activity demand fails. */ });
    }
    const turnID = agent.activeTurn?.turnId;
    if (turnID && turnID !== state.turnID) {
      const turnTimestamp = Date.parse(agent.activeTurn?.startedAt ?? '') || timestamp;
      if (state.retiredTurns.has(turnID) || turnTimestamp < state.turnTimestamp ||
          timestamp <= state.retiredThrough) return;
      if (state.turnID) {
        state.retiredTurns.add(state.turnID);
        // Keep recent identity ties and a conservative timestamp floor for older history.
        if (state.retiredTurns.size > 64) {
          state.retiredThrough = state.timestamp;
          const oldest = state.retiredTurns.values().next().value;
          if (oldest) state.retiredTurns.delete(oldest);
        }
      }
      state.turnTimestamp = turnTimestamp;
      state.turnID = turnID;
      state.ended = false;
      state.activity = 'thinking';
    }
    state.version++;
    state.pending = new Map((agent.pendingPermissions ?? []).filter(request => request.id)
      .map(request => [request.id, request.kind]));
    state.timestamp = timestamp;
    // An idle catalog update alone is not proof of a successful turn. Keep the last
    // running state until the authoritative turn_ended callback validates its identity.
    if ((summary.status === 'idle' || agent.status === 'error') && state.turnID) {
      summary.status = state.summary.status;
    }
    if (state.ended) return;
    state.summary = summary;
    if (summary.status === 'running' && !state.activity) state.activity = 'thinking';
    emit(agent.id);
  }
  /** @param {string} id @param {import('@getpaseo/client').PaseoAgentTimelineEvent} message */
  function activity(id, message) {
    const state = sessions.get(id);
    const event = message.event;
    if (!state || state.ended || state.summary.status !== 'running' ||
        event.type !== 'timeline' || !event.turnId || event.turnId !== state.turnID) return;
    const seq = 'seq' in message ? message.seq : undefined;
    if (seq != null && seq <= state.seq) return;
    if (seq != null) state.seq = seq;
    const item = event.item;
    if (item.type === 'reasoning' || item.type === 'assistant_message') state.activity = 'thinking';
    else if (item.type === 'tool_call') {
      // Only the tool name is classified; arguments, results, errors and labels never leave here.
      const name = item.name.toLowerCase();
      state.activity = item.status === 'running' ?
        (/read|view|list/.test(name) ? 'reading' : /edit|write|patch/.test(name) ? 'editing' :
          /search|grep|find/.test(name) ? 'searching' : /agent|task|thread/.test(name) ? 'delegating' :
          /test|gradle|xcode/.test(name) ? 'testing' : /web|browser/.test(name) ? 'browsing' : 'executing') : 'thinking';
    } else return;
    emit(id);
  }
  async function drain() {
    while (!stopped && queue.length) {
      const summary = queue.shift();
      if (!summary) break;
      await send(config, summary, sockets);
    }
    active = undefined;
  }
  /** @param {import('@getpaseo/plugin/server').PluginHookAgent} agent */
  function isRoot(agent) {
    if (stopped || agent.provider !== 'omp') return false;
    if (agent.parentAgentId) {
      retire(agent.id);
      return false;
    }
    return true;
  }

  // Register synchronously before fetching, as required by the official plugin runtime.
  server.on('agent.created', async (event, context) => {
    if (!isRoot(event.agent)) return;
    try {
      const result = await context.paseo.agents.ref(event.agent.id).refresh();
      if (result?.agent) publish(result.agent);
    } catch { /* Monitoring must not fail a Paseo lifecycle callback. */ }
  });
  server.on('agent.turn_started', async (event, context) => {
    if (!isRoot(event.agent)) return;
    try {
      const result = await context.paseo.agents.ref(event.agent.id).refresh();
      if (result?.agent) publish(result.agent);
    } catch { /* Best effort within this connection; recovery belongs to #17. */ }
  });
  // At most one refresh and one dirty flag per session. A callback arriving during a
  // read requires another read; it must not lose the newer state to a version guard.
  /** @type {Map<string, {again: boolean, context: import('@getpaseo/plugin/server').PluginHookContext, promise: Promise<void>}>} */
  const requestRefreshes = new Map();
  for (const name of /** @type {const} */ (['agent.permission_requested', 'agent.permission_resolved'])) {
    server.on(name, (event, context) => {
      if (!isRoot(event.agent) || !sessions.has(event.agent.id)) return;
      const id = event.agent.id;
      const previous = requestRefreshes.get(id);
      if (previous) {
        previous.again = true;
        previous.context = context;
        return previous.promise;
      }
      const job = {again: true, context, promise: Promise.resolve()};
      requestRefreshes.set(id, job);
      job.promise = (async () => {
        try {
          while (job.again && !stopped && sessions.has(id)) {
            job.again = false;
            const state = sessions.get(id);
            const version = state?.version;
            const result = await job.context.paseo.agents.ref(id).refresh();
            if (sessions.get(id) !== state) break;
            if (state?.version !== version) job.again = true;
            else if (result?.agent) publish(result.agent);
          }
        } catch { /* Keep the last known state; never infer approval from a failed read. */ }
        finally { requestRefreshes.delete(id); }
      })();
      return job.promise;
    });
  }
  server.on('agent.turn_ended', async (event, context) => {
    if (!isRoot(event.agent) || !event.turnId ||
        sessions.get(event.agent.id)?.turnID !== event.turnId ||
        sessions.get(event.agent.id)?.ended) return;
    try {
      const result = await context.paseo.agents.ref(event.agent.id).refresh();
      if (!result?.agent || stopped) return;
      publish(result.agent);
      const state = sessions.get(event.agent.id);
      if (!state || state.ended || state.turnID !== event.turnId ||
          !(result.agent.status === 'idle' || (event.outcome.kind === 'failed' && result.agent.status === 'error')) || result.agent.activeTurn ||
          (Date.parse(result.agent.updatedAt) || 0) < state.timestamp) return;
      state.ended = true;
      state.summary.status = event.outcome.kind === 'completed' ? 'succeeded' :
        event.outcome.kind === 'failed' ? 'failed' : 'canceled';
      state.pending.clear();
      state.activity = null;
      emit(event.agent.id);
    } catch { /* Never turn a missing or failed refresh into success. */ }
  });
  let catalogSequence = -1;
  let catalogGeneration = '';
  const unsubscribe = client.agents.subscribe((update) => {
    if (update.generation && catalogGeneration && update.generation !== catalogGeneration) return;
    if (update.generation) catalogGeneration = update.generation;
    if (update.seq != null && update.seq <= catalogSequence) return;
    if (update.seq != null) catalogSequence = update.seq;
    // New live identities are admitted by agent.created, which supplies parentAgentId.
    // Initial snapshots use the public parent label; live creation also verifies the hook parent.
    if (update.kind === 'remove') retire(update.agentId);
    else if (sessions.has(update.agent.id)) publish(update.agent);
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
        if (queue.length >= 100) await active;
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
      queue.length = 0;
      for (const state of sessions.values()) state.unsubscribe?.();
      sessions.clear();
      for (const socket of sockets) socket.destroy();
      await active;
    },
  };
}
