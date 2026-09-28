import { test } from 'node:test';
import { doesNotThrow, throws } from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { assertPluginCompatibility } from '@getpaseo/protocol/plugin-requirements';

const manifest = JSON.parse(readFileSync(new URL('../paseo-plugin.json', import.meta.url), 'utf8'));
const check = version => assertPluginCompatibility({ ...manifest, version, runtime: 'daemon' });

test('Paseo accepts the monitor on all explicitly supported daemon releases', () => {
  doesNotThrow(() => check('0.8.0'));
  doesNotThrow(() => check('0.9.1'));
  doesNotThrow(() => check('0.9.2'));
});

test('unknown releases remain gated until their contract is verified', () => {
  throws(() => check('0.7.0'));
  throws(() => check('0.10.0'));
});
