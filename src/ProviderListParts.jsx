// s781 (Platform Admin 19 Nov 2026 16:37, chat S1-RM-Design): the Catalogue › Providers list. Each row leads with the provider's logo (32 px, contained
// on white) or a two-letter monogram in a calm colour picked from the name, then the name in bold with its CRICOS code or stable key underneath.
// Country codes show a drawn flag for Australia, New Zealand and Canada beside one code pill: Windows has no flag emoji, so the emoji read "AU AU".
import React,{useEffect,useState}from'react'
import{listLogoCached,requestListLogo,useLogoEditing,openLogoEditor}from'./ProviderLogo'
import'./provider-list.css'

const TONES=['indigo','blue','green','amber','violet','orange']
const SMALL=/^(of|the|and|for|at|in|de|la|le|du|des|y)$/i
export function monogram(name){
  const w=String(name||'').replace(/\([^)]*\)/g,' ').split(/[\s\-–—,&/]+/).filter(x=>/^[\p{L}\p{N}]/u.test(x)&&!SMALL.test(x))
  return (w.length>=2?w[0][0]+w[1][0]:(w[0]||'?').slice(0,2)).toUpperCase()
}
export function toneOf(name){let h=0;for(const c of String(name||''))h=(h*31+c.codePointAt(0))>>>0;return TONES[h%TONES.length]}

export function ProviderListLogo({stableKey,providerId,name}){
  const k=String(stableKey||'')
  const[item,setItem]=useState(()=>listLogoCached(k)),[failed,setFailed]=useState(false)
  useEffect(()=>{let live=true;setFailed(false);if(!k){setItem(null);return}const c=listLogoCached(k);if(c){setItem(c);return}
    requestListLogo(k).then(v=>{if(live)setItem(v)});return()=>{live=false}},[k])
  const pid=String(providerId||item?.provider_id||'')
  useEffect(()=>{if(!pid)return;const on=e=>{if(String(e?.detail?.providerId||'')!==pid)return;setFailed(false);setItem(x=>({...(x||{}),url:String(e?.detail?.url||'')}))}
    addEventListener('coursefinder:provider-logo-refresh',on);return()=>removeEventListener('coursefinder:provider-logo-refresh',on)},[pid])
  const canEdit=useLogoEditing(Boolean(pid))
  const edit=canEdit&&pid?{role:'button',tabIndex:0,'data-logo-edit':'1',title:'Click to upload a logo, give an image address, or find it on the provider\'s website',
    onClick:e=>{e.preventDefault();e.stopPropagation();openLogoEditor(e.currentTarget,pid,name)},
    onKeyDown:e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();e.stopPropagation();openLogoEditor(e.currentTarget,pid,name)}}}:{'aria-hidden':'true'}
  const url=item?.url&&!failed?item.url:''
  if(url)return <span className={`pl-logo${canEdit?' pl-editable':''}`} data-pl-logo="image" {...edit}><img src={url} alt="" loading="lazy" decoding="async" onError={()=>setFailed(true)}/></span>
  return <span className={`pl-logo pl-mono tone-${toneOf(name)}${canEdit?' pl-editable':''}`} data-pl-logo="monogram" {...edit}>{monogram(name)}</span>
}

// ---- flags: drawn, so they look the same on every system ----------------------------------------------------------------------------------------
const NAMES={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
const star=(cx,cy,r,n=7,inner=.42)=>Array.from({length:n*2},(_,i)=>{const a=Math.PI*i/n-Math.PI/2,q=i%2?r*inner:r;return `${(cx+q*Math.cos(a)).toFixed(2)},${(cy+q*Math.sin(a)).toFixed(2)}`}).join(' ')
const F={navy:{fill:'var(--cf-flag-navy)'},red:{fill:'var(--cf-flag-red)'},white:{fill:'var(--cf-white)'},caRed:{fill:'var(--cf-flag-ca-red)'}}
const S=(c,w)=>({stroke:`var(--cf-${c})`,strokeWidth:w,fill:'none'})
function Canton(){return <svg x="0" y="0" width="10" height="5" viewBox="0 0 10 5"><rect width="10" height="5" style={F.navy}/>
  <path d="M0 0L10 5M10 0L0 5" style={S('white',1)}/><path d="M0 0L10 5M10 0L0 5" style={S('flag-red',.35)}/>
  <path d="M5 0V5M0 2.5H10" style={S('white',1.6)}/><path d="M5 0V5M0 2.5H10" style={S('flag-red',.9)}/></svg>}
const LEAF=[[0,-1],[.13,-.75],[.28,-.82],[.22,-.38],[.45,-.6],[.5,-.48],[.75,-.52],[.66,-.27],[.8,-.2],[.48,.1],[.55,.25],[.06,.2],[.08,.62],[-.08,.62],[-.06,.2],[-.55,.25],[-.48,.1],[-.8,-.2],[-.66,-.27],[-.75,-.52],[-.5,-.48],[-.45,-.6],[-.22,-.38],[-.28,-.82],[-.13,-.75]]
const FLAG={
  AU:<><rect width="20" height="10" style={F.navy}/><Canton/><polygon points={star(5,7.5,1.5)} style={F.white}/>
    {[[15,8.4,.8],[12.6,4.6,.75],[15,1.6,.75],[17.4,3.9,.75]].map(([x,y,r],i)=><polygon key={i} points={star(x,y,r)} style={F.white}/>)}<polygon points={star(16.1,5.7,.42,5)} style={F.white}/></>,
  NZ:<><rect width="20" height="10" style={F.navy}/><Canton/>
    {[[15,8.3,.95],[12.8,4.4,.8],[15,1.7,.7],[17.2,3.8,.8]].map(([x,y,r],i)=><polygon key={i} points={star(x,y,r,5,.4)} style={{...F.red,stroke:'var(--cf-white)',strokeWidth:.3}}/>)}</>,
  CA:<><rect width="20" height="10" style={F.white}/><rect width="5" height="10" style={F.caRed}/><rect x="15" width="5" height="10" style={F.caRed}/>
    <polygon points={LEAF.map(([x,y])=>`${(10+x*3.3).toFixed(2)},${(4.8+y*3.3).toFixed(2)}`).join(' ')} style={F.caRed}/></>
}
export function CountryTag({code}){
  const c=String(code||'').trim().toUpperCase();if(!c)return '—'
  const f=FLAG[c]
  return <span className="pl-country" data-country={c} title={NAMES[c]||undefined}>{f&&<svg className="pl-flag" data-flag={c} viewBox="0 0 20 10" aria-hidden="true" focusable="false">{f}</svg>}<span className="pl-cc">{c}</span></span>
}

// the line under a provider's name: its registration code, or its stable key when it has none
export function providerMeta(r){const g=r?.registration;if(g?.code)return `${g.scheme||'CRICOS'} ${g.code}`;return r?.stable_key?String(r.stable_key):''}
