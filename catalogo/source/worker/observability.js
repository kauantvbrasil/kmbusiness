// Minimal, first-party telemetry. No IP, address, customer text or credentials are persisted.
const ORIGINS=new Set(['https://kmimportsz.github.io','https://km-camisetas-catalogo.inventivetoucan16.chatgpt.site']);
const KINDS=new Set(['visit','product_view','bag_add','category','search','checkout']);
export const ERROR_CODES={catalog_load:['Carregamento','Falha ao carregar o catálogo'],catalog_save:['Sincronização','Falha ao salvar alterações'],photo_upload:['Fotos','Falha ao enviar foto'],delivery_quote:['Entrega','Falha ao consultar frete'],delivery_pending:['Entrega','Frete ficou para confirmação manual'],postcode_lookup:['Entrega','Falha ao consultar CEP'],checkout_refresh:['Sacola','Falha ao conferir a sacola'],whatsapp_link:['WhatsApp','Falha ao preparar o link'],javascript:['Interface','Erro inesperado de JavaScript'],promise:['Interface','Operação assíncrona não concluída']};
const UUID=/^[a-f0-9-]{36}$/i;
const budgets=new Map();
function allowed(key,limit=120){const now=Date.now();let v=budgets.get(key);if(!v||now-v.start>3600000){v={start:now,n:0};budgets.set(key,v)}if(budgets.size>2000)budgets.delete(budgets.keys().next().value);return ++v.n<=limit}
function response(r,v,status=200){const origin=r.headers.get('origin');return new Response(v===null?null:JSON.stringify(v),{status,headers:{'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':ORIGINS.has(origin)?origin:'https://kmimportsz.github.io','access-control-allow-methods':'GET, POST, OPTIONS','access-control-allow-headers':'Content-Type','vary':'Origin'}})}
export function safeSearchTerms(products){const terms=new Set();for(const p of products)for(const text of [p.brand,p.model]){const s=String(text||'').toLocaleLowerCase('pt-BR').trim();if(s&&s.length<=60)terms.add(s);for(const t of s.split(/[^\p{L}\p{N}]+/u))if(t.length>=2&&t.length<=30)terms.add(t)}return terms}
const dayAt=t=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(t));
async function visitorHash(id,day){const b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(day+':'+id));return Array.from(new Uint8Array(b),n=>n.toString(16).padStart(2,'0')).join('').slice(0,24)}
async function readCatalog(e){const obj=await e.BUCKET.get('catalog.json');return obj?await obj.json():{products:[]}}
async function receive(r,e){
 if(r.headers.get('content-type')?.split(';')[0]!=='application/json')return response(r,{error:'Formato inválido'},415);
 const raw=await r.text();if(raw.length>6000)return response(r,{error:'Solicitação muito grande'},413);
 let b;try{b=JSON.parse(raw)}catch{return response(r,{error:'JSON inválido'},400)}
 if(!b||typeof b!=='object'||!UUID.test(b.batchId)||!Array.isArray(b.events)||!b.events.length||b.events.length>20)return response(r,{error:'Eventos inválidos'},400);
 if(!allowed(b.session||b.batchId)||!allowed('total',10000))return response(r,{error:'Limite temporário'},429);
 const now=Date.now(),day=dayAt(now),hour=Number(new Intl.DateTimeFormat('en-GB',{timeZone:'America/Sao_Paulo',hour:'2-digit',hourCycle:'h23'}).format(new Date(now)));
 const catalog=await readCatalog(e),products=new Map(catalog.products.map(p=>[p.id,p])),terms=safeSearchTerms(catalog.products),brands=new Set(catalog.products.map(p=>p.brand));
 const analytic=b.consent===true&&UUID.test(b.session),events=[];
 for(const item of b.events){
  if(!item||typeof item!=='object')continue;
  if(item.type==='error'&&Object.hasOwn(ERROR_CODES,item.code)){events.push({type:'error',code:item.code});continue}
  if(!analytic||!KINDS.has(item.type))continue;
  if(['product_view','bag_add'].includes(item.type)){if(products.has(item.productId))events.push({type:item.type,productId:item.productId});continue}
  if(item.type==='category'){if(['all','bestSellers','budget','newArrivals'].includes(item.category)||brands.has(item.category))events.push({type:'category',category:item.category});continue}
  if(item.type==='search'){const term=typeof item.term==='string'?item.term.toLocaleLowerCase('pt-BR').trim():'';events.push({type:'search',term:terms.has(term)?term:null});continue}
  events.push({type:item.type});
 }
 if(!events.length)return response(r,{ok:true},202);
 const key='telemetry/events/'+day+'/'+b.batchId+'.json';if(await e.BUCKET.head(key))return response(r,{ok:true},202);
 await e.BUCKET.put(key,JSON.stringify({version:1,at:now,day,hour,visitor:analytic?await visitorHash(b.session,day):null,events}),{httpMetadata:{contentType:'application/json'}});
 return response(r,{ok:true},202);
}
async function listRange(bucket,start,end){let cursor,keys=[],truncated=false;do{const page=await bucket.list({prefix:'telemetry/events/',startAfter:'telemetry/events/'+start+'/',limit:500,...(cursor?{cursor}:{})});for(const o of page.objects){const day=o.key.slice(17,27);if(day>=start&&day<=end)keys.push(o.key);if(day>end)return {keys,truncated:false}}cursor=page.truncated?page.cursor:null;if(keys.length>=2000){truncated=!!cursor;break}}while(cursor);return {keys,truncated}}
const increment=(o,k)=>{o[k]=(o[k]||0)+1};
export async function report(e,days=7){
 const today=dayAt(Date.now()),start=dayAt(Date.now()-(days-1)*86400000);const {keys,truncated}=await listRange(e.BUCKET,start,today);
 const visitors=new Set(),checkoutVisitors=new Set(),views={},adds={},categories={},search={},daily={},hours=Array(24).fill(0),weekdays=Array(7).fill(0),diagnostics={};let productViews=0,checkoutClicks=0,otherSearches=0;
 for(let i=0;i<keys.length;i+=20){const rows=await Promise.all(keys.slice(i,i+20).map(async k=>{const o=await e.BUCKET.get(k);return o?await o.json():null}));for(const row of rows){if(!row)continue;for(const item of row.events||[]){if(item.type==='error'){const d=diagnostics[item.code]??={code:item.code,area:ERROR_CODES[item.code]?.[0]||'Interface',description:ERROR_CODES[item.code]?.[1]||'Falha',count:0,first:row.at,last:row.at};d.count++;d.first=Math.min(d.first,row.at);d.last=Math.max(d.last,row.at);continue}if(!row.visitor)continue;const day=daily[row.day]??={day:row.day,visitors:new Set(),views:0,checkouts:0};visitors.add(row.day+':'+row.visitor);day.visitors.add(row.visitor);hours[row.hour]++;weekdays[new Date(row.day+'T12:00:00Z').getUTCDay()]++;
 if(item.type==='product_view'){productViews++;increment(views,item.productId);day.views++}if(item.type==='bag_add')increment(adds,item.productId);if(item.type==='category')increment(categories,item.category);if(item.type==='search'){if(item.term)increment(search,item.term);else otherSearches++}if(item.type==='checkout'){checkoutClicks++;checkoutVisitors.add(row.day+':'+row.visitor);day.checkouts++}
 }}}
 for(const d of Object.values(diagnostics)){const obj=await e.BUCKET.get('telemetry/status/'+d.code+'.json');const status=obj?await obj.json():null;d.resolvedAt=status?.resolvedAt||null;d.status=d.resolvedAt&&d.resolvedAt>=d.last?'resolved':'open'}
 const catalog=await readCatalog(e),products=new Map(catalog.products.map(p=>[p.id,p]));const ranked=(o,kind)=>Object.entries(o).sort((a,b)=>b[1]-a[1]).slice(0,10).map(([key,count])=>({label:kind==='product'?(products.has(key)?products.get(key).brand+' · '+products.get(key).model:'Modelo removido'):key,count}));
 return {days,start,end:today,limited:truncated,visits:visitors.size,productViews,checkoutClicks,conversion:visitors.size?Math.round(checkoutVisitors.size/visitors.size*1000)/10:0,viewClickRate:productViews?Math.round(checkoutClicks/productViews*1000)/10:0,topViews:ranked(views,'product'),topAdds:ranked(adds,'product'),topCategories:ranked(categories),topSearches:ranked(search),otherSearches,daily:Object.values(daily).map(d=>({...d,visitors:d.visitors.size})).sort((a,b)=>a.day.localeCompare(b.day)),hours,weekdays,diagnostics:Object.values(diagnostics).sort((a,b)=>b.last-a.last)};
}
// Bounded lazy retention: expired data is excluded immediately and purged on admin reports.
async function prune(bucket){const cutoff=dayAt(Date.now()-90*86400000);const page=await bucket.list({prefix:'telemetry/events/',limit:500});const old=page.objects.filter(o=>o.key.slice(17,27)<cutoff);if(old.length)await bucket.delete(old.map(o=>o.key))}
export async function observabilityEndpoint(r,e,admin,ctx){
 const u=new URL(r.url),origin=r.headers.get('origin');if(origin&&!ORIGINS.has(origin)&&origin!==u.origin)return response(r,{error:'Origem não permitida'},403);
 if(r.method==='OPTIONS')return response(r,null,204);
 if(u.pathname==='/api/telemetry'&&r.method==='POST'){try{return await receive(r,e)}catch{return response(r,{error:'Métricas temporariamente indisponíveis'},503)}}
 if(!admin)return response(r,{error:'Acesso restrito'},401);
 if(u.pathname==='/api/insights'&&r.method==='GET'){const n=Number(u.searchParams.get('days')||7);if(![7,30,90].includes(n))return response(r,{error:'Período inválido'},400);const result=await report(e,n);if(ctx?.waitUntil)ctx.waitUntil(prune(e.BUCKET).catch(()=>{}));return response(r,result)}
 if(u.pathname==='/api/diagnostics/status'&&r.method==='POST'){if(origin!==u.origin)return response(r,{error:'Origem inválida'},403);let b;try{const raw=await r.text();if(raw.length>300)return response(r,{error:'Solicitação inválida'},400);b=JSON.parse(raw)}catch{return response(r,{error:'Solicitação inválida'},400)}if(!Object.hasOwn(ERROR_CODES,b.code))return response(r,{error:'Código inválido'},400);await e.BUCKET.put('telemetry/status/'+b.code+'.json',JSON.stringify({resolvedAt:b.resolved?Date.now():null}));return response(r,{ok:true})}
 return response(r,{error:'Solicitação inválida'},405);
}
