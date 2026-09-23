// Controlled public Paseo input; the adapter, ingress, Bridge and phone transport are real.
import assert from 'node:assert/strict';
import { createInterface } from 'node:readline';
import { startDiscovery } from '../server/discovery.mjs';
const hooks = new Map();
let tick;
const delays = [];
const clock = {setTimeout: (fn, ms) => { delays.push(ms); tick = fn; return 1; }, clearTimeout: () => { tick = undefined; }};
let update;
let timeline;
let snapshot = { id: 'main', provider: 'omp', cwd: '/private/secret-path/TurnTest',
  title: 'implement secret-prompt', model: 'openai-codex/gpt-5.5', status: 'idle',
  updatedAt: '2026-09-22T08:00:00.000Z', lastUserMessageAt: null, activeTurn: null };
const client = { agents: {
  subscribe: handler => { update = handler; return () => {}; },
  list: async () => ({ entries: [{agent: snapshot}, {agent: {...snapshot, id: 'existing-child', labels: {'paseo.parent-agent-id': 'main'}}}], pageInfo: {hasMore: false} }),
  ref: id => ({ refresh: async () => ({agent: snapshot}), timeline: {
    subscribe: handler => { if (id === 'main') timeline = handler; return Object.assign(() => {}, {ready: Promise.resolve()}); },
  } }),
} };
let adapter = startDiscovery({ on: (name, fn) => hooks.set(name, fn) }, client,
  {port: Number(process.argv[2]), token: process.argv[3], hostID: 'turn-test'}, Promise.resolve(), clock);
