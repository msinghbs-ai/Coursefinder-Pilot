import React,{useEffect,useState}from'react'
import{Building2}from'lucide-react'
import{api,supabase}from'./lib/supabase'
import'./contextual-theme.css'

const cache=new Map()
const inflight=new Map()
const listCache=new Map()
const now=()=>Date.now()
const initials=name=>String(name||'University').split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase()
const cacheTtl=expires=>now()+Math.max(60,Number(expires||600)-60)*1000
const listCacheKey='coursefinder:provider-list-logo-cache:v2'
function restoreListCache(){
 if(typeof sessionStorage==='undefined')return
 try{const raw=JSON.parse(sessionStorage.getItem(listCacheKey)||'{}');for(const[k,v]of Object.entries(raw))if(v?.expiresAt>now()&&typeof v?.url==='string')listCache.set(k,v)}catch{}
}
function persistListCache(){
 if(typeof sessionStorage==='undefined')return
 try{const out={};for(const[k,v]of listCache.entries())if(v?.expiresAt>now())out[k]=v;sessionStorage.setItem(listCacheKey,JSON.stringify(out))}catch{}
}
function clearListCache(){listCache.clear();if(typeof sessionStorage!=='undefined')try{sessionStorage.removeItem(listCacheKey)}catch{}}
restoreListCache()

function loadProviderLogo(providerId){
 const key=String(providerId||'')
 if(!key)return Promise.resolve({url:'',expiresAt:0})
 const hit=cache.get(key)
 if(hit?.expiresAt>now())return Promise.resolve(hit)
 if(inflight.has(key))return inflight.get(key)
 const request=api.providerAssetAccess(key).then(x=>{
   const item={url:String(x?.url||''),expiresAt:cacheTtl(x?.expires_in)}
   cache.set(key,item)
   return item
 }).finally(()=>inflight.delete(key))
 inflight.set(key,request)
 return request
}

// CF-247 15 Oct 2026 (Platform Admin: "unable to upload Uni Logos or request to find it"): the logo is made clickable by the screen itself
// (editable), not by a page watcher that missed panels whose details arrived late. Who may change logos is a setting (Pipeline settings › Logos).
let capPromise=null
export function logoCapability(){
 return capPromise||(capPromise=supabase.rpc('admin_provider_logo_capability').then(({data,error})=>{if(error)throw error;return data||{}}).catch(()=>{capPromise=null;return{can_upload:false}}))
}
if(supabase?.auth?.onAuthStateChange)supabase.auth.onAuthStateChange(()=>{capPromise=null})
export function useLogoEditing(enabled=true){
 const[can,setCan]=useState(false)
 useEffect(()=>{if(!enabled){setCan(false);return}let live=true;logoCapability().then(c=>{if(live)setCan(Boolean(c?.can_upload))});return()=>{live=false}},[enabled])
 return can
}

