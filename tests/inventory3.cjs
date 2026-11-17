const {JSDOM}=require('jsdom'),fs=require('fs'),assert=require('assert');
const root=require('path').resolve(__dirname,'..')+'/';
const dom=new JSDOM(fs.readFileSync(root+'index.html','utf8'),{url:'https://kmimportsz.github.io/kmbusiness/',runScripts:'outside-only',pretendToBeVisual:true});
const vm=require('vm'),run=code=>vm.runInContext(code,dom.getInternalVMContext());
const w=dom.window,d=w.document;const runtimeErrors=[];w.addEventListener('error',e=>runtimeErrors.push(e.error));w.HTMLElement.prototype.scrollIntoView=()=>{};w.HTMLElement.prototype.scrollIntoView=()=>{};w.scrollTo=()=>{};w.alert=msg=>{throw Error('Unexpected alert: '+msg)};w.confirm=()=>true;w.console.error=()=>{};
for(const s of d.querySelectorAll('script:not([src])'))run(s.textContent);
run(`S.products=[{id:'p1',name:'Produto Azul',brand:'Marca',model:'Modelo',flavor:'Azul',stock:5,cost:40,price:100}];S.sales=[{id:'sale1',pid:'p1',name:'Produto Azul',client:'Maria Silva',phone:'11912345678',date:today(),price:100,cost:40,inst:[{v:100,d:today(),paid:false}]}];S.config=[];`);
run(fs.readFileSync(root+'central.js','utf8'));run(fs.readFileSync(root+'business3.js','utf8'));run(fs.readFileSync(root+'inventory3.js','utf8'));
const click=(action,id='')=>{const b=[...d.querySelectorAll('[data-cx-action]')].find(b=>b.dataset.cxAction===action&&b.dataset.cxId===id);assert(b,action+' '+id+' exists');b.click();};
const set=(id,value)=>{d.getElementById(id).value=value;};const flush=()=>new Promise(r=>setTimeout(r,10));
const submit=()=>d.getElementById('cxForm').dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));
const stockClick=action=>{const b=d.querySelector(`[data-stock="${action}"]`);assert(b,action+' exists');b.click();};
const submitStock=()=>d.getElementById('stockForm').dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));
(async()=>{
 run("S.products.push({id:'p2',name:'Produto Verde',stock:2,cost:20,price:50});go('prod')");
 stockClick('inbound');set('stockP0','p1');d.getElementById('stockP0').dispatchEvent(new w.Event('change',{bubbles:true}));set('stockQ0','10');set('stockC0','45');stockClick('add');set('stockP1','p2');set('stockQ1','5');set('stockC1','25');set('stockReason','Reposição 001');submitStock();await flush();assert.equal(run('S.products[0].stock'),15);assert.equal(run('S.products[1].stock'),7);assert.equal(run('S.products[0].cost'),45);assert.equal(run('S.expenses.length'),0);assert.equal(run('S.config.filter(x=>x.type==="b3-stock-operation").length'),1);
 stockClick('count');set('stockProduct','p1');d.getElementById('stockProduct').dispatchEvent(new w.Event('change'));set('stockFound','14');set('stockReason','Uma unidade danificada');submitStock();await flush();assert.equal(run('S.products[0].stock'),14);stockClick('ledger');assert(d.getElementById('modal').textContent.includes('Uma unidade danificada'));stockClick('close');
 // Simulate a cloud commit whose response is lost. Retry must not add stock twice.
 const state=new Map();state.set('products/p1',JSON.parse(JSON.stringify(run('S.products[0]'))));state.set('products/p2',JSON.parse(JSON.stringify(run('S.products[1]'))));let loseResponse=true;
 w.firebase={};w.mockDb={collection:c=>({doc:id=>({path:c+'/'+id})}),runTransaction:async callback=>{const writes=[];await callback({get:async ref=>({exists:state.has(ref.path),data:()=>JSON.parse(JSON.stringify(state.get(ref.path)))}),set:(ref,value)=>writes.push([ref.path,JSON.parse(JSON.stringify(value))])});writes.forEach(([path,value])=>state.set(path,value));if(loseResponse){loseResponse=false;throw Error('Resposta de rede perdida');}}};run('db=window.mockDb;cloudOn=true;ready.products=true;ready.config=true');
 stockClick('inbound');set('stockP0','p1');set('stockQ0','3');set('stockC0','45');set('stockReason','Reposição com tentativa repetida');submitStock();await flush();assert.equal(state.get('products/p1').stock,17);assert(d.getElementById('stockFeedback').textContent.includes('rede perdida'));assert.equal(d.getElementById('stockQ0').value,'3');submitStock();await flush();assert.equal(state.get('products/p1').stock,17);assert.equal(run('S.products[0].stock'),17);assert.equal([...state.values()].filter(v=>v.type==='b3-stock-operation').length,1);
 // Count conflicts must fail rather than overwrite a sale made during the physical count.
 stockClick('count');set('stockProduct','p1');d.getElementById('stockProduct').dispatchEvent(new w.Event('change'));set('stockFound','16');set('stockReason','Contagem divergente');state.get('products/p1').stock=15;submitStock();await flush();assert(d.getElementById('stockFeedback').textContent.includes('estoque mudou'));assert.equal(state.get('products/p1').stock,15);assert.equal(d.getElementById('stockFound').value,'16');
 console.log('PASS: batch stock entry, per-product cost, no duplicate expense, physical count with reason, movement ledger, transaction retry without duplicate stock, conflicting count rejected.');
assert.equal(runtimeErrors.length,0,runtimeErrors.map(e=>e.message).join('; '));
})().catch(e=>{console.error(e);process.exitCode=1});
