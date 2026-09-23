import net from 'node:net';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

/** @typedef {import('@getpaseo/client').PaseoAgent} PaseoAgent */
/** @typedef {ReturnType<typeof summarize> & {connectionID: string, connectionStartedAt: number, revision: number, activity: string | null, baseline?: boolean, members?: string[], snapshotID?: string, snapshotPart?: number, snapshotParts?: number, codexSessionIDs?: string[]}} Summary */
/** @typedef {{port: number, token: string, hostID: string}} IngressConfig */

// Category-only titles mirror ZCodeEventReducer.safeTitle; never forward source text.
/** @param {PaseoAgent} agent @param {string} hostID */
function summarize(agent, hostID) {
  if (agent?.provider !== 'omp' || ('parentAgentId' in agent && agent.parentAgentId) || agent.labels?.['paseo.parent-agent-id']?.trim() ||
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

/** Only the public provider session identity is needed to label existing Codex cards.
 * @param {PaseoAgent} agent */
function nativeCodexSessionID(agent) {
  if (agent.provider !== 'codex' || agent.archivedAt || agent.status === 'closed' ||
      ('parentAgentId' in agent && agent.parentAgentId) || agent.labels?.['paseo.parent-agent-id']?.trim() ||
      agent.persistence?.provider !== 'codex') return null;
  const id = agent.persistence.sessionId;
  return typeof id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id) ? id : null;
}

/**
 * @param {IngressConfig} config
 * @param {NonNullable<Summary>} summary
 * @param {Set<import('node:net').Socket>} sockets
 * @returns {Promise<boolean>}
 */
function send(config, summary, sockets) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host: '127.0.0.1', port: config.port });
    sockets.add(socket);
    const done = () => { sockets.delete(socket); socket.destroy(); resolve(false); };
    socket.setTimeout(1500, done);
    socket.once('error', done);
    socket.once('end', done);
    socket.once('data', data => { sockets.delete(socket); socket.destroy(); resolve(data.toString().trim() === 'ok'); });
    socket.once('connect', () => socket.write(JSON.stringify({ token: config.token, ...summary }) + '\n'));
    socket.once('close', () => { sockets.delete(socket); resolve(false); });
  });
}

/** Official lifecycle callbacks plus public SDK catalog and live timeline. No model or control calls.
 * @param {import('@getpaseo/plugin/server').PluginServerContext} server
 * @param {import('@getpaseo/client').PaseoApi} client
 * @param {IngressConfig} config
 * @param {Promise<void>} connected
 * @param {{setTimeout: (fn: () => void, ms: number) => any, clearTimeout: (timer: any) => void}} clock
 */