export default function ProviderLogo({providerId,name,size=44,className='',showFallback=true,editable=false}){
 const key=String(providerId||'')
 const[url,setUrl]=useState(()=>key&&cache.get(key)?.expiresAt>now()?cache.get(key).url:'')
 const[failed,setFailed]=useState(false)
 const canEdit=useLogoEditing(Boolean(editable&&key))
 useEffect(()=>{
   let live=true
   if(!key){setUrl('');return()=>{live=false}}
   const hit=cache.get(key)
   if(hit?.expiresAt>now()){setUrl(hit.url);setFailed(false)}
   else{setFailed(false);loadProviderLogo(key).then(x=>{if(live)setUrl(x.url)}).catch(()=>{if(live)setFailed(true)})}
   const refresh=e=>{
     if(String(e?.detail?.providerId||'')!==key)return
     const next=String(e?.detail?.url||'')
     cache.delete(key);inflight.delete(key);setFailed(false)
     if(next){cache.set(key,{url:next,expiresAt:cacheTtl(e?.detail?.expiresIn)});setUrl(next)}
     else loadProviderLogo(key).then(x=>{if(live)setUrl(x.url)}).catch(()=>{})
   }
   addEventListener('coursefinder:provider-logo-refresh',refresh)
   return()=>{live=false;removeEventListener('coursefinder:provider-logo-refresh',refresh)}
 },[key])
 useEffect(()=>{ensureStyles()},[])
 const style={width:size,height:size,minWidth:size}
 const edit=canEdit?{tabIndex:0,role:'button','data-logo-edit':'1',title:'Click to upload a logo, give an image address, or find it on the provider\'s website',
   onClick:e=>{e.preventDefault();e.stopPropagation();openLogoEditor(e.currentTarget,key,name)},
   onKeyDown:e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();e.stopPropagation();openLogoEditor(e.currentTarget,key,name)}}}:{}
 const cls=canEdit?' cf-logo-editable':''
 if(url&&!failed)return <span className={'cf-provider-logo '+className+cls} data-provider-id={key} style={style} {...edit}><img src={url} alt={name?name+' logo':'Provider logo'} loading="lazy" decoding="async" onError={()=>setFailed(true)}/></span>
 if(!showFallback)return null
 return <span className={'cf-provider-logo fallback '+className+cls} data-provider-id={key} style={style} aria-label={name?name+' logo unavailable':'Provider logo unavailable'} {...edit}>{name?<b>{initials(name)}</b>:<Building2 size={Math.max(16,Math.round(size*.44))}/>}</span>
}

export function ProviderBrand({providerId,name,subtitle='',size=48,className='',editable=false}) {
 return <span className={'cf-provider-brand '+className}><ProviderLogo providerId={providerId} name={name} size={size} editable={editable}/><span className="cf-provider-brand-copy"><strong>{name||'Provider'}</strong>{subtitle&&<small>{subtitle}</small>}</span></span>
}

