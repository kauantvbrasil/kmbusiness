// Public catalog/requests only. Administrative RPCs retain the caller's Supabase session.
const ALLOWED=new Set(['https://kmimportsz.github.io']);
const SUPABASE_URL=Deno.env.get('SUPABASE_URL')!;
const SERVICE=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const DELIVERY='https://km-camisetas-catalogo.inventivetoucan16.chatgpt.site';
const budgets=new Map<string,{at:number,n:number}>();
function limited(key:string){const now=Date.now();let r=budgets.get(key);if(!r||now-r.at>60000){r={at:now,n:0};budgets.set(key,r)}if(budgets.size>2000)budgets.delete(budgets.keys().next().value!);return ++r.n>120}
function reply(req:Request,body:unknown,status=200){const origin=req.headers.get('origin')||'';return new Response(body===null?null:JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':ALLOWED.has(origin)?origin:'https://kmimportsz.github.io','access-control-allow-methods':'GET, POST, OPTIONS','access-control-allow-headers':'Content-Type, apikey, authorization','vary':'Origin'}})}
async function rpc(name:string,args:unknown){const res=await fetch(SUPABASE_URL+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:SERVICE,authorization:'Bearer '+SERVICE,'content-type':'application/json'},body:JSON.stringify(args)});const data=await res.json();if(!res.ok)throw Error(data.message||'Não foi possível concluir agora.');return data}
async function hmac(value:string){const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(SERVICE),{name:'HMAC',hash:'SHA-256'},false,['sign']);const bytes=await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(value));return Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('')}
async function delivery(path:string,body?:unknown){const r=await fetch(DELIVERY+path,{method:body?'POST':'GET',headers:body?{'content-type':'application/json'}:{},...(body?{body:JSON.stringify(body)}:{})});const data=await r.json();if(!r.ok)throw Error('Não foi possível conferir a entrega.');return data}
Deno.serve(async(req:Request)=>{try{
 const origin=req.headers.get('origin');if(origin&&!ALLOWED.has(origin))return reply(req,{error:'Origem não permitida.'},403);
 if(req.method==='OPTIONS')return reply(req,null,204);
 const u=new URL(req.url),path=u.pathname.replace(/^.*\/km-current-gateway/,'');
 if(req.method==='GET'&&path==='/catalog')return reply(req,await rpc('kmuv2_public_catalog',{}));
 if(req.method==='GET'&&path==='/delivery/cep')return reply(req,await delivery('/api/delivery/cep?cep='+encodeURIComponent(u.searchParams.get('cep')||'')));
 if(req.method!=='POST')return reply(req,{error:'Solicitação inválida.'},405);
 if(!req.headers.get('content-type')?.startsWith('application/json'))return reply(req,{error:'Formato inválido.'},415);
 const raw=await req.text();if(raw.length>16384)return reply(req,{error:'Solicitação muito grande.'},413);
 let b;try{b=JSON.parse(raw)}catch{return reply(req,{error:'Formato inválido.'},400)}
 if(!b||typeof b!=='object')return reply(req,{error:'Solicitação inválida.'},400);
 const ip=(req.headers.get('x-forwarded-for')||'unknown').split(',')[0].trim();const rate=await hmac(ip);
 if(limited(rate))return reply(req,{error:'Aguarde um instante antes de tentar novamente.'},429);
 if(path==='/delivery/quote')return reply(req,await delivery('/api/delivery/quote',b));
 if(path==='/events'){
  if(!Array.isArray(b.events)||b.events.length>20||raw.length>6000||!/^[a-f0-9-]{36}$/i.test(b.batchId||''))return reply(req,{error:'Eventos inválidos.'},400);
  const session=typeof b.session==='string'&&/^[a-f0-9-]{36}$/i.test(b.session)?b.session:'';
  await rpc('kmuv2_event_batch',{p:{batchId:b.batchId,consent:b.consent===true,visitor:session?await hmac(new Date().toISOString().slice(0,10)+':'+session):null,events:b.events}});return reply(req,{ok:true},202);
 }
 if(path==='/orders'){
  if(b.website||!Array.isArray(b.items)||b.items.length<1||b.items.length>30||!/^[a-f0-9-]{36}$/i.test(b.key||''))return reply(req,{error:'Revise a solicitação.'},400);
  const address=b.mode==='delivery'?{cep:String(b.address?.cep||'').replace(/\D/g,''),street:String(b.address?.street||'').trim().slice(0,180),number:String(b.address?.number||'').trim().slice(0,20),reference:String(b.address?.reference||'').trim().slice(0,180)}:null;
  const p={key:b.key,name:String(b.name||'').trim().slice(0,120),mode:b.mode,notes:String(b.notes||'').trim().slice(0,500),address,items:b.items.map((x:any)=>({id:x.id,quantity:x.quantity,price:x.price,brand:String(x.brand||''),model:String(x.model||''),size:String(x.size||'')})),shipping:b.mode==='pickup'?0:null as number|null};
  // Never trust a shipping price sent by a browser. Recalculate on the private-origin server.
  if(address){try{const quote=await delivery('/api/delivery/quote',address);if(quote.status==='quoted')p.shipping=quote.feeCents/100}catch{p.shipping=null}}
  return reply(req,await rpc('kmuv2_create_order',{p,p_rate:rate}),201);
 }
 return reply(req,{error:'Solicitação inválida.'},404);
}catch(error){const text=error instanceof Error?error.message:'';return reply(req,{error:text&&text.length<240?text:'Não foi possível concluir agora. Tente novamente.'},400)}});
