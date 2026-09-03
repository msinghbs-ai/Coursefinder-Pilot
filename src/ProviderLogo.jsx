import React,{useEffect,useState}from'react'
import{Building2}from'lucide-react'
import{api}from'./lib/supabase'

const cache=new Map()
const now=()=>Date.now()
const initials=name=>String(name||'University').split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase()

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
     cache.set(providerId,{url:x.url,expiresAt:now()+Math.max(60,Number(x.expires_in||600)-60)*1000})
     setUrl(x.url)
   }).catch(()=>{if(live)setFailed(true)})
   return()=>{live=false}
 },[providerId])
 const style={width:size,height:size,minWidth:size}
 if(url&&!failed)return <span className={'cf-provider-logo '+className} style={style}><img src={url} alt={name?name+' logo':'Provider logo'} loading="lazy" onError={()=>setFailed(true)}/></span>
 if(!showFallback)return null
 return <span className={'cf-provider-logo fallback '+className} style={style} aria-label={name?name+' logo unavailable':'Provider logo unavailable'}>{name?<b>{initials(name)}</b>:<Building2 size={Math.max(16,Math.round(size*.44))}/>}</span>
}

export function ProviderBrand({providerId,name,subtitle='',size=48,className=''}) {
 return <span className={'cf-provider-brand '+className}><ProviderLogo providerId={providerId} name={name} size={size}/><span className="cf-provider-brand-copy"><strong>{name||'Provider'}</strong>{subtitle&&<small>{subtitle}</small>}</span></span>
}
