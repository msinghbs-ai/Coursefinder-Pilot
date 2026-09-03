import React,{useEffect,useState}from'react'
import{Building2}from'lucide-react'
import{api,supabase}from'./lib/supabase'

const cache=new Map()
const listCache=new Map()
const now=()=>Date.now()
const initials=name=>String(name||'University').split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase()
const cacheTtl=expires=>now()+Math.max(60,Number(expires||600)-60)*1000
const listCacheKey='coursefinder:provider-list-logo-cache:v1'
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

export default function ProviderLogo({providerId,name,size=44,className='',showFallback=true}){
 const[url,setUrl]=useState(()=>providerId&&cache.get(providerId)?.expiresAt>now()?cache.get(providerId).url:'')
 const[failed,setFailed]=useState(false)
 useEffect(()=>{
   let live=true
   if(!providerId){setUrl('');return()=>{live=false}}
   const hit=cache.get(providerId)
   if(hit?.expiresAt>now()){setUrl(hit.url);setFailed(false);return()=>{live=false}}
   setFailed(false)
   api.providerAssetAccess(providerId).then(x=>{
     if(!live||!x?.url)return
     cache.set(providerId,{url:x.url,expiresAt:cacheTtl(x.expires_in)})
     setUrl(x.url)
   }).catch(()=>{if(live)setFailed(true)})
   const refresh=e=>{
     if(String(e?.detail?.providerId||'')!==String(providerId))return
     const next=String(e?.detail?.url||'')
     cache.delete(providerId);setFailed(false)
     if(next){cache.set(providerId,{url:next,expiresAt:cacheTtl(e?.detail?.expiresIn)});setUrl(next)}
     else api.providerAssetAccess(providerId).then(x=>{if(live&&x?.url){cache.set(providerId,{url:x.url,expiresAt:cacheTtl(x.expires_in)});setUrl(x.url)}}).catch(()=>{})
   }
   addEventListener('coursefinder:provider-logo-refresh',refresh)
   return()=>{live=false;removeEventListener('coursefinder:provider-logo-refresh',refresh)}
 },[providerId])
 const style={width:size,height:size,minWidth:size}
 if(url&&!failed)return <span className={'cf-provider-logo '+className} data-provider-id={providerId||''} style={style}><img src={url} alt={name?name+' logo':'Provider logo'} loading="lazy" onError={()=>setFailed(true)}/></span>
 if(!showFallback)return null
 return <span className={'cf-provider-logo fallback '+className} data-provider-id={providerId||''} style={style} aria-label={name?name+' logo unavailable':'Provider logo unavailable'}>{name?<b>{initials(name)}</b>:<Building2 size={Math.max(16,Math.round(size*.44))}/>}</span>
}

export function ProviderBrand({providerId,name,subtitle='',size=48,className=''}) {
 return <span className={'cf-provider-brand '+className}><ProviderLogo providerId={providerId} name={name} size={size}/><span className="cf-provider-brand-copy"><strong>{name||'Provider'}</strong>{subtitle&&<small>{subtitle}</small>}</span></span>
}

