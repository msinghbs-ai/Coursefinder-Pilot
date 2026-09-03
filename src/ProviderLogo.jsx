import React,{useEffect,useState}from'react'
import{Building2}from'lucide-react'
import{api,supabase}from'./lib/supabase'

const cache=new Map()
const now=()=>Date.now()
const initials=name=>String(name||'University').split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase()
const cacheTtl=expires=>now()+Math.max(60,Number(expires||600)-60)*1000

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
 return <span className={'cf-provider-brand '+className}><ProviderLogo providerId={providerId} name={name} size={size}/><span className="cf-provider-brand-copy"><strong style={{color:'#0f172a',fontWeight:850}}>{name||'Provider'}</strong>{subtitle&&<small>{subtitle}</small>}</span></span>
}

let roleRankPromise=null,decorateTimer=null
const getRoleRank=()=>roleRankPromise||(roleRankPromise=api.context().then(x=>Number(x?.role_rank||0)).catch(()=>0))
function ensureStyles(){
 if(document.getElementById('cf-provider-logo-ui-style'))return
 const s=document.createElement('style');s.id='cf-provider-logo-ui-style';s.textContent=`
.cf-provider-brand-copy strong{color:#0f172a!important;font-weight:850!important}.cf-provider-brand-copy small{color:#64748b!important}.m-drawer-provider .cf-provider-brand{color:#0f172a!important}
.cf-provider-logo{display:grid;place-items:center;border-radius:9px;overflow:hidden;background:#fff;border:1px solid #e2e8f0;flex:0 0 auto}.cf-provider-logo img{display:block;width:100%;height:100%;object-fit:contain;background:#fff}.cf-provider-logo.fallback{background:#f8fafc;color:#475569;font-size:10px;font-weight:850}
.cf-provider-list-cell{display:flex;align-items:center;gap:9px}.cf-provider-list-logo{width:34px;height:34px;min-width:34px}.cf-provider-list-cell>.m-cell-title{min-width:0}.cf-provider-list-cell>.m-cell-title strong{color:#0f172a!important;font-weight:800!important}
.m-drawer-provider .cf-provider-logo.cf-logo-editable{cursor:pointer;outline-offset:2px;transition:box-shadow .15s,border-color .15s}.m-drawer-provider .cf-provider-logo.cf-logo-editable:hover,.m-drawer-provider .cf-provider-logo.cf-logo-editable:focus-visible{border-color:#818cf8;box-shadow:0 0 0 3px rgba(99,102,241,.14);outline:none}.cf-logo-upload-note{display:block;margin:5px 0 0 63px;font-size:9px;color:#64748b;font-weight:650}.cf-logo-upload-note.success{color:#15803d}.cf-logo-upload-note.error{color:#b42318}
`;document.head.appendChild(s)
}
function listFallback(name){const s=document.createElement('span');s.className='cf-provider-logo fallback cf-provider-list-logo';s.innerHTML=`<b>${initials(name)}</b>`;return s}
async function decorateProviderList(){
 ensureStyles()
 if(!location.hash.startsWith('#providers'))return
 const rows=[...document.querySelectorAll('.m-catalogue-panel .m-table tbody tr')]
 const targets=[]
 for(const row of rows){
   const cell=row.querySelector('td:first-child'),title=cell?.querySelector('.m-cell-title'),stable=title?.querySelector('small')?.textContent?.trim()
   if(!cell||!title||!stable||cell.dataset.cfLogoDecorated==='1')continue
   targets.push({cell,title,stable,name:title.querySelector('strong')?.textContent?.trim()||'Provider'})
 }
 if(!targets.length)return
 const keys=[...new Set(targets.map(x=>x.stable))]
 let byKey=new Map()
 try{
   const{data,error}=await supabase.functions.invoke('provider-asset-access',{body:{stable_keys:keys}})
   if(!error)byKey=new Map((data?.items||[]).map(x=>[String(x.stable_key),x]))
 }catch{}
 for(const t of targets){
   if(!t.cell.isConnected||t.cell.dataset.cfLogoDecorated==='1')continue
   const item=byKey.get(t.stable),logo=item?.url?document.createElement('span'):listFallback(t.name)
   if(item?.url){logo.className='cf-provider-logo cf-provider-list-logo';const img=document.createElement('img');img.src=item.url;img.alt=t.name+' logo';img.loading='lazy';img.addEventListener('error',()=>{logo.replaceWith(listFallback(t.name))},{once:true});logo.appendChild(img)}
   const wrap=document.createElement('span');wrap.className='cf-provider-list-cell';wrap.appendChild(logo);wrap.appendChild(t.title);t.cell.replaceChildren(wrap);t.cell.dataset.cfLogoDecorated='1'
 }
}
function setUploadNote(logo,text,tone=''){
 const brand=logo.closest('.cf-provider-brand');if(!brand)return
 let note=brand.parentElement?.querySelector('.cf-logo-upload-note');if(!note){note=document.createElement('span');note.className='cf-logo-upload-note';brand.insertAdjacentElement('afterend',note)}
 note.className='cf-logo-upload-note '+tone;note.textContent=text
}
async function enableProviderLogoUpload(){
 ensureStyles();if(!document.querySelector('.m-drawer-provider'))return
 const rank=await getRoleRank();if(rank<5)return
 document.querySelectorAll('.m-drawer-provider .cf-provider-logo[data-provider-id]').forEach(logo=>{
   if(logo.dataset.cfUploadBound==='1')return
   const providerId=logo.dataset.providerId;if(!providerId)return
   logo.dataset.cfUploadBound='1';logo.classList.add('cf-logo-editable');logo.tabIndex=0;logo.title='Click to upload or replace Provider logo'
   const choose=()=>{
     const input=document.createElement('input');input.type='file';input.accept='image/svg+xml,image/png,image/jpeg,image/webp';input.hidden=true
     input.addEventListener('change',async()=>{
       const file=input.files?.[0];if(!file){input.remove();return}
       setUploadNote(logo,'Uploading Provider logo…')
       const form=new FormData();form.set('provider_id',providerId);form.set('file',file)
       try{
         const{data,error}=await supabase.functions.invoke('provider-asset-upload',{body:form});if(error)throw error;if(data?.error)throw new Error(data.error)
         cache.delete(providerId);dispatchEvent(new CustomEvent('coursefinder:provider-logo-refresh',{detail:{providerId,url:data?.url||'',expiresIn:data?.expires_in||600}}));setUploadNote(logo,'Logo updated · managed primary asset','success');queueDecorate()
       }catch(e){setUploadNote(logo,'Upload failed: '+String(e?.message||e),'error')}
       finally{input.remove()}
     },{once:true});document.body.appendChild(input);input.click()
   }
   logo.addEventListener('click',e=>{e.stopPropagation();choose()});logo.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();choose()}})
   setUploadNote(logo,'PIM Operator: click the logo to upload/replace')
 })
}
function queueDecorate(){clearTimeout(decorateTimer);decorateTimer=setTimeout(()=>{decorateProviderList();enableProviderLogoUpload()},90)}
if(typeof document!=='undefined'){
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',queueDecorate,{once:true});else queueDecorate()
 new MutationObserver(queueDecorate).observe(document.documentElement,{childList:true,subtree:true})
 addEventListener('hashchange',queueDecorate)
}
