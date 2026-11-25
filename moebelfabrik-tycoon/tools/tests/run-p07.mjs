import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const runtime=resolve(root,process.argv[2]||'.local/luau-0.747/bin');
const staging=resolve(root,'.local/p07-tests/run');
mkdirSync(staging,{recursive:true});
const hashes={};
function source(name,path){const s=readFileSync(resolve(root,path),'utf8');hashes[name]=createHash('sha256').update(s).digest('hex');return s;}
const modules=['Recipes','State','Actions','Transfers','Profiles','Sessions','Persistence','Purchases','Sales'];
for(const name of modules){
 let s=source(name,`src/server/${name}.luau`).replace(/require\(script\.Parent\.(\w+)\)/g,'require("./$1")');
 if(name==='State'){
  const guard='local runService = game:GetService("RunService")';
  if(!s.includes(guard))throw Error('Review changed State guard');
  s=s.replace(guard,`local game: any={GetService=function(_: any,n: string): any assert(n=="RunService");return {IsServer=function(): boolean return true end} end}\n${guard}`);
 }
 if(name==='Persistence')s=s.replace('--!strict','--!strict\nlocal Instance: any=nil -- CLI: engine wrapper is checked separately in Studio.');
 if(name==='Purchases')s=s.replace('--!strict','--!strict\ntype Instance = any\ntype Attachment = any');
 writeFileSync(resolve(staging,name+'.luau'),s);
}
writeFileSync(resolve(staging,'Suite.luau'),source('Suite','tools/tests/p07-sales.luau'));
writeFileSync(resolve(staging,'AdvanceSuite.luau'),source('AdvanceSuite','tools/tests/p07-07-advance.luau'));
writeFileSync(resolve(staging,'Runner.luau'),`--!strict
local State = require("./State")
local Transfers = require("./Transfers")
local Persistence = require("./Persistence")
local Purchases = require("./Purchases")
local Sales = require("./Sales")
local salesSuite = require("./Suite")
local advanceSuite = require("./AdvanceSuite")
local failed = 0
for _, suite in {{name = "Sales", run = salesSuite}, {name = "Material advance", run = advanceSuite}} do
 local summary = suite.run(State, Transfers, Persistence, Purchases, Sales)
 print(suite.name)
 for _, name in summary.passed do print("PASS\\t" .. name) end
 for _, failure in summary.failures do print("FAIL\\t" .. failure.name .. "\\n" .. failure.error) end
 print(string.format("TOTAL\\t%d\\t%d\\t%d", summary.total, #summary.passed, #summary.failures))
 failed += #summary.failures
end
assert(failed == 0, "P07 test failure")
`);
function run(exe,args){const r=spawnSync(resolve(runtime,exe),args,{cwd:staging,encoding:'utf8'});if(r.error)throw r.error;return {exit:r.status,output:(r.stdout+r.stderr).trim()};}
const analysis=run('luau-analyze.exe',[...modules.map(n=>n+'.luau'),'Suite.luau','AdvanceSuite.luau']);
const tests=run('luau.exe',['Runner.luau']);
const report={task:'P07',runtime:'Official Luau CLI 0.747 Windows',sourceSha256:hashes,analysis,tests,
 status:analysis.exit===0&&tests.exit===0?'passed-local':'failed',
 method:'ModuleScript import adaptation plus CLI-only RunService server stub; in-memory atomic backend',storageAccess:false};
writeFileSync(resolve(staging,'result.json'),JSON.stringify(report,null,2)+'\n');
console.log(tests.output);if(analysis.output)console.log(analysis.output);
if(report.status==='failed')process.exitCode=1;