let hydrateFrame=0,observer=null
function ensureStyles(){
 if(document.getElementById('cf-provider-logo-ui-style'))return
 const s=document.createElement('style');s.id='cf-provider-logo-ui-style';s.textContent=`
.cf-provider-brand{display:flex!important;align-items:center!important;gap:10px!important;min-width:0!important}.cf-provider-brand-copy{display:grid!important;gap:2px!important;min-width:0!important}.m-drawer-provider .cf-provider-brand-copy strong,.m-drawer-provider .m-drawer-head strong{color:var(--cf-slate-900)!important;font-weight:850!important;text-shadow:none!important}.cf-provider-brand-copy small{color:var(--cf-slate-500)!important;font-weight:600!important}.m-drawer-provider .cf-provider-brand{color:var(--cf-slate-900)!important}
.cf-provider-logo{display:grid;place-items:center;border-radius:var(--cf-radius-md);overflow:hidden;background:var(--cf-white);border:1px solid var(--cf-slate-200);flex:0 0 auto}.cf-provider-logo img{display:block;width:100%;height:100%;object-fit:contain;background:var(--cf-white)}.cf-provider-logo.fallback{background:var(--cf-slate-50);color:var(--cf-slate-600);font-size:var(--cf-fs-xs);font-weight:850}
.cf-provider-list-cell{display:flex!important;align-items:center!important;gap:9px!important}.cf-provider-list-logo{width:34px!important;height:34px!important;min-width:34px!important;display:grid!important;flex:0 0 34px!important}.cf-provider-list-cell>.m-cell-title{min-width:0!important}.cf-provider-list-cell>.m-cell-title strong{font-weight:500!important;text-shadow:none!important}
.cf-provider-logo.cf-logo-editable{cursor:pointer;outline-offset:2px;transition:box-shadow .15s,border-color .15s}.cf-provider-logo.cf-logo-editable:hover,.cf-provider-logo.cf-logo-editable:focus-visible{border-color:var(--cf-indigo-400);box-shadow:var(--cf-focus-ring);outline:none}.cf-logo-upload-note{display:block;margin:5px 0 0 63px;font-size:var(--cf-fs-2xs);color:var(--cf-slate-500);font-weight:650}.cf-logo-upload-note.success{color:var(--cf-green-700)}.cf-logo-upload-note.error{color:var(--cf-red-750)}.cf-logo-toast{position:fixed;right:18px;bottom:18px;z-index:60001;max-width:420px;background:var(--cf-white);border:1px solid var(--cf-slate-225);border-radius:var(--cf-radius-md);box-shadow:var(--cf-shadow-xl);padding:10px 12px;margin:0!important}.cf-logo-editor .cf-logo-editor-find{width:100%;margin-top:4px}
.cf-logo-editor-backdrop{position:fixed;inset:0;z-index:60000;background:color-mix(in srgb,var(--cf-slate-900) 55%,transparent);display:flex;align-items:center;justify-content:center;padding:18px}.cf-logo-editor{width:min(520px,100%);background:var(--cf-white);border-radius:var(--cf-radius-2xl);border:1px solid var(--cf-slate-225);box-shadow:var(--cf-shadow-xl);padding:18px;color:var(--cf-slate-900)}.cf-logo-editor h3{margin:0 0 5px;font-size:var(--cf-fs-xl);color:var(--cf-slate-900);font-weight:850}.cf-logo-editor p{margin:0 0 14px;font-size:var(--cf-fs-sm);color:var(--cf-slate-500);line-height:1.5}.cf-logo-editor label{display:grid;gap:5px;font-size:var(--cf-fs-xs);font-weight:800;color:var(--cf-slate-600);margin:10px 0}.cf-logo-editor input[type=url]{height:36px;border:1px solid var(--cf-slate-225);border-radius:var(--cf-radius-md);padding:0 9px;color:var(--cf-slate-900);background:var(--cf-white)}.cf-logo-editor-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:14px}.cf-logo-editor button{border:1px solid var(--cf-slate-225);border-radius:var(--cf-radius-md);background:var(--cf-white);padding:8px 11px;font-weight:750;color:var(--cf-slate-700);cursor:pointer}.cf-logo-editor button.primary{background:var(--cf-slate-750);color:var(--cf-white);border-color:var(--cf-slate-750)}.cf-logo-editor-or{text-align:center;font-size:var(--cf-fs-2xs);color:var(--cf-slate-400);font-weight:800;text-transform:uppercase;letter-spacing:.06em}
`;document.head.appendChild(s)
}
function listFallback(name){const s=document.createElement('span');s.className='cf-provider-logo fallback cf-provider-list-logo';s.innerHTML=`<b>${initials(name)}</b>`;return s}
function applyListLogo(slot,item,name){
 if(!slot?.isConnected)return
 if(!item?.url){slot.className='cf-provider-logo fallback cf-provider-list-logo';slot.innerHTML=`<b>${initials(name)}</b>`;return}
 slot.className='cf-provider-logo cf-provider-list-logo';slot.replaceChildren();const img=document.createElement('img');img.src=item.url;img.alt=name+' logo';img.loading='lazy';img.decoding='async';img.fetchPriority='low';img.addEventListener('error',()=>{slot.className='cf-provider-logo fallback cf-provider-list-logo';slot.innerHTML=`<b>${initials(name)}</b>`},{once:true});slot.appendChild(img)
}
async function decorateProviderList(){
 ensureStyles()
 if(!location.hash.startsWith('#providers'))return
 const cells=[...document.querySelectorAll('.m-catalogue-panel .m-table tbody tr td:first-child')].filter(cell=>cell.dataset.cfLogoDecorated!=='1')
 const targets=[]
 for(const cell of cells){
   const title=cell.querySelector('.m-cell-title'),stable=title?.querySelector('small')?.textContent?.trim()
   if(!title||!stable)continue
   const name=title.querySelector('strong')?.textContent?.trim()||'Provider'
   let wrap=cell.querySelector(':scope > .cf-provider-list-cell'),slot=wrap?.querySelector('.cf-provider-list-logo')
   if(!wrap){wrap=document.createElement('span');wrap.className='cf-provider-list-cell';slot=listFallback(name);wrap.appendChild(slot);wrap.appendChild(title);cell.replaceChildren(wrap)}
   else if(!slot){slot=listFallback(name);wrap.insertBefore(slot,wrap.firstChild)}
   cell.dataset.cfLogoDecorated='1'
   const cached=listCache.get(stable);if(cached?.expiresAt>now()){applyListLogo(slot,cached,name);bindListEdit(slot,cached.provider_id,name)}
   targets.push({stable,name,slot,cached:cached?.expiresAt>now()})
 }
 const misses=targets.filter(x=>!x.cached)
 if(!misses.length)return
 const keys=[...new Set(misses.map(x=>x.stable))]
 try{
   const{data,error}=await supabase.functions.invoke('provider-asset-access',{body:{stable_keys:keys}})
   if(error)return
   const expiresAt=cacheTtl(data?.expires_in||600),byKey=new Map((data?.items||[]).map(x=>[String(x.stable_key),x]))
   for(const t of misses){const item=byKey.get(t.stable)||null;listCache.set(t.stable,{url:String(item?.url||''),provider_id:String(item?.provider_id||''),expiresAt});applyListLogo(t.slot,item,t.name);bindListEdit(t.slot,item?.provider_id,t.name)}
   persistListCache()
 }catch{}
}
// the providers list: the logo opens the same editor, for roles allowed to change logos (the row itself still opens the provider)
function bindListEdit(slot,providerId,name){
 if(!slot||!providerId||slot.dataset.cfUploadBound==='1')return
 logoCapability().then(c=>{
   if(!c?.can_upload||!slot.isConnected||slot.dataset.cfUploadBound==='1')return
   slot.dataset.cfUploadBound='1';slot.dataset.logoEdit='1';slot.classList.add('cf-logo-editable');slot.tabIndex=0;slot.setAttribute('role','button');slot.title='Click to upload a logo, give an image address, or find it on the provider\'s website'
   const open=e=>{e.preventDefault();e.stopPropagation();openLogoEditor(slot,String(providerId),name)}
   slot.addEventListener('click',open);slot.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' ')open(e)})
 })
}
function setUploadNote(logo,text,tone=''){
 const brand=logo?.closest?.('.cf-provider-brand')
 let note
 if(brand){note=brand.parentElement?.querySelector('.cf-logo-upload-note');if(!note){note=document.createElement('span');note.className='cf-logo-upload-note';brand.insertAdjacentElement('afterend',note)}}
 else{note=document.querySelector('.cf-logo-toast');if(!note){note=document.createElement('div');document.body.appendChild(note)}clearTimeout(note._t);note._t=setTimeout(()=>note.remove(),tone==='error'?12000:6000)}
 note.className=(brand?'cf-logo-upload-note ':'cf-logo-upload-note cf-logo-toast ')+tone;note.setAttribute('role','status');note.textContent=text
}
// the edge function answers with a reason; show it rather than "non-2xx status code"
async function errorText(e,data){
 if(data?.error)return String(data.error).replace(/_/g,' ')
 try{const b=await e?.context?.json?.();if(b?.error)return String(b.error).replace(/_/g,' ')+(b.detail?': '+b.detail:'')}catch{}
 return String(e?.message||e||'failed')
}
function afterLogoChange(providerId,url='',expiresIn=600){
 cache.delete(String(providerId));inflight.delete(String(providerId));clearListCache()
 dispatchEvent(new CustomEvent('coursefinder:provider-logo-refresh',{detail:{providerId,url,expiresIn}}))
 document.querySelectorAll('.m-catalogue-panel .m-table tbody tr td:first-child[data-cf-logo-decorated="1"]').forEach(cell=>{cell.dataset.cfLogoDecorated='0'});scheduleHydration()
}
async function uploadLogo(logo,providerId,{file=null,sourceUrl=''}){
 setUploadNote(logo,sourceUrl?'Downloading and storing the logo…':'Uploading the logo…')
 const form=new FormData();form.set('provider_id',providerId);if(file)form.set('file',file);if(sourceUrl)form.set('source_url',sourceUrl)
 try{
   const{data,error}=await supabase.functions.invoke('provider-asset-upload',{body:form});if(error||data?.error)throw new Error(await errorText(error,data))
   afterLogoChange(providerId,data?.url||'',data?.expires_in||600);setUploadNote(logo,'Logo updated','success')
 }catch(e){setUploadNote(logo,'Logo not updated: '+String(e?.message||e),'error')}
}
async function findLogo(logo,providerId){
 setUploadNote(logo,'Asking the logo finder…')
 try{
   const{data,error}=await supabase.rpc('admin_provider_logo_find_request',{p_provider_id:providerId});if(error)throw error
   setUploadNote(logo,data?.has_website===false?'Queued, but this provider has no website on record: add its website, or upload the logo.':'Queued: the logo finder checks this provider\'s website within about 10 minutes and attaches the logo it finds.','success')
 }catch(e){setUploadNote(logo,'Not queued: '+String(e?.message||e).replace(/^.*?ERROR:\s*/,''),'error')}
}
export function openLogoEditor(logo,providerId,name=''){
 ensureStyles()
 document.querySelector('.cf-logo-editor-backdrop')?.remove()
 const back=document.createElement('div');back.className='cf-logo-editor-backdrop'
 back.innerHTML=`<section class="cf-logo-editor" role="dialog" aria-modal="true" aria-label="Provider logo"><h3>Provider logo</h3><p data-logo-for></p><label>Upload an image (SVG, PNG, JPEG or WebP, up to 5 MB)<input type="file" accept="image/svg+xml,image/png,image/jpeg,image/webp" data-file></label><div class="cf-logo-editor-or">or</div><label>Image address<input type="url" inputmode="url" placeholder="https://university.edu/logo.svg" data-url></label><div class="cf-logo-editor-or">or</div><button type="button" class="cf-logo-editor-find" data-find>Find it on the provider's website</button><div class="cf-logo-editor-actions"><button type="button" data-cancel>Cancel</button><button type="button" class="primary" data-save>Use logo</button></div></section>`
 back.querySelector('[data-logo-for]').textContent=(name?name+': ':'')+'the logo is stored in StudySearch (an image address is downloaded, not linked). The logo finder never replaces a logo added here.'
 const close=()=>{back.remove();removeEventListener('keydown',esc)},esc=e=>{if(e.key==='Escape')close()}
 addEventListener('keydown',esc)
 back.addEventListener('click',e=>{if(e.target===back)close()});back.querySelector('[data-cancel]').addEventListener('click',close)
 back.querySelector('[data-find]').addEventListener('click',async()=>{close();await findLogo(logo,providerId)})
 back.querySelector('[data-save]').addEventListener('click',async()=>{const file=back.querySelector('[data-file]').files?.[0]||null,sourceUrl=back.querySelector('[data-url]').value.trim();if(!file&&!sourceUrl){back.querySelector('[data-url]').focus();return}if(file&&sourceUrl){back.querySelector('[data-url]').setCustomValidity('Choose a file or an address, not both.');back.querySelector('[data-url]').reportValidity();return}close();await uploadLogo(logo,providerId,{file,sourceUrl})})
 document.body.appendChild(back);back.querySelector('[data-file]').focus()
}
function scheduleHydration(){
 if(hydrateFrame||typeof requestAnimationFrame==='undefined')return
 hydrateFrame=requestAnimationFrame(()=>{hydrateFrame=0;decorateProviderList()})
}
function relevantMutation(records){
 if(!location.hash.startsWith('#providers'))return false
 return records.some(r=>[...r.addedNodes].some(n=>n?.nodeType===1&&(n.matches?.('.m-table,.m-table tbody tr,.m-cell-title')||n.querySelector?.('.m-table tbody tr,.m-cell-title'))))
}
function bindHydrationObserver(){
 if(observer)return
 const root=document.getElementById('root')||document.body
 observer=new MutationObserver(records=>{if(relevantMutation(records))scheduleHydration()})
 observer.observe(root,{childList:true,subtree:true})
 scheduleHydration()
}
if(typeof document!=='undefined'){
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',bindHydrationObserver,{once:true});else bindHydrationObserver()
 addEventListener('hashchange',scheduleHydration)
}