let roleRankPromise=null,decorateTimer=null
const getRoleRank=()=>roleRankPromise||(roleRankPromise=api.context().then(x=>Number(x?.role_rank||0)).catch(()=>0))
function ensureStyles(){
 if(document.getElementById('cf-provider-logo-ui-style'))return
 const s=document.createElement('style');s.id='cf-provider-logo-ui-style';s.textContent=`
.cf-provider-brand{display:flex!important;align-items:center!important;gap:10px!important;min-width:0!important}.cf-provider-brand-copy{display:grid!important;gap:2px!important;min-width:0!important}.m-drawer-provider .cf-provider-brand-copy strong,.m-drawer-provider .m-drawer-head strong{color:#0f172a!important;font-weight:850!important;text-shadow:none!important}.cf-provider-brand-copy small{color:#64748b!important;font-weight:600!important}.m-drawer-provider .cf-provider-brand{color:#0f172a!important}
.cf-provider-logo{display:grid;place-items:center;border-radius:9px;overflow:hidden;background:#fff;border:1px solid #e2e8f0;flex:0 0 auto}.cf-provider-logo img{display:block;width:100%;height:100%;object-fit:contain;background:#fff}.cf-provider-logo.fallback{background:#f8fafc;color:#475569;font-size:10px;font-weight:850}
.cf-provider-list-cell{display:flex!important;align-items:center!important;gap:9px!important}.cf-provider-list-logo{width:34px!important;height:34px!important;min-width:34px!important;display:grid!important;flex:0 0 34px!important}.cf-provider-list-cell>.m-cell-title{min-width:0!important}.cf-provider-list-cell>.m-cell-title strong{font-weight:500!important;text-shadow:none!important}
.m-drawer-provider .cf-provider-logo.cf-logo-editable{cursor:pointer;outline-offset:2px;transition:box-shadow .15s,border-color .15s}.m-drawer-provider .cf-provider-logo.cf-logo-editable:hover,.m-drawer-provider .cf-provider-logo.cf-logo-editable:focus-visible{border-color:#818cf8;box-shadow:0 0 0 3px rgba(99,102,241,.14);outline:none}.cf-logo-upload-note{display:block;margin:5px 0 0 63px;font-size:9px;color:#64748b;font-weight:650}.cf-logo-upload-note.success{color:#15803d}.cf-logo-upload-note.error{color:#b42318}
.cf-logo-editor-backdrop{position:fixed;inset:0;z-index:60000;background:rgba(15,23,42,.55);display:flex;align-items:center;justify-content:center;padding:18px}.cf-logo-editor{width:min(520px,100%);background:#fff;border-radius:14px;border:1px solid #dfe5ee;box-shadow:0 28px 80px rgba(15,23,42,.3);padding:18px;color:#0f172a}.cf-logo-editor h3{margin:0 0 5px;font-size:16px;color:#0f172a;font-weight:850}.cf-logo-editor p{margin:0 0 14px;font-size:11px;color:#64748b;line-height:1.5}.cf-logo-editor label{display:grid;gap:5px;font-size:10px;font-weight:800;color:#475569;margin:10px 0}.cf-logo-editor input[type=url]{height:36px;border:1px solid #dbe3ec;border-radius:8px;padding:0 9px;color:#0f172a;background:#fff}.cf-logo-editor-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:14px}.cf-logo-editor button{border:1px solid #dbe3ec;border-radius:8px;background:#fff;padding:8px 11px;font-weight:750;color:#334155;cursor:pointer}.cf-logo-editor button.primary{background:#25324a;color:#fff;border-color:#25324a}.cf-logo-editor-or{text-align:center;font-size:9px;color:#94a3b8;font-weight:800;text-transform:uppercase;letter-spacing:.06em}
`;document.head.appendChild(s)
}
function listFallback(name){const s=document.createElement('span');s.className='cf-provider-logo fallback cf-provider-list-logo';s.innerHTML=`<b>${initials(name)}</b>`;return s}
function applyListLogo(slot,item,name){
 if(!slot?.isConnected)return
 if(!item?.url){slot.className='cf-provider-logo fallback cf-provider-list-logo';slot.innerHTML=`<b>${initials(name)}</b>`;return}
 slot.className='cf-provider-logo cf-provider-list-logo';slot.replaceChildren();const img=document.createElement('img');img.src=item.url;img.alt=name+' logo';img.loading='eager';img.decoding='async';img.addEventListener('error',()=>{slot.className='cf-provider-logo fallback cf-provider-list-logo';slot.innerHTML=`<b>${initials(name)}</b>`},{once:true});slot.appendChild(img)
}
async function decorateProviderList(){
 ensureStyles()
 if(!location.hash.startsWith('#providers'))return
 const rows=[...document.querySelectorAll('.m-catalogue-panel .m-table tbody tr')]
 const targets=[]
 for(const row of rows){
   const cell=row.querySelector('td:first-child'),title=cell?.querySelector('.m-cell-title'),stable=title?.querySelector('small')?.textContent?.trim()
   if(!cell||!title||!stable||cell.dataset.cfLogoDecorated==='1')continue
   const name=title.querySelector('strong')?.textContent?.trim()||'Provider',slot=listFallback(name),wrap=document.createElement('span')
   wrap.className='cf-provider-list-cell';wrap.appendChild(slot);wrap.appendChild(title);cell.replaceChildren(wrap);cell.dataset.cfLogoDecorated='1'
   const cached=listCache.get(stable);if(cached?.expiresAt>now())applyListLogo(slot,cached,name)
   targets.push({cell,title,stable,name,slot,cached:cached?.expiresAt>now()})
 }
 const misses=targets.filter(x=>!x.cached)
 if(!misses.length)return
 const keys=[...new Set(misses.map(x=>x.stable))]
 try{
   const{data,error}=await supabase.functions.invoke('provider-asset-access',{body:{stable_keys:keys}})
   if(error)return
   const expiresAt=cacheTtl(data?.expires_in||600),byKey=new Map((data?.items||[]).map(x=>[String(x.stable_key),x]))
   for(const t of misses){
     const item=byKey.get(t.stable)||null
     listCache.set(t.stable,{url:String(item?.url||''),expiresAt});applyListLogo(t.slot,item,t.name)
   }
   persistListCache()
 }catch{}
}
function setUploadNote(logo,text,tone=''){
 const brand=logo.closest('.cf-provider-brand');if(!brand)return
 let note=brand.parentElement?.querySelector('.cf-logo-upload-note');if(!note){note=document.createElement('span');note.className='cf-logo-upload-note';brand.insertAdjacentElement('afterend',note)}
 note.className='cf-logo-upload-note '+tone;note.textContent=text
}
async function uploadLogo(logo,providerId,{file=null,sourceUrl=''}){
 setUploadNote(logo,sourceUrl?'Downloading and storing Provider logo…':'Uploading Provider logo…')
 const form=new FormData();form.set('provider_id',providerId);if(file)form.set('file',file);if(sourceUrl)form.set('source_url',sourceUrl)
 try{
   const{data,error}=await supabase.functions.invoke('provider-asset-upload',{body:form});if(error)throw error;if(data?.error)throw new Error(data.error)
   cache.delete(providerId);clearListCache();dispatchEvent(new CustomEvent('coursefinder:provider-logo-refresh',{detail:{providerId,url:data?.url||'',expiresIn:data?.expires_in||600}}));setUploadNote(logo,'Logo updated · managed primary asset','success');queueDecorate()
 }catch(e){setUploadNote(logo,'Logo update failed: '+String(e?.message||e),'error')}
}
function openLogoEditor(logo,providerId){
 document.querySelector('.cf-logo-editor-backdrop')?.remove()
 const back=document.createElement('div');back.className='cf-logo-editor-backdrop';back.innerHTML=`<section class="cf-logo-editor" role="dialog" aria-modal="true" aria-label="Replace Provider logo"><h3>Replace Provider logo</h3><p>This control is available only from the Provider screen to PIM/Admin operators. Upload an image, or provide a public HTTPS image URL. URL images are downloaded server-side and stored in the managed Provider Assets bucket; external hot-linking is not retained.</p><label>Browse image<input type="file" accept="image/svg+xml,image/png,image/jpeg,image/webp" data-file></label><div class="cf-logo-editor-or">or</div><label>Image URL<input type="url" inputmode="url" placeholder="https://university.edu/logo.svg" data-url></label><div class="cf-logo-editor-actions"><button type="button" data-cancel>Cancel</button><button type="button" class="primary" data-save>Use logo</button></div></section>`
 const close=()=>back.remove();back.addEventListener('click',e=>{if(e.target===back)close()});back.querySelector('[data-cancel]').addEventListener('click',close);back.querySelector('[data-save]').addEventListener('click',async()=>{const file=back.querySelector('[data-file]').files?.[0]||null,sourceUrl=back.querySelector('[data-url]').value.trim();if(!file&&!sourceUrl){back.querySelector('[data-url]').focus();return}if(file&&sourceUrl){back.querySelector('[data-url]').setCustomValidity('Choose a file or URL, not both.');back.querySelector('[data-url]').reportValidity();return}close();await uploadLogo(logo,providerId,{file,sourceUrl})});document.body.appendChild(back);back.querySelector('[data-file]').focus()
}
async function enableProviderLogoUpload(){
 ensureStyles();if(!location.hash.startsWith('#providers')||!document.querySelector('.m-drawer-provider'))return
 const rank=await getRoleRank();if(rank<5)return
 document.querySelectorAll('.m-drawer-provider .cf-provider-logo[data-provider-id]').forEach(logo=>{
   if(logo.dataset.cfUploadBound==='1')return
   const providerId=logo.dataset.providerId;if(!providerId)return
   logo.dataset.cfUploadBound='1';logo.classList.add('cf-logo-editable');logo.tabIndex=0;logo.title='Click to upload, replace or import Provider logo from image URL'
   const choose=()=>openLogoEditor(logo,providerId)
   logo.addEventListener('click',e=>{e.stopPropagation();choose()});logo.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();choose()}})
   setUploadNote(logo,'PIM/Admin: click logo to upload or import from image URL')
 })
}
function queueDecorate(){clearTimeout(decorateTimer);decorateTimer=setTimeout(()=>{decorateProviderList();enableProviderLogoUpload()},90)}
if(typeof document!=='undefined'){
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',queueDecorate,{once:true});else queueDecorate()
 new MutationObserver(queueDecorate).observe(document.documentElement,{childList:true,subtree:true})
 addEventListener('hashchange',queueDecorate)
}
