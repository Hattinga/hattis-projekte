import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const runtimeRoot = resolve(projectRoot, process.argv[2] || '.local/luau-0.747/bin');
const stagingRoot = resolve(projectRoot, '.local/p04-05-tests');
mkdirSync(stagingRoot, { recursive: true });
const sourceSha256 = {};
const readSource = (name, path) => {
  const source = readFileSync(resolve(projectRoot, path), 'utf8');
  sourceSha256[name] = createHash('sha256').update(source).digest('hex');
  return source;
};
// Only Roblox ModuleScript imports are adapted. Production source remains unchanged.
for (const name of ['State', 'Actions', 'Transfers', 'Profiles', 'Sessions']) {
  let source = readSource(name, `src/server/${name}.luau`)
    .replace(/require\(script\.Parent\.(State|Actions|Transfers|Profiles)\)/g, 'require("./$1")');
  if (name === 'State') {
    // CLI has no DataModel. Studio tests separately verify the real server-only guard.
    const guard = 'local runService = game:GetService("RunService")';
    if (!source.includes(guard)) throw new Error('State guard changed; review CLI adapter');
    source = source.replace(guard, `local game: any = {GetService=function(_: any, name: string): any
assert(name=="RunService"); return {IsServer=function(): boolean return true end}
end}\n${guard}`);
  }
  writeFileSync(resolve(stagingRoot, `${name}.luau`), source);
}
writeFileSync(resolve(stagingRoot, 'Suite.luau'), readSource('Suite', 'tools/tests/p04-05-sessions.luau'));
writeFileSync(resolve(stagingRoot, 'Runner.luau'), `--!strict
local run = require("./Suite")
local summary = run(require("./State"), require("./Profiles"), require("./Sessions"), require("./Transfers"))
for _, name in summary.passed do print("PASS\\t" .. name) end
for _, failure in summary.failures do print("FAIL\\t" .. failure.name .. "\\n" .. failure.error) end
print(string.format("TOTAL\\t%d\\t%d\\t%d", summary.total, #summary.passed, #summary.failures))
assert(#summary.failures == 0, "Session boundary test failures")
`);
const run = (name, args) => {
  const result = spawnSync(resolve(runtimeRoot, name), args, { cwd: stagingRoot, encoding: 'utf8' });
  if (result.error) throw result.error;
  return { exit: result.status, output: (result.stdout + result.stderr).trim() };
};
const analysis = run('luau-analyze.exe', ['Sessions.luau', 'Suite.luau']);
const tests = run('luau.exe', ['Runner.luau']);
const report = {
  task: 'P04-05', runtime: 'Official Luau CLI 0.747, Windows',
  method: 'Pure suite; staged copies adapt imports and stub RunService server guard only',
  status: analysis.exit === 0 && tests.exit === 0 ? 'passed-local' : 'failed',
  sourceSha256, analysis, tests, storageAccess: false, economicReady: false,
};
writeFileSync(resolve(stagingRoot, 'result.json'), JSON.stringify(report, null, 2) + '\n');
console.log(tests.output);
if (analysis.output) console.log(analysis.output);
if (report.status === 'failed') process.exitCode = 1;
