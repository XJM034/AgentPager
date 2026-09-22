// Controlled upstream SDK/lifecycle boundary; production adapter and TCP transport are real.
import { startDiscovery } from '../server/discovery.mjs';
const port = Number(process.argv[2]);
const token = process.argv[3];
const callbacks = new Map();
const agent = (id, overrides = {}) => ({
  id, provider: 'omp', cwd: '/private/sensitive-parent/AgentPager',
  title: 'implement secret-prompt-value', status: 'idle', archivedAt: null,
  model: 'codex', ...overrides,
});
const server = { on: (event, handler) => callbacks.set(event, handler) };
let listener;
const refreshCounts = new Map();
const client = {
  agents: {
    subscribe: (handler) => { listener = handler; return () => { listener = undefined; }; },
    list: async (options) => options.page.cursor ? ({ entries: [{ agent: agent('initial') }],
      pageInfo: { hasMore: false, nextCursor: null } }) : ({ entries: [
      { agent: agent('initial') },
      { agent: agent('archived', { archivedAt: '2026-01-01' }) },
      { agent: agent('native', { provider: 'codex' }) },
      { agent: agent('closed-history', { status: 'closed' }) },
    ], pageInfo: { hasMore: true, nextCursor: 'page-two' } }),
    ref: (id) => ({ refresh: async () => {
      const count = refreshCounts.get(id) ?? 0;
      refreshCounts.set(id, count + 1);
      return { agent: agent(id, {
        model: count ? 'glm' : 'codex',
        ...(id === 'another-project' ? { cwd: '/private/other/ProjectB' } : {}),
      }) };
    } }),
  },
};
const connection = startDiscovery(server, client, { port, token, hostID: 'fixture-host' });
await connection.ready;
listener({ kind: 'upsert', agent: agent('created', { status: 'initializing' }) });
await connection.flush();
await Promise.all([
  callbacks.get('agent.created')({ agent: agent('created') }, { paseo: client }),
  callbacks.get('agent.created')({ agent: agent('created', { model: 'glm' }) }, { paseo: client }),
  callbacks.get('agent.created')({ agent: agent('another-project', { cwd: '/private/other/ProjectB' }) }, { paseo: client }),
  callbacks.get('agent.created')({ agent: agent('native-created', { provider: 'claude' }) }, { paseo: client }),
]);
await connection.flush();
await connection.close();