await adapter.ready;
console.log("ready");
for await (const command of createInterface({input: process.stdin})) {
  if (command === 'sync') await tick?.();
  if (command === 'outcome-race') {
    let release;
    const turnId = snapshot.activeTurn.turnId;
    snapshot = {...snapshot, status: 'idle', activeTurn: null, updatedAt: '2026-09-22T08:00:05Z'};
    hooks.get('agent.turn_ended')({agent: snapshot, turnId, outcome: {kind: 'completed'}},
      {paseo: {agents: {ref: () => ({refresh: () => new Promise(resolve => { release = resolve; })})}}});
    await tick();
    release({agent: snapshot});
  }
  if (command === 'adapter-restart-empty') {
    await adapter.close();
    snapshot = {...snapshot, archivedAt: '2026-09-22T08:00:06Z'};
    adapter = startDiscovery({on: (name, fn) => hooks.set(name, fn)}, client,
      {port: Number(process.argv[2]), token: process.argv[3], hostID: 'turn-test'}, Promise.resolve(), clock);
    await adapter.ready;
  }
  if (command === 'busy-snapshot') {
    const list = client.agents.list;
    let release;
    const old = {...snapshot, status: 'idle', activeTurn: null};
    client.agents.list = () => new Promise(resolve => { release = resolve; });
    const reading = tick();
    update({kind: 'upsert', agent: snapshot, seq: 4, generation: 'connection-2'});
    release({entries: [{agent: old}, {agent: {...old, id: 'snapshot-branch'}}], pageInfo: {hasMore: false}});
    await reading;
    client.agents.list = list;
  }
  if (command === 'resource-recovery') {
    let pendingReads = 0;
    const releases = [];
    const context = {paseo: {agents: {ref: () => ({refresh: () => {
      pendingReads++;
      return new Promise(resolve => releases.push(resolve));
    }})}}};
    for (let i = 0; i < 1000; i++) {
      assert.equal(hooks.get('agent.turn_started')({agent: snapshot}, context), undefined);
    }
    assert.ok(pendingReads <= 200 && pendingReads > 0);
    for (const release of releases) release({agent: snapshot});
    await adapter.flush();
    const list = client.agents.list;
    client.agents.list = async () => { throw new Error('unavailable'); };
    for (let i = 0; i < 3; i++) await tick();
    assert.deepEqual(delays.slice(-3), [1500, 3000, 6000]);
    client.agents.list = list;
    await tick();
    assert.equal(delays.at(-1), 15000);
    timeline({seq: 3, event: {type: 'timeline', turnId: snapshot.activeTurn.turnId,
      item: {type: 'tool_call', name: 'browser', status: 'running'}}});
  }
  if (command === 'recovery-hazards') {
    const originalList = client.agents.list;
    let release;
    const old = {...snapshot, status: 'idle', activeTurn: null};
    client.agents.list = () => new Promise(resolve => { release = resolve; });
    const reading = tick();
    snapshot = {...snapshot, activeTurn: {turnId: 'raced-round', startedAt: snapshot.updatedAt}};
    update({kind: 'upsert', agent: snapshot, seq: 2, generation: 'connection-2'});
    release({entries: [{agent: old}], pageInfo: {hasMore: false}});
    await reading;
    client.agents.list = originalList;
    update({kind: 'upsert', agent: {...old, id: 'imported'}, seq: 3, generation: 'connection-2'});
    update({kind: 'upsert', agent: {...old, updatedAt: '2026-09-22T10:00:00Z'}, seq: 99, generation: 'connection-1'});
    timeline({seq: 2, event: {type: 'timeline', turnId: 'raced-round', item: {type: 'tool_call', name: 'edit', status: 'running'}}});
  }
  if (command === 'new-generation') {
    snapshot = {...snapshot, status: 'running', activeTurn: {turnId: 'new-generation-round', startedAt: '2026-09-22T08:00:04Z'}, updatedAt: '2026-09-22T08:00:04Z'};
    update({kind: 'upsert', agent: snapshot, seq: 1, generation: 'connection-2'});
    timeline({seq: 1, event: {type: 'timeline', turnId: 'new-generation-round', item: {type: 'tool_call', name: 'read', status: 'running'}}});
  }
  if (command === 'callback-fast') {
    let release;
    const pending = new Promise(resolve => { release = resolve; });
    const returned = hooks.get('agent.turn_started')({agent: snapshot}, {paseo: {agents: {ref: () => ({refresh: () => pending})}}});
    assert.equal(returned, undefined, 'lifecycle callback must return before slow SDK response');
    snapshot = {...snapshot, status: 'running', activeTurn: {turnId: 'fast-round', startedAt: '2026-09-22T08:00:03Z'}, updatedAt: '2026-09-22T08:00:03Z'};
    release({agent: snapshot});
  }
  if (command === 'silent-idle') {
    snapshot = {...snapshot, status: 'idle', activeTurn: null, updatedAt: '2026-09-22T08:00:02Z'};
    await tick?.();
  }
  if (command === 'silent-start') {
    snapshot = {...snapshot, status: 'running', activeTurn: {turnId: 'recovered-round', startedAt: '2026-09-22T08:00:01Z'}, updatedAt: '2026-09-22T08:00:01Z'};
    await tick?.();
  }
  if (command === 'archive') {
    update({kind: 'remove', agentId: 'imported', seq: 2, generation: 'connection-1'});
  }
  if (command === 'import') {
    update({kind: 'upsert', agent: {...snapshot, id: 'imported'}, seq: 1, generation: 'connection-1'});
  }
  if (command === 'start') {
    snapshot = {...snapshot, status: 'running', updatedAt: '2026-09-22T08:00:01.000Z',
      lastUserMessageAt: '2026-09-22T08:00:01.000Z', activeTurn: {turnId: 'round-1', startedAt: '2026-09-22T08:00:01.000Z'}};
    update({kind: 'upsert', agent: snapshot, seq: 1, generation: 'connection-1'});
    await hooks.get('agent.turn_started')?.({agent: {...snapshot, parentAgentId: null}, turnId: 'round-1'}, {paseo: client});
  }
  if (command === 'approval') {
    snapshot = {...snapshot, pendingPermissions: [{id: 'request-a', kind: 'tool', name: 'bash', title: 'secret-question', input: 'secret-tool'}], updatedAt: '2026-09-22T08:00:01.500Z'};
    await hooks.get('agent.permission_requested')?.({agent: snapshot, request: snapshot.pendingPermissions[0]}, {paseo: client});
  }
  if (['question', 'resolve-a', 'resolve-b', 'stale-resolved', 'tool-c', 'resolve-c', 'plan', 'other', 'resolve-all'].includes(command)) {
    const b = {id: 'request-b', kind: 'question', title: 'secret-question', input: {text: 'secret-tool'}};
    if (command === 'question') snapshot = {...snapshot, pendingPermissions: [...snapshot.pendingPermissions, b]};
    if (command.startsWith('resolve-')) snapshot = {...snapshot, pendingPermissions: snapshot.pendingPermissions.filter(r => r.id !== `request-${command.slice(8)}`)};
    if (command === 'tool-c') snapshot = {...snapshot, pendingPermissions: [...snapshot.pendingPermissions, {id: 'request-c', kind: 'tool'}]};
    if (command === 'plan' || command === 'other') snapshot = {...snapshot, pendingPermissions: [{id: `request-${command}`, kind: command, input: {text: 'secret-question'}}]};
    if (command === 'resolve-all') snapshot = {...snapshot, pendingPermissions: []};
    snapshot = {...snapshot, updatedAt: snapshot.activeTurn?.turnId === 'round-2' ? '2026-09-22T08:00:04.500Z' : '2026-09-22T08:00:02.000Z'};
    await hooks.get(command === 'question' ? 'agent.permission_requested' : 'agent.permission_resolved')?.(
      {agent: snapshot, request: b, requestId: command === 'resolve-b' ? b.id : 'request-a', resolution: {behavior: 'deny'}}, {paseo: client});
  }
  if (command === 'failed' || command === 'canceled') {
    snapshot = {...snapshot, status: command === 'failed' ? 'error' : 'idle', activeTurn: null,
      pendingPermissions: [], updatedAt: command === 'failed' ? '2026-09-22T08:00:03.000Z' : '2026-09-22T08:00:05.000Z'};
    if (command === 'canceled') {
      update({kind: 'upsert', agent: snapshot});
      timeline({seq: 100, event: {type: 'timeline', turnId: 'round-2',
        item: {type: 'tool_call', name: 'read', status: 'completed'}}});
    }
    for (let i = 0; i < 2; i++) await hooks.get('agent.turn_ended')?.({agent: snapshot, turnId: command === 'failed' ? 'round-1' : 'round-2',
      outcome: {kind: command, error: {message: 'secret-error'}, reason: 'secret-cancel'}}, {paseo: client});
  }
  if (command === 'refresh-race') {
    const older = {...snapshot, pendingPermissions: [{id: 'race-a', kind: 'tool'}], updatedAt: '2026-09-22T08:00:02.100Z'};
    snapshot = {...snapshot, pendingPermissions: [], updatedAt: '2026-09-22T08:00:02.200Z'};
    let release;
    const delayed = new Promise(resolve => { release = resolve; });
    const first = hooks.get('agent.permission_requested')({agent: snapshot, request: older.pendingPermissions[0]},
      {paseo: {agents: {ref: () => ({refresh: () => delayed})}}});
    let releaseNew;
    const newer = new Promise(resolve => { releaseNew = resolve; });
    const second = hooks.get('agent.permission_resolved')({agent: snapshot, requestId: 'race-a', resolution: {behavior: 'deny'}},
      {paseo: {agents: {ref: () => ({refresh: () => newer})}}});
    delayed.then(() => releaseNew({agent: snapshot}));
    release({agent: older});
    await Promise.all([first, second]);
  }
  if (command === 'tool') {
    timeline?.({agentId: 'main', timestamp: '2026-09-22T08:00:02.000Z', seq: 1, epoch: 'timeline-1',
      event: {type: 'timeline', provider: 'omp', turnId: 'round-1', item: {
        type: 'tool_call', callId: 'tool-1', name: 'read', status: 'running',
        detail: {type: 'unknown', input: 'secret-tool', output: 'secret-tool'}, error: null}}});
  }
  if (command === 'complete') {
    snapshot = {...snapshot, status: 'idle', activeTurn: null, updatedAt: '2026-09-22T08:00:03.000Z'};
    update({kind: 'upsert', agent: snapshot, seq: 2, generation: 'connection-1'});
    await tick();
    await hooks.get('agent.turn_ended')?.({agent: {...snapshot, parentAgentId: null}, turnId: 'round-1',
      outcome: {kind: 'completed'}, timeline: []}, {paseo: client});
  }
  if (command === 'next') {
    snapshot = {...snapshot, model: 'zhipu-coding-plan/glm-5.3', status: 'running',
      updatedAt: '2026-09-22T08:00:04.000Z', lastUserMessageAt: '2026-09-22T08:00:04.000Z',
      activeTurn: {turnId: 'round-2', startedAt: '2026-09-22T08:00:04.000Z'}};
    update({kind: 'upsert', agent: snapshot, seq: 3, generation: 'connection-1'});
    await hooks.get('agent.turn_started')?.({agent: {...snapshot, parentAgentId: null}, turnId: 'round-2'}, {paseo: client});
  }
  if (command === 'hazards') {
    // A higher catalog seq must not make an older round authoritative.
    update({kind: 'upsert', seq: 4, generation: 'connection-1', agent: {...snapshot,
      updatedAt: '2026-09-22T08:00:01.000Z', activeTurn: {turnId: 'round-1'}}});
    await hooks.get('agent.turn_ended')?.({agent: snapshot, turnId: 'round-1',
      outcome: {kind: 'completed'}, timeline: []}, {paseo: client});
    const child = {...snapshot, id: 'child', parentAgentId: 'main'};
    update({kind: 'upsert', agent: child, seq: 5, generation: 'connection-1'});
    await adapter.flush();
    await hooks.get('agent.created')({agent: child}, {paseo: {agents: {ref: () => ({refresh: async () => ({agent: child})})}}});
    update({kind: 'upsert', agent: child, seq: 5, generation: 'connection-1'});
    await hooks.get('agent.turn_ended')?.({agent: child, turnId: 'round-2', outcome: {kind: 'completed'}}, {paseo: client});
    const message = (seq, turnId, name, status = 'running') => ({agentId: 'main', seq,
      epoch: 'timeline-1', timestamp: '2026-09-22T08:00:05.000Z', event: {
        type: 'timeline', provider: 'omp', turnId, item: {type: 'tool_call', callId: 'call-2',
          name, status, detail: {type: 'unknown', input: 'secret-tool', output: 'secret-tool'}, error: 'secret-tool'}}});
    update({kind: 'upsert', seq: 1, generation: 'connection-1', agent: {...snapshot,
      updatedAt: '2026-09-22T08:01:00.000Z', activeTurn: {turnId: 'round-1'}}});
    timeline(message(2, 'round-2', 'bash', 'failed'));
    await adapter.flush();
    // An internal tool completion while the provider keeps working is never terminal.
    await hooks.get('agent.turn_ended')?.({agent: snapshot, turnId: 'round-2',
      outcome: {kind: 'completed'}, timeline: []}, {paseo: client});
    timeline(message(3, 'round-2', 'unknown-secret-tool'));
    await adapter.flush();
    timeline(message(4, 'round-2', 'edit'));
    timeline(message(3, 'round-2', 'read'));
    timeline(message(4, 'round-2', 'edit'));
    timeline(message(9, 'round-1', 'read'));
  }
  if (command === 'equal-time-old-round') {
    const current = snapshot;
    snapshot = {...snapshot, activeTurn: {turnId: 'round-2', startedAt: '2026-09-22T08:00:04.000Z'}};
    update({kind: 'upsert', agent: snapshot, seq: 7, generation: 'connection-1'});
    snapshot = {...snapshot, status: 'idle', activeTurn: null};
    await hooks.get('agent.turn_ended')({agent: snapshot, turnId: 'round-2', outcome: {kind: 'completed'}}, {paseo: client});
    snapshot = current;
    timeline({agentId: 'main', seq: 10, epoch: 'timeline-1', timestamp: snapshot.updatedAt,
      event: {type: 'timeline', provider: 'omp', turnId: 'round-3', item: {type: 'tool_call',
        callId: 'round3-read', name: 'read', status: 'running', detail: {type: 'unknown', input: '', output: ''}, error: null}}});
  }
  if (command === 'churn') {
    for (let i = 0; i < 201; i++) {
      snapshot = {...snapshot, id: `temporary-${i}`, status: 'idle', activeTurn: null, archivedAt: null};
      await hooks.get('agent.created')({agent: snapshot}, {paseo: client});
      update({kind: 'upsert', agent: {...snapshot, archivedAt: '2026-09-22T08:02:00Z'}});
      update({kind: 'remove', agentId: snapshot.id});
    }
    snapshot = {...snapshot, id: 'fresh', cwd: '/private/secret-path/Fresh', archivedAt: null};
    await hooks.get('agent.created')({agent: snapshot}, {paseo: client});
  }
  if (command === 'burst') {
    snapshot = {...snapshot, status: 'idle', activeTurn: null, updatedAt: '2026-09-22T08:00:06.000Z'};
    await hooks.get('agent.turn_ended')({agent: snapshot, turnId: 'round-2', outcome: {kind: 'completed'}}, {paseo: client});
    snapshot = {...snapshot, status: 'running', updatedAt: '2026-09-22T08:00:07.000Z',
      activeTurn: {turnId: 'round-3', startedAt: '2026-09-22T08:00:07.000Z'}};
    update({kind: 'upsert', agent: snapshot, seq: 6, generation: 'connection-1'});
  }
  await adapter.flush();
  if (command === 'barrier') console.log("settled");
}
await adapter.close();
