// CF-247 v2.15.298 (Platform Admin, 20 Oct 2026 07:02: "anything that needs attention or intervention should come to Layer 4, define its
// return path"; 07:40 choices: by university, all stopped onboarding cases, courses not on the site at the bottom, websites down after 30
// days). Layer 4 › Inbox: everything that needs a person, grouped by university, from public.admin_layer4_inbox. Each item says why it is
// here and what each choice does next; choices that open another screen link to it. Design: admin repo docs/platform/LAYER4-INBOX-DESIGN.md.
import React,{useEffect,useMemo,useState}from'react'
import{AlertTriangle,ArrowRight,ExternalLink,Inbox,RefreshCw,Search}from'lucide-react'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{Button,Empty,Loading,Metric,StatusChip,fmtDate,fmtNumber}from'./ui-kit'
import'./layer4-inbox.css'

const rpc=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
const days=t=>t?Math.max(0,Math.floor((Date.now()-new Date(t).getTime())/86400000)):0
const linkFor=(link,it)=>link==='builder'?hrefFor('layer2','builder',{provider:it.provider_id}):link==='course'?hrefFor('courses','',{id:it.detail?.course_id}):link==='reports'?hrefFor('coverage','reports'):'#'
const urlOf=v=>typeof v==='string'?v:Array.isArray(v)?urlOf(v[0]):v&&typeof v==='object'?(v.url||v.course_url||''):''

