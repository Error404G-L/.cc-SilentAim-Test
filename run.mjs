import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { LuauState } from 'luau-web';

const source = await readFile(new URL('../silent-aim.lua', import.meta.url), 'utf8');
const mock = await readFile(new URL('./mock.luau', import.meta.url), 'utf8');
const spec = await readFile(new URL('./spec.luau', import.meta.url), 'utf8');
assert(!source.includes('--'), 'The delivered script must not contain comments');
assert(!/[^\x00-\x7f]/.test(source), 'The delivered script must contain ASCII only');
assert(!/HttpGet|loadstring|FireServer|writefile|readfile/.test(source), 'Unexpected network or filesystem dependency');
const state = await LuauState.createAsync({ print: console.log, warn: () => {} });
try {
  state.loadstring(source, 'silent-aim.lua', true);
  console.log('PASS Luau compilation, no comments, ASCII, no remote loaders');
  const run = state.loadstring(`${mock}\nlocal function launch()\n${source}\nend\n${spec}`, 'behavior-tests', true);
  await run();
} finally {
  state.destroy();
}
