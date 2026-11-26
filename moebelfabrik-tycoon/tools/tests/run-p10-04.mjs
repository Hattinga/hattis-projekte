import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const runtime=resolve(root,process.argv[2]||'.local/luau-0.747/bin');
const staging=resolve(root,'.local/p10-04-tests/run');
mkdirSync(staging,{recursive:true});
const hashes={};
function source(name,path){const s=readFileSync(resolve(root,path),'utf8');hashes[name]=createHash('sha256').update(s).digest('hex');return s;}
// Overview reads Line, which pulls in the station and persistence modules; the suite itself only builds plain profiles.
const modules=['Recipes','State','Actions','Transfers','Profiles','Sessions','Persistence','Equipment','Stations','Line','Purchases','Overview'];
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
writeFileSync(resolve(staging,'Suite.luau'),source('Suite','tools/tests/p10-04-equipment.luau'));
writeFileSync(resolve(staging,'Runner.luau'),`--!strict
local run=require("./Suite")
local summary=run(require("./State"),require("./Persistence"),require("./Stations"),require("./Line"),require("./Purchases"),require("./Recipes"),require("./Profiles"),require("./Equipment"),require("./Overview"))
for _,name in summary.passed do print("PASS\\t"..name) end
for _,failure in summary.failures do print("FAIL\\t"..failure.name.."\\n"..failure.error) end
print(string.format("TOTAL\\t%d\\t%d\\t%d",summary.total,#summary.passed,#summary.failures))
assert(#summary.failures==0,"Overview test failure")
`);
function run(exe,args){const r=spawnSync(resolve(runtime,exe),args,{cwd:staging,encoding:'utf8'});if(r.error)throw r.error;return {exit:r.status,output:(r.stdout+r.stderr).trim()};}
const analysis=run('luau-analyze.exe',[...modules.map(n=>n+'.luau'),'Suite.luau']);
const tests=run('luau.exe',['Runner.luau']);
const report={task:'P10-04',runtime:'Official Luau CLI 0.747 Windows',sourceSha256:hashes,analysis,tests,
 status:analysis.exit===0&&tests.exit===0?'passed-local':'failed',
 method:'ModuleScript import adaptation plus CLI-only RunService server stub; in-memory atomic backend',storageAccess:false};
writeFileSync(resolve(staging,'result.json'),JSON.stringify(report,null,2)+'\n');
console.log(tests.output);if(analysis.output)console.log(analysis.output);
if(report.status==='failed')process.exitCode=1;