export default function Layer4Inbox({onError}){
  const[sum,setSum]=useState(null),[view,setView]=useState('university'),[kind,setKind]=useState(''),[q,setQ]=useState('')
  const[unis,setUnis]=useState(null),[offset,setOffset]=useState(0),[pick,setPick]=useState(null),[items,setItems]=useState(null),[note,setNote]=useState('')
  const kinds=sum?.kinds||{},order=useMemo(()=>Object.entries(kinds).sort((a,b)=>a[1].order-b[1].order).map(([k])=>k),[sum])
  const loadSum=()=>rpc('summary').then(setSum).catch(e=>onError?.(e.message))
  const loadUnis=(o=offset)=>{setUnis(null);rpc('universities',{kind,q,limit:50,offset:o}).then(d=>{setUnis(d);if(view==='university'&&!pick&&d.items?.[0])setPick(d.items[0])}).catch(e=>onError?.(e.message))}
  const loadItems=()=>{if(view==='kind'&&!kind){setItems(null);return}if(view==='university'&&!pick){setItems(null);return}setItems(null)
    rpc('items',view==='kind'?{kind,limit:200}:{provider_id:pick.provider_id,...(kind?{kind}:{}),limit:200}).then(setItems).catch(e=>onError?.(e.message))}
  useEffect(()=>{loadSum()},[])
  useEffect(()=>{setOffset(0);setPick(null);loadUnis(0)},[kind,q])
  useEffect(()=>{loadItems()},[pick?.provider_id,view,kind])
  const decided=r=>{setNote(`Done. ${r?.returns||''}`);loadSum();loadItems();if(view==='university')rpc('universities',{kind,q,limit:50,offset}).then(setUnis).catch(()=>{})}
  if(!sum)return <Loading label="Reading what needs a person…"/>
  const bk=sum.by_kind||{}
  return <div className="l4i" data-l4-inbox>
    <section className="l4i-tiles">
      <Metric label="Waiting for a person" value={fmtNumber(sum.total)} detail={`${fmtNumber(sum.universities)} universities`} icon={Inbox}/>
      <Metric label={`Older than ${sum.target_days} days`} value={fmtNumber(sum.late)} tone={Number(sum.late)?'warning':'success'} detail="Oldest first within each university" icon={AlertTriangle}/>
    </section>
    <div className="l4i-kinds" role="toolbar" aria-label="Kinds of decision">
      <button type="button" className={!kind?'on':''} onClick={()=>setKind('')}>All ({fmtNumber(sum.total)})</button>
      {order.filter(k=>bk[k]?.n).map(k=><button key={k} type="button" className={kind===k?'on':''} data-l4-kind={k} onClick={()=>setKind(k)}>{kinds[k].label} ({fmtNumber(bk[k].n)})</button>)}
    </div>
    <div className="l4i-bar">
      <div className="l4i-view">{[['university','By university'],['kind','By kind']].map(([v,l])=><button key={v} type="button" className={view===v?'on':''} onClick={()=>{setView(v);setNote('')}}>{l}</button>)}</div>
      {view==='university'&&<label className="l4i-search"><Search size={14}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Find a university…" aria-label="Find a university"/></label>}
      <Button compact onClick={()=>{loadSum();loadUnis(offset);loadItems()}}><RefreshCw size={14}/>Refresh</Button>
    </div>
    {note&&<p className="l4i-note" role="status">{note}</p>}
    {view==='kind'&&!kind?<Empty text="Choose a kind above to see its items across every university."/>:
    <div className={view==='university'?'l4i-split':''}>
      {view==='university'&&<aside className="l4i-unis" aria-label="Universities">
        {!unis?<Loading compact/>:(unis.items||[]).length===0?<Empty text="Nothing waits for a person."/>:<>
          <ul>{unis.items.map(u=><li key={u.provider_id||'platform'}><button type="button" className={pick?.provider_id===u.provider_id?'on':''} onClick={()=>{setPick(u);setNote('')}} data-l4-uni={u.name}>
            <strong>{u.name}</strong><small>{u.country||''}{u.courses!=null?` · ${fmtNumber(u.courses)} courses`:''}</small>
            <span className="l4i-uni-kinds">{Object.entries(u.by_kind||{}).sort((a,b)=>(kinds[a[0]]?.order||99)-(kinds[b[0]]?.order||99)).map(([k,n])=><em key={k}>{kinds[k]?.label||k}{n>1?` ${n}`:''}</em>)}</span>
            {u.late&&<span className="l4i-late">{days(u.oldest)} d</span>}</button></li>)}</ul>
          {Number(unis.total)>50&&<div className="l4i-pager"><Button compact disabled={offset===0} onClick={()=>{const o=Math.max(0,offset-50);setOffset(o);loadUnis(o)}}>Previous</Button><small>{offset+1}–{Math.min(offset+50,unis.total)} of {fmtNumber(unis.total)}</small><Button compact disabled={offset+50>=unis.total} onClick={()=>{const o=offset+50;setOffset(o);loadUnis(o)}}>Next</Button></div>}
        </>}
      </aside>}
      <section className="l4i-items" aria-label="Items">
        {view==='university'&&pick&&<header className="l4i-items-head"><h3>{pick.name}</h3><small>{pick.country||''}{pick.courses!=null?` · ${fmtNumber(pick.courses)} active courses`:''}</small></header>}
        {!items?<Loading compact/>:(items.items||[]).length===0?<Empty text="Nothing left here."/>:
          items.items.map(it=><Item key={`${it.kind}:${it.ref}`} it={it} k={kinds[it.kind]||{label:it.kind,choices:[]}} showProvider={view==='kind'} rank={sum.rank} onDone={decided} onError={onError}/>)}
        {items&&Number(items.total)>(items.items||[]).length&&<p className="l4i-more">Showing {fmtNumber(items.items.length)} of {fmtNumber(items.total)}.</p>}
      </section>
    </div>}
  </div>
}

function Item({it,k,showProvider,rank,onDone,onError}){
  const[open,setOpen]=useState(null),[reason,setReason]=useState(''),[value,setValue]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  const d=it.detail||{}
  const choose=c=>{setErr('');if(c.link){window.location.hash=linkFor(c.link,it).replace(/^#/,'');return}setOpen(c);setReason(c.reason||'');setValue(c.input==='url'&&it.kind==='course_link'?urlOf(d.proposed):'')}
  const go=async()=>{setBusy(true);setErr('');try{const r=await rpc('decide',{kind:it.kind,ref:it.ref,choice:open.key,reason,value});setOpen(null);onDone?.(r)}catch(e){setErr(e.message)}finally{setBusy(false)}}
  return <article className={`l4i-item${it.late?' late':''}`} data-l4-item={it.kind}>
    <header><StatusChip value={it.kind} tone={it.late?'warning':'info'} label={k.label}/>{showProvider&&it.provider&&<strong className="l4i-prov">{it.provider}</strong>}{it.subject&&<span className="l4i-subj">{it.subject}</span>}{d.course_code&&<span className="l4i-code" title="CRICOS code" data-l4-code>CRICOS {d.course_code}</span>}<small>{fmtDate(it.created_at)} · {days(it.created_at)} d</small></header>
    <p className="l4i-why">{it.why}</p>
    {it.kind==='course_link'&&(urlOf(d.before)||urlOf(d.proposed))&&<dl className="l4i-dl"><dt>Page we hold</dt><dd data-l4-held><PageLink u={urlOf(d.before)} title={it.subject}/></dd><dt>New page</dt><dd data-l4-new><PageLink u={urlOf(d.proposed)} title={it.subject}/></dd></dl>}
    {it.kind==='held_scholarship'&&<dl className="l4i-dl">{d.url&&<><dt>Page</dt><dd><a href={d.url} target="_blank" rel="noreferrer">{d.url} <ExternalLink size={11}/></a></dd></>}{it.suggestion&&<><dt>AI re-check</dt><dd>{it.suggestion}</dd></>}{d.audience_quote&&<><dt>Who</dt><dd><q>{d.audience_quote}</q></dd></>}{d.value_quote&&<><dt>Value</dt><dd><q>{d.value_quote}</q></dd></>}</dl>}
    <div className="l4i-choices">{(k.choices||[]).map(c=>{const low=c.rank&&rank<c.rank;return <button key={c.key} type="button" className={`${open?.key===c.key?'on':''}${c.link?' link':''}`} disabled={low} title={low?'Your role cannot make this choice':c.returns} onClick={()=>choose(c)} data-l4-choice={c.key}>{c.label}{c.link&&<ArrowRight size={12}/>}</button>})}</div>
    {open&&<div className="l4i-confirm">
      <p className="l4i-next"><strong>What happens next:</strong> {open.returns}</p>
      {open.input==='url'&&<input value={value} onChange={e=>setValue(e.target.value)} placeholder="https://…" aria-label="Web address"/>}
      <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why (kept with the decision)" aria-label="Reason"/>
      <Button compact variant="primary" disabled={busy||reason.trim().length<4||(open.input==='url'&&!/^https?:\/\/\S+\.\S+/.test(value.trim()))} onClick={go} data-l4-confirm>{busy?'Saving…':open.label}</Button>
      <Button compact onClick={()=>setOpen(null)}>Cancel</Button>
      {err&&<p className="l4i-err" role="alert">{err}</p>}
    </div>}
  </article>
}

// v2.15.299 (Platform Admin, 20 Oct 2026 09:41: "the course name is align to course url, there should be no confusion"): each address says
// whether its last part is the course's own name, or the course name with more words (a major or specialisation)
const slug=t=>String(t||'').toLowerCase().replace(/&/g,' and ').replace(/\([^)]*\)/g,m=>' '+m.slice(1,-1)+' ').replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'')
function nameMatch(u,title){if(!u||!title)return null;const last=String(u).replace(/[?#].*$/,'').replace(/\/+$/,'').split('/').pop().toLowerCase(),t=slug(title);if(!t)return null;if(last===t)return'name';if(last.startsWith(t+'-'))return'major';return null}
function PageLink({u,title}){if(!u)return'none';const m=nameMatch(u,title);return <><a href={u} target="_blank" rel="noreferrer">{u} <ExternalLink size={11}/></a>{m==='name'&&<em className="l4i-match ok" data-l4-match="name">matches the course name</em>}{m==='major'&&<em className="l4i-match warn" data-l4-match="major">a major or specialisation of the course</em>}</>}
