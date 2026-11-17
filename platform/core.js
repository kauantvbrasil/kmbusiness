/* Generic technical services only: no business mutations, remote calls or order automation. */
(function(root){
'use strict';
const DATA_ARRAYS=['products','sales','expenses','closings','config','proofs','catalog','cphotos'];
const CODES=new Set(['javascript','promise','offline','download','backup_invalid','backup_export','storage']);
const records=[];
function record(code){if(!CODES.has(code))return;const at=new Date().toISOString(),last=records.find(r=>r.code===code);if(last){last.count++;last.last=at}else{records.push({code,count:1,first:at,last:at});if(records.length>20)records.shift()}}
function diagnostics(){return records.map(row=>({...row}))}
function validateState(state){if(!state||typeof state!=='object'||Array.isArray(state)||!Array.isArray(state.products)||!Array.isArray(state.sales))throw Error('A cópia precisa conter listas de produtos e registros.');for(const key of DATA_ARRAYS){if(state[key]!==undefined&&!Array.isArray(state[key]))throw Error('Lista inválida na cópia: '+key);if(Array.isArray(state[key])&&state[key].some(row=>!row||typeof row!=='object'||Array.isArray(row)))throw Error('Formato de registro inválido: '+key)}return state}
async function checksum(text){if(!root.crypto?.subtle||typeof TextEncoder==='undefined')throw Error('A verificação segura não está disponível neste navegador.');const bytes=await root.crypto.subtle.digest('SHA-256',new TextEncoder().encode(text));return Array.from(new Uint8Array(bytes),v=>v.toString(16).padStart(2,'0')).join('')}
async function createBackup(state){validateState(state);const snapshot=JSON.parse(JSON.stringify(state));const digest=await checksum(JSON.stringify(snapshot));return {format:'km-business-backup',version:1,createdAt:new Date().toISOString(),algorithm:'SHA-256',checksum:digest,data:snapshot}}
async function inspectBackup(text){if(typeof text!=='string'||text.length>100*1024*1024)throw Error('Arquivo inválido ou maior que 100 MB.');let parsed;try{parsed=JSON.parse(text)}catch{throw Error('O arquivo não contém JSON válido.')}let state,verified=false;if(parsed?.format==='km-business-backup'){if(parsed.version!==1||parsed.algorithm!=='SHA-256'||!/^[a-f0-9]{64}$/.test(parsed.checksum||''))throw Error('Formato de cópia não suportado.');state=validateState(parsed.data);if(await checksum(JSON.stringify(state))!==parsed.checksum)throw Error('O conteúdo não confere com a soma de verificação.');verified=true}else state=validateState(parsed);const counts=Object.fromEntries(DATA_ARRAYS.map(key=>[key,(state[key]||[]).length]));return {state,verified,counts,createdAt:verified?parsed.createdAt:null}}
const api=Object.freeze({version:1,createBackup,inspectBackup,validateState,diagnostics,record});
root.KMPlatform=api;if(typeof module!=='undefined'&&module.exports)module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
