import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
const prefix=execFileSync('git',['rev-parse','--show-prefix'],{encoding:'utf8'}).trim();
const oldBanner='<div class="art" aria-hidden="true"><div class="orbit"></div><div class="monogram">K<span>&</span>M</div><div class="art-label">CURADORIA K&M / SELEÇÃO ESPECIAL</div></div>';
for(const path of ['public/catalogo.html','worker/index.js']){
 const original=execFileSync('git',['show','catalogo-before-premium-ui-3:'+prefix+path],{encoding:'utf8'});
 const current=fs.readFileSync(path,'utf8');
 const restored=current.replace(/<!-- km-premium-style:start -->[\s\S]*?<!-- km-premium-style:end -->/g,'').replace(/<!-- km-premium-script:start -->[\s\S]*?<!-- km-premium-script:end -->/g,'').replace(/<!-- km-premium-banner:start -->[\s\S]*?<!-- km-premium-banner:end -->/g,oldBanner);
 assert.equal(restored,original,path+': functional code and original document must remain byte-identical after stripping visual additions');
 for(const match of current.matchAll(/<script>([\s\S]*?)<\/script>/g))new vm.Script(match[1]);
}
for(const path of ['worker/observability.js','.openai/hosting.json','scripts/build.mjs','public/catalogoadm.html','package.json']){
 assert.equal(fs.readFileSync(path,'utf8'),execFileSync('git',['show','catalogo-before-premium-ui-3:'+prefix+path],{encoding:'utf8'}),path+' must remain unchanged');
}
console.log('Preservation verified: original UI handlers, requests, auth, data processing, metrics, build and hosting configuration unchanged; scripts parse.');
