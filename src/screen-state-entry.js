import{utils as supabaseUtils}from'./lib/supabase'
import{supabase}from'./lib/supabase'

const PREFIX='coursefinder:pim:screen-state:v1'
const SUPPORTED=new Set(['courses','providers','campuses','scholarships','completeness'])
const FILTER_ORDER=['Country','State / Region','Provider','Study level','Field','Delivery','Has fee','Has intake','Has English','Has scholarship','Min readiness','Freshness','Lifecycle','Publication']
let restoring=false,timer=null,userId='anonymous',restoreToken=0

function route(){return location.hash.replace(/^#/,'').split('?')[0]||'dashboard'}
function key(r=route()){return`${PREFIX}:${userId}:${r}`}
function root(){return document.querySelector('.m-catalogue-panel')}
function text(el){return String(el?.textContent||'').trim().replace(/\s+/g,' ')}
function setInput(input,value){const setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set;setter?.call(input,value);input.dispatchEvent(new Event('input',{bubbles:true}))}
function currentSnapshot(){const r=route(),panel=root();if(!SUPPORTED.has(r)||!panel)return null;const search=panel.querySelector('.m-searchbox input')?.value||'';const filters={};panel.querySelectorAll('.m-filter-button').forEach(btn=>{const label=text(btn.querySelector('small')),value=text(btn.querySelector('strong'));if(label&&value&&value!=='All')filters[label]=value});const advanced=Boolean(panel.querySelector('.m-filter-toggle.active'));return{route:r,search,filters,advanced,saved_at:new Date().toISOString()}}
function persist(){if(restoring)return;const snap=currentSnapshot();if(!snap)return;try{localStorage.setItem(key(snap.route),JSON.stringify(snap))}catch{}}
function schedulePersist(delay=180){clearTimeout(timer);timer=setTimeout(persist,delay)}
function clearCurrent(){try{localStorage.removeItem(key())}catch{}}
function read(r){try{return JSON.parse(localStorage.getItem(key(r))||'null')}catch{return null}}
function delay(ms){return new Promise(resolve=>setTimeout(resolve,ms))}
function buttonFor(label){return[...document.querySelectorAll('.m-catalogue-panel .m-filter-button')].find(b=>text(b.querySelector('small'))===label)}
async function choose(label,wanted,token){for(let attempt=0;attempt<8&&token===restoreToken;attempt++){const btn=buttonFor(label);if(!btn){await delay(150);continue}if(text(btn.querySelector('strong'))===wanted)return true;btn.click();await delay(80);const pop=btn.parentElement?.querySelector('.m-filter-popover');if(!pop){await delay(120);continue}const option=[...pop.querySelectorAll('button')].find(x=>text(x.querySelector('span'))===wanted||text(x)===wanted);if(option){option.click();await delay(label==='Country'||label==='State / Region'?260:100);return true}btn.click();await delay(160)}return false}
async function restore(r=route()){
  if(!SUPPORTED.has(r))return
  const saved=read(r);if(!saved)return
  const token=++restoreToken;restoring=true
  try{
    for(let i=0;i<20&&token===restoreToken;i++){if(root())break;await delay(120)}
    const panel=root();if(!panel||token!==restoreToken)return
    if(saved.advanced){const toggle=panel.querySelector('.m-filter-toggle');if(toggle&&!toggle.classList.contains('active')){toggle.click();await delay(100)}}
    const input=panel.querySelector('.m-searchbox input');if(input&&saved.search&&input.value!==saved.search){setInput(input,saved.search);await delay(320)}
    for(const label of FILTER_ORDER){const wanted=saved.filters?.[label];if(wanted)await choose(label,wanted,token)}
  }finally{if(token===restoreToken){restoring=false;setTimeout(()=>persist(),250)}}
}
async function initUser(){try{const{data}=await supabase.auth.getSession();userId=data.session?.user?.id||'anonymous'}catch{userId='anonymous'};restore()}

document.addEventListener('input',e=>{if(e.target.closest?.('.m-catalogue-panel .m-searchbox'))schedulePersist()},true)
document.addEventListener('click',e=>{const btn=e.target.closest?.('button');if(!btn)return;if(btn.closest('.m-catalogue-panel')){const t=text(btn);if(/^Clear$/i.test(t)){clearCurrent();return}if(btn.closest('.m-filter-select')||btn.classList.contains('m-filter-toggle')||btn.closest('.m-searchbox'))schedulePersist(260)}},true)
addEventListener('hashchange',()=>{clearTimeout(timer);restoreToken++;setTimeout(()=>restore(),120)})
addEventListener('beforeunload',persist)
supabase.auth.onAuthStateChange((_event,session)=>{if(session?.user?.id){userId=session.user.id;setTimeout(()=>restore(),180)}})
if(document.readyState==='loading')addEventListener('DOMContentLoaded',initUser,{once:true});else initUser()