export function startDiscovery(server, client, config, connected = Promise.resolve(), clock = {setTimeout, clearTimeout}) {
  /** @type {any} */
  let timer;
  /** @type {Set<string> | undefined} */
  let snapshotChanges;
  let snapshotInvalid = false;
  /** @param {string} id */
  function markChanged(id) {
    if (!snapshotChanges) return;
    if (snapshotChanges.size < 200) snapshotChanges.add(id);
    else snapshotInvalid = true;
  }
  let needsSnapshot = false;
  let hasSnapshot = false;
  let retryDelay = 1500;
  let stopped = false;
  const connectionID = randomUUID();
  const connectionStartedAt = Date.now();
  let revision = 0;
  /** @type {Promise<void> | undefined} */
  let active;
  /** @type {NonNullable<Summary>[]} */
  const queue = [];
  /** @type {Set<import("node:net").Socket>} */
  const sockets = new Set();
  /** @type {Map<string, {summary: NonNullable<ReturnType<typeof summarize>>, timestamp: number,
   * turnID: string | null, retiredTurns: Set<string>, retiredThrough: number,
   * pending: Map<string, string>, version: number, turnTimestamp: number, ended: boolean, awaitingOutcome: boolean, activity: string | null, seq: number,
   * unsubscribe?: import('@getpaseo/client').PaseoAgentTimelineSubscription}>} */
  const sessions = new Map();
  /** @type {Map<string, number>} */
  const pendingOutcomes = new Map();
  /** @type {Set<string>} */
  const retiredAgents = new Set();
  /** Release demand for sessions that leave the catalog; this does not synthesize outcomes.
   * @param {string} id */
  function retire(id) {
    markChanged(id);
    retiredAgents.add(id);
    if (retiredAgents.size > 200) retiredAgents.delete(retiredAgents.values().next().value ?? '');
    const removed = sessions.get(id);
    removed?.unsubscribe?.();
    sessions.delete(id);
    for (let i = queue.length - 1; i >= 0; i--) {
      if (queue[i].agentID === id) queue.splice(i, 1);
    }
    if (removed && !stopped) {
      if (queue.length < 200) queue.push({...removed.summary, archived: true, connectionID, connectionStartedAt, revision: ++revision, activity: null});
      else needsSnapshot = true;
      if (!active) active = drain();
    }
  }
  /** @param {string} id @param {boolean} baseline */
  function emit(id, baseline = false) {
    const state = sessions.get(id);
    if (!state || stopped || (needsSnapshot && !baseline) || (state.awaitingOutcome && !state.ended && !baseline)) return;
    const waiting = !state.ended && state.pending.size ?
      ([...state.pending.values()].every(kind => kind === 'tool') ? 'waitingApproval' : 'waitingAnswer') : null;
    const summary = { ...state.summary, status: waiting ?? state.summary.status,
      connectionID, connectionStartedAt, revision: ++revision, activity: waiting ? null : state.activity, baseline };
    const last = queue.at(-1);
    // Coalesce content within one lifecycle only. Preserve completion followed immediately
    // by another round so the phone sees both transitions and its sound baseline advances.
    if (last?.agentID === id && last.status === summary.status) queue[queue.length - 1] = summary;
    else if (queue.length < 200) queue.push(summary);
    else { needsSnapshot = true; return; }
    if (!active) active = drain();
  }
  /** @param {PaseoAgent} agent @param {boolean} baseline @param {boolean} recovering */
  function publish(agent, baseline = false, recovering = false) {
    if (stopped || (!baseline && retiredAgents.has(agent.id)) || (baseline && pendingOutcomes.has(agent.id))) return;
    if (baseline) retiredAgents.delete(agent.id);
    if (!baseline) markChanged(agent.id);
    if (agent.archivedAt || agent.status === 'closed') { retire(agent.id); return; }
    const summary = summarize(agent, config.hostID);
    if (!summary) return;
    const timestamp = Date.parse(agent.updatedAt) || 0;
    let state = sessions.get(agent.id);
    if (state && timestamp < state.timestamp) return;
    if (!state) {
      if (sessions.size >= 200) return;
      state = {summary, timestamp, turnID: null, retiredTurns: new Set(), retiredThrough: -1,
        pending: new Map(), version: 0, turnTimestamp: -1, ended: false, awaitingOutcome: false, activity: null, seq: -1};
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
    if (baseline && !turnID) {
      // A recovered idle/error fact is not a replayable outcome.
      state.summary = {...summary, status: agent.status === 'idle' ? 'idle' : 'offline'};
      state.awaitingOutcome = false;
      state.ended = state.ended || (!!state.turnID && recovering);
      state.activity = null;
      emit(agent.id, true);
      return;
    }
    if (state.ended) return;
    state.summary = summary;
    if (summary.status === 'running' && !state.activity) state.activity = 'thinking';
    // Gate every publisher, including late timeline events, until the public outcome
    // arrives or the authoritative catalog confirms active execution again.
    state.awaitingOutcome = !!state.turnID && !turnID &&
      (agent.status === 'idle' || agent.status === 'error');
    emit(agent.id, baseline);
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
      if (!await send(config, summary, sockets)) {
        // Never replay a backlog of historical completions after a transport failure.
        needsSnapshot = true;
        queue.length = 0;
        break;
      }
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

  /** @type {Set<Promise<unknown>>} */
  const jobs = new Set();
  /** @type {import('@getpaseo/plugin/server').PluginServerContext['on']} */
  const on = (name, handler) => server.on(name, (event, context) => {
    if (stopped || jobs.size >= 200) return;
    // Paseo never waits for our SDK or Bridge. Bounded jobs are repaired by catalog reads.
    const job = Promise.resolve(handler(event, context)).catch(() => {}).finally(() => jobs.delete(job));
    jobs.add(job);
  });
  // Register synchronously before fetching, as required by the official plugin runtime.
  on('agent.created', async (event, context) => {
    if (!isRoot(event.agent)) return;
    try {
      const result = await context.paseo.agents.ref(event.agent.id).refresh();
      if (result?.agent) publish(result.agent);
    } catch { /* Monitoring must not fail a Paseo lifecycle callback. */ }
  });
  on('agent.turn_started', async (event, context) => {
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
    on(name, (event, context) => {
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
          for (let reads = 0; reads < 2 && job.again && !stopped && sessions.has(id); reads++) {
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
  on('agent.turn_ended', async (event, context) => {
    if (!isRoot(event.agent) || !event.turnId ||
        sessions.get(event.agent.id)?.turnID !== event.turnId ||
        sessions.get(event.agent.id)?.ended) return;
    const id = event.agent.id;
    pendingOutcomes.set(id, (pendingOutcomes.get(id) ?? 0) + 1);
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
    finally {
      const remaining = (pendingOutcomes.get(id) ?? 1) - 1;
      if (remaining) pendingOutcomes.set(id, remaining);
      else pendingOutcomes.delete(id);
    }
  });
  let catalogSequence = -1;
  let catalogGeneration = '';
  /** @type {Set<string>} */
  const retiredGenerations = new Set();
  const unsubscribe = client.agents.subscribe((update) => {
    if (update.generation && retiredGenerations.has(update.generation)) return;
    if (update.generation && catalogGeneration && update.generation !== catalogGeneration) {
      retiredGenerations.add(catalogGeneration);
      if (retiredGenerations.size > 32) retiredGenerations.delete(retiredGenerations.values().next().value ?? '');
      catalogSequence = -1;
      hasSnapshot = false;
      for (const state of sessions.values()) state.seq = -1;
    }
    if (update.generation) catalogGeneration = update.generation;
    if (update.seq != null && update.seq <= catalogSequence) return;
    if (update.seq != null) catalogSequence = update.seq;
    // Import/resume need not emit created; public parent labels still exclude children.
    // A native identity changed during the list read: discard the partial membership.
    if (snapshotChanges && (update.kind === 'remove' || update.agent.provider === 'codex')) snapshotInvalid = true;
    if (update.kind === 'remove') retire(update.agentId);
    else publish(update.agent);
  });
  // The public API has no connection event subscription. One bounded catalog read
  // every 15 seconds also repairs missed hooks and late Bridge startup.
  async function reconcile() {
    const recovering = needsSnapshot || !hasSnapshot;
    const changed = new Set();
    snapshotChanges = changed;
    snapshotInvalid = false;
    try {
      /** @type {PaseoAgent[]} */
      const agents = [];
      /** @type {Set<string>} */
      const nativeIDs = new Set();
      /** @type {string | null | undefined} */
      let cursor;
      const cursors = new Set();
      do {
        const page = await client.agents.list({
          timeout: 5000,
          filter: { includeArchived: false },
          page: { limit: 200, ...(cursor ? { cursor } : {}) },
          ...(!cursor ? { subscribe: { subscriptionId: 'agentpager-omp-discovery' } } : {}),
        });
        if (stopped) return;
        for (const {agent} of page.entries) {
          const id = nativeCodexSessionID(agent);
          if (id && nativeIDs.size < 200) nativeIDs.add(id);
        }
        agents.push(...page.entries.map(entry => entry.agent).filter(agent => summarize(agent, config.hostID)).slice(0, 200 - agents.length));
        cursor = page.pageInfo.hasMore ? page.pageInfo.nextCursor : null;
        if (cursor && cursors.has(cursor)) throw new Error("repeated catalog cursor");
        if (cursor) cursors.add(cursor);
      } while (cursor && agents.length < 200 && cursors.size < 200 && !stopped);
      if (stopped) return;
      if (snapshotInvalid) return;
      const ids = new Set(agents.map(agent => agent.id));
      if (!cursor) for (const id of sessions.keys()) if (!ids.has(id) && !changed.has(id)) retire(id);
      needsSnapshot = false;
      for (const agent of agents.slice(0, 200)) if (!changed.has(agent.id)) publish(agent, true, recovering);
      await active;
      if (!cursor && !needsSnapshot) {
        // Commit a complete host membership in bounded, ordered chunks. This also
        // removes stale Bridge records when the adapter itself has been restarted.
        const ids = [...sessions.keys()];
        const snapshotID = randomUUID();
        const codexIDs = [...nativeIDs];
        const parts = Math.max(1, Math.ceil(Math.max(ids.length, codexIDs.length) / 20));
        for (let part = 0; part < parts && !stopped; part++) {
          queue.push({hostID: config.hostID, agentID: '', provider: 'omp', projectName: '',
            titleCategory: '', status: 'snapshot', archived: false, activity: null,
            connectionID, connectionStartedAt, revision: ++revision,
            snapshotID, snapshotPart: part, snapshotParts: parts,
            codexSessionIDs: codexIDs.slice(part * 20, (part + 1) * 20), members: ids.slice(part * 20, (part + 1) * 20)});
          if (!active) active = drain();
          await active;
          if (needsSnapshot) break;
        }
      }
      if (!needsSnapshot) hasSnapshot = true;
    } finally { snapshotChanges = undefined; }
  }
  async function tick() {
    let delay = 15000;
    try {
      await reconcile();
      if (needsSnapshot) throw new Error('transport unavailable');
      retryDelay = 1500;
    } catch {
      // A failed snapshot is not an empty authoritative catalog.
      needsSnapshot = true;
      delay = retryDelay;
      retryDelay = Math.min(retryDelay * 2, 30000);
    } finally { if (!stopped) timer = clock.setTimeout(tick, delay); }
  }
  const ready = (async () => {
    try { await connected; await reconcile(); }
    finally { if (!stopped) timer = clock.setTimeout(tick, 15000); }
  })();
  return {
    ready,
    async flush() { await ready; while (jobs.size) await Promise.all(jobs); while (active) await active; },
    async close() {
      stopped = true;
      clock.clearTimeout(timer);
      unsubscribe();
      queue.length = 0;
      for (const state of sessions.values()) state.unsubscribe?.();
      sessions.clear();
      for (const socket of sockets) socket.destroy();
      await active;
    },
  };
}
