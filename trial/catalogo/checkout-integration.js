// Only this preview uses the new backend. Existing catalog URLs and local selections stay intact.
const CURRENT_GATEWAY='https://xzcwmhrdfueutareqxjw.supabase.co/functions/v1/km-current-gateway';
let currentRequest=null,creatingRequest=false;
function requestFields(){return {name:customerDetails().name,mode:deliveryMode,address:deliveryMode==='delivery'?deliveryFields():null,notes:orderNotes(),items:chosenItems().map(p=>({id:p.id,quantity:itemQuantity(p),price:p.price,brand:p.brand,model:p.model,size:p.size})),website:$('orderWebsite')?.value||''}}
async function requestFingerprint(body){const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(body)));return Array.from(new Uint8Array(bytes),v=>v.toString(16).padStart(2,'0')).join('')}
function orderMessage(code){const url=new URL(contact());url.searchParams.set('text','Solicitação K&M #'+code+'\n\n'+url.searchParams.get('text')+'\n\nSolicitação sujeita à confirmação da loja.');return url.href}
const originalReviewValidation=$('confirmOrder').onclick;
$('confirmOrder').onclick=async event=>{
 if(creatingRequest){event.preventDefault();return}
 if(!chosenItems().length)return originalReviewValidation(event);
 let invalid=false;originalReviewValidation({preventDefault(){invalid=true}});if(invalid){event.preventDefault();return}
 event.preventDefault();if($('requestWhatsApp'))$('requestWhatsApp').hidden=true;if($('newRequest'))$('newRequest').hidden=true;creatingRequest=true;$('confirmOrder').setAttribute('aria-busy','true');
 let popup=null;try{popup=window.open('about:blank','_blank');if(popup){popup.opener=null;if(popup.document){popup.document.title='K&M · Preparando sua solicitação';popup.document.body.style.cssText='margin:0;background:#000;color:#f5f7ff;font:16px/1.7 system-ui;padding:48px 24px';popup.document.body.innerHTML='<div style="max-width:400px;margin:15vh auto;border-top:2px solid #248bff;padding-top:24px"><small style="color:#248bff;letter-spacing:2px">K&M IMPORTS</small><h1 style="font-size:28px;font-weight:500">Preparando sua solicitação.</h1><p style="color:#96a4b9">Vamos abrir o WhatsApp com sua mensagem pronta. Se esta aba não avançar, volte ao catálogo para conferir.</p></div>'}}}catch{}
 try{
  const body=requestFields(),fingerprint=await requestFingerprint(body);
  let saved=null;try{saved=JSON.parse(sessionStorage.getItem('km.preview.request.v1')||'null')}catch{}
  const key=currentRequest?.fingerprint===fingerprint?currentRequest.key:saved?.fingerprint===fingerprint&&Date.now()-saved.at<86400000?saved.key:crypto.randomUUID();
  currentRequest={key,fingerprint};try{sessionStorage.setItem('km.preview.request.v1',JSON.stringify({key,fingerprint,at:Date.now()}))}catch{}
  const r=await fetch(CURRENT_GATEWAY+'/orders',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...body,key})});const result=await r.json();if(!r.ok)throw Error(result.error||'Não foi possível preparar a solicitação.');if(result.status&&result.status!=='pending'){popup?.close();checkoutGuidance('A solicitação '+result.code+' já foi encerrada. Você pode iniciar outra solicitação para estes itens.');showNewRequest();return}const previousShipping=deliveryMode==='delivery'&&currentDeliveryQuote()?.status==='quoted'?currentDeliveryQuote().feeCents/100:null;const shippingChanged=deliveryMode==='delivery'&&result.shipping!==undefined&&result.shipping!==previousShipping;
  // The returned shipping value was calculated again by the server.
  if(deliveryMode==='delivery'&&deliveryQuoteState){if(result.shipping===null){deliveryQuoteState={...deliveryQuoteState,status:'pending',feeCents:null}}else if(result.shipping!==undefined)deliveryQuoteState={...deliveryQuoteState,feeCents:Math.round(Number(result.shipping)*100)};updateDeliverySummary()}
  const url=orderMessage(result.code);$('confirmOrder').href=url;$('checkoutHelp').textContent='Solicitação '+result.code+' preparada. Envie a mensagem no WhatsApp para continuar com a loja.';
  if(shippingChanged){popup?.close();checkoutGuidance('A entrega foi conferida novamente. Revise o valor atualizado e toque em “Abrir WhatsApp” para continuar.');showWhatsAppFallback(url)}else if(popup&&!popup.closed)popup.location.replace(url);else{$('checkoutHelp').textContent='Solicitação '+result.code+' preparada. Toque em “Abrir WhatsApp” abaixo para enviar a mensagem.';showWhatsAppFallback(url)}
 }catch(error){popup?.close();checkoutGuidance(error.message||'Não foi possível preparar a solicitação. Tente novamente.');diagnostic('whatsapp_link')}
 finally{creatingRequest=false;$('confirmOrder').removeAttribute('aria-busy')}
};
function showWhatsAppFallback(url){let link=$('requestWhatsApp');if(!link){link=document.createElement('a');link.id='requestWhatsApp';link.className='primary';link.target='_blank';link.rel='noopener';link.textContent='Abrir WhatsApp ↗';$('checkoutHelp').after(link)}link.href=url;link.hidden=false}
// Refresh only while visible; selection reconciliation uses current prices and availability.
setInterval(async()=>{if(document.hidden||creatingRequest||$('summaryDialog').open)return;try{data=await api('/api/catalog');render()}catch{}},30000);

function showNewRequest(){let button=$('newRequest');if(!button){button=document.createElement('button');button.type='button';button.id='newRequest';button.className='secondary';button.textContent='Iniciar outra solicitação';$('checkoutHelp').after(button);button.onclick=()=>{currentRequest=null;try{sessionStorage.removeItem('km.preview.request.v1')}catch{}button.hidden=true;checkoutGuidance('Confira a sacola e confirme novamente para preparar uma nova solicitação.')}}button.hidden=false}
const originalClearChoices=$('clearChoices').onclick;$('clearChoices').onclick=()=>{originalClearChoices();currentRequest=null;try{sessionStorage.removeItem('km.preview.request.v1')}catch{}if($('requestWhatsApp'))$('requestWhatsApp').hidden=true;if($('newRequest'))$('newRequest').hidden=true};
