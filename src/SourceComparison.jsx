// Sources side by side (v2.15.107). Both sources are kept and shown; where they disagree the row is
// highlighted, never hidden.
//   Scholarship: the provider's own page (primary) next to the government source (Study Australia):
//                value, closing date, study levels.
//   Course:      the provider's course page next to the regulator (CRICOS): tuition, duration, campus.
// Read: public.admin_source_comparison(entity_type, id) (migration 20260930000000_cf247_admin_ui_reads).
import React,{useEffect,useState}from'react'
import{BookOpen,ExternalLink,Scale}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Loading,fmtDate,fmtMoney,fmtNumber}from'./ui-kit'

const money=(v,c='AUD')=>v==null||v===''?null:fmtMoney(Number(v),c||'AUD')
const NONE='Not stated'

// ---- scholarship value, date and level normalisation (exported for tests) ----
export function providerAmounts(value){
  if(!value||typeof value!=='object')return[]
  if(Array.isArray(value.amounts))return value.amounts.map(Number).filter(Number.isFinite)
  if(value.amount!=null&&Number.isFinite(Number(value.amount)))return[Number(value.amount)]
  return[]
}
export function providerValueText(value){
  if(!value||typeof value!=='object')return null
  const cur=value.currency||'AUD',amounts=providerAmounts(value)
  if(value.type==='fixed_amount'&&amounts.length)return money(amounts[0],cur)
  if(amounts.length)return `${value.up_to?'Up to ':''}${amounts.map(a=>money(a,cur)).join(' or ')}${value.type==='ambiguous'?' (page lists more than one amount)':''}`
  if(Array.isArray(value.percentages)&&value.percentages.length)return `${value.percentages.join('% or ')}% of tuition`
  if(value.percentage!=null)return `${value.percentage}% of tuition`
  return value.text||null
}
const LEVEL_OF={undergraduate:'ug_vet',vet:'ug_vet',diploma:'ug_vet',postgraduate:'postgraduate',postgraduate_coursework:'postgraduate',postgraduate_research:'postgraduate',research:'postgraduate',english:'english',elicos:'english',english_language:'english',school:'school',foundation:'foundation'}
const LEVEL_LABEL={ug_vet:'Undergraduate / VET',postgraduate:'Postgraduate',english:'English language',school:'School',foundation:'Foundation'}
export function providerLevels(levels){return[...new Set((Array.isArray(levels)?levels:[]).map(l=>LEVEL_OF[String(l).toLowerCase()]).filter(Boolean))].sort()}
export function governmentLevels(text,list){
  const out=new Set()
  for(const l of Array.isArray(list)?list:[])if(LEVEL_OF[String(l).toLowerCase()])out.add(LEVEL_OF[String(l).toLowerCase()])
  for(const part of String(text||'').split(',').map(x=>x.trim().toLowerCase()).filter(Boolean)){
    if(/undergraduate|vet/.test(part))out.add('ug_vet')
    else if(/postgrad|research/.test(part))out.add('postgraduate')
    else if(/english|elicos/.test(part))out.add('english')
    else if(/school/.test(part))out.add('school')
    else if(/foundation/.test(part))out.add('foundation')
  }
  return[...out].sort()
}
const sameSet=(a,b)=>a.length===b.length&&a.every((x,i)=>x===b[i])
const dayOf=v=>{const d=v&&!Number.isNaN(Date.parse(v))?new Date(v):null;return d?d.toISOString().slice(0,10):null}

/** Compare one row. Returns 'same' | 'differs' | 'provider_only' | 'government_only' | 'neither'. */
export function compareState(a,b,equal){const ha=a!=null&&a!=='',hb=b!=null&&b!=='';if(!ha&&!hb)return'neither';if(ha&&!hb)return'provider_only';if(!ha&&hb)return'government_only';return equal?'same':'differs'}

export function scholarshipRows(d){
  const p=d?.provider||{},g=d?.government||{}
  const pa=providerAmounts(p.value),ga=g.amount!=null?Number(g.amount):null
  const valueEqual=ga==null||pa.length===0?false:(pa.length===1&&pa[0]===ga)
  const pv=providerValueText(p.value),gv=g.value_text||(ga!=null?money(ga,g.currency):null)
  const pd=p.deadline?dayOf(p.deadline)||String(p.deadline):null,gd=g.closing_date?dayOf(g.closing_date):null
  const pl=providerLevels(p.levels),gl=governmentLevels(g.levels_text,g.study_levels)
  return[
    {key:'value',label:'Value',provider:pv,government:gv,state:compareState(pv,gv,valueEqual||(pa.length===0&&ga==null&&pv===gv))},
    {key:'closing',label:'Closing date',provider:pd?fmtDate(pd,pd):null,government:gd?fmtDate(gd):(g.closing_text||null),state:compareState(pd,gd||g.closing_text,pd&&gd&&pd===gd)},
    {key:'levels',label:'Study levels',provider:pl.length?pl.map(l=>LEVEL_LABEL[l]).join(', '):null,government:gl.length?gl.map(l=>LEVEL_LABEL[l]).join(', '):(g.levels_text||null),state:compareState(pl.length?pl:null,gl.length?gl:(g.levels_text||null),sameSet(pl,gl))},
  ]
}

const BASIS={annual:'per year',indicative_annual:'per year',total_indicative:'whole course',registered_total_course:'whole course'}
const basisWord=b=>BASIS[b]||(String(b||'').includes('annual')?'per year':String(b||'').replaceAll('_',' '))
const weeksText=d=>d&&d.value!=null?(d.unit==='weeks'?`${fmtNumber(Number(d.value))} weeks${Number(d.value)%52===0?` (${fmtNumber(Number(d.value)/52)} year${Number(d.value)===52?'':'s'})`:''}`:`${fmtNumber(Number(d.value))} ${d.unit||''}`.trim()):null
export function courseRows(d){
  const p=d?.provider||{},r=d?.regulator||{},pt=p.tuition,rt=r.tuition
  let tuitionState=compareState(pt?.amount,rt?.amount,false),tuitionNote=''
  if(pt?.amount!=null&&rt?.amount!=null){
    const perYear=basisWord(pt.basis)==='per year'
    const other=perYear?rt.per_year_estimate:rt.amount
    if(other==null){tuitionState='differs';tuitionNote='Different basis: the provider shows a yearly fee and the regulator a whole-course total.'}
    else{const diff=Math.round(Number(pt.amount)-Number(other));tuitionState=Math.abs(diff)<1?'same':'differs';if(diff)tuitionNote=`Provider page is ${money(Math.abs(diff),pt.currency)} ${diff>0?'higher':'lower'}${perYear?' a year':''}.`}
  }
  return[
    {key:'tuition',label:'Tuition',state:tuitionState,note:tuitionNote,
      provider:pt?.amount!=null?`${money(pt.amount,pt.currency)} ${basisWord(pt.basis)}`:null,providerSub:pt?[pt.fee_year?`${pt.fee_year} fees`:'',pt.source_type==='provider_fee_schedule'?'from the provider fee schedule':''].filter(Boolean).join(' · '):'',providerEvidence:pt?.evidence_id,
      government:rt?.amount!=null?`${money(rt.amount,rt.currency)} ${basisWord(rt.basis)}`:null,governmentSub:rt?.per_year_estimate!=null?`about ${money(rt.per_year_estimate,rt.currency)} a year over ${weeksText(r.duration)||'the course'}`:'',governmentEvidence:rt?.evidence_id},
    {key:'duration',label:'Duration',state:compareState(weeksText(p.duration),weeksText(r.duration),weeksText(p.duration)===weeksText(r.duration)),provider:weeksText(p.duration),government:weeksText(r.duration)},
    {key:'campus',label:'Campus',state:compareState(p.campuses?.length?p.campuses:null,r.campuses?.length?r.campuses:null,JSON.stringify([...(p.campuses||[])].sort())===JSON.stringify([...(r.campuses||[])].sort())),provider:p.campuses?.length?p.campuses.join('; '):null,government:r.campuses?.length?r.campuses.join('; '):null},
  ]
}

function Cell({value,sub,evidence,empty,navigate,label}){return <td data-label={label}>{value??<span className="cf-muted-text">{empty}</span>}{sub&&<small>{sub}</small>}{evidence&&navigate&&<small><button type="button" className="cf-btn compact" onClick={()=>navigate('Evidence',{evidence_id:evidence})}><BookOpen size={12}/>Evidence</button></small>}</td>}

export default function SourceComparison({type,id,navigate}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState('')
  useEffect(()=>{if(!id)return;let live=true;setBusy(true);setError('');supabase.rpc('admin_source_comparison',{p_entity_type:type,p_id:id}).then(({data:d,error:e})=>{if(!live)return;if(e)setError(e.message);else setData(d)}).finally(()=>live&&setBusy(false));return()=>{live=false}},[type,id])
  if(busy)return <section className="sc-panel"><Loading compact label="Comparing sources…"/></section>
  if(error)return <section className="sc-panel"><h3>Sources side by side</h3><p className="sc-summary">The comparison could not be loaded: {error}</p></section>
  if(!data)return null
  const isCourse=type==='course',p=data.provider||{},g=isCourse?(data.regulator||{}):(data.government||{})
  const rows=isCourse?courseRows(data):scholarshipRows(data)
  const leftLabel='Provider page',rightLabel=isCourse?'Regulator (CRICOS)':'Government (Study Australia)'
  const differs=rows.filter(r=>r.state==='differs').length
  const emptyLeft=isCourse?'Not read from the provider page yet':NONE,emptyRight=NONE
  return <section className="sc-panel" data-source-comparison={type}>
    <h3><Scale size={15}/> Sources side by side</h3>
    <p className="sc-summary">{differs?`${differs} value${differs===1?' differs':'s differ'} between the two sources (highlighted). Both are kept; the provider page is the primary source.`:'Where both sources state a value, they agree.'}</p>
    <div className="sc-src"><strong>{leftLabel}:</strong>{p.url?<a href={p.url} target="_blank" rel="noreferrer">{p.url} <ExternalLink size={11}/></a>:<span>No provider page linked yet</span>}{p.read_at&&<span>read {fmtDate(p.read_at)}</span>}{!isCourse&&p.evidence_id&&navigate&&<button type="button" className="cf-btn compact" onClick={()=>navigate('Evidence',{evidence_id:p.evidence_id})}><BookOpen size={12}/>Evidence</button>}</div>
    <div className="sc-src"><strong>{rightLabel}:</strong>{isCourse?(g.cricos_code?<span>CRICOS course code {g.cricos_code}</span>:<span>No CRICOS registration found</span>):(g.url?<a href={g.url} target="_blank" rel="noreferrer">{g.url} <ExternalLink size={11}/></a>:<span>Not listed on Study Australia</span>)}{!isCourse&&g.observed_at&&<span>read {fmtDate(g.observed_at)}</span>}{!isCourse&&g.evidence_id&&navigate&&<button type="button" className="cf-btn compact" onClick={()=>navigate('Evidence',{evidence_id:g.evidence_id})}><BookOpen size={12}/>Evidence</button>}</div>
    <div className="cf-table-wrap"><table className="cf-kv-table"><thead><tr><th/><th>{leftLabel}</th><th>{rightLabel}</th></tr></thead><tbody>
      {rows.map(r=><tr key={r.key} className={r.state==='differs'?'cf-diff':''} data-compare-state={r.state}>
        <th>{r.label}{r.state==='differs'&&<span className="sc-diff-tag">Differs</span>}{r.state==='provider_only'&&<span className="sc-diff-tag is-one-sided">Only on the provider page</span>}{r.state==='government_only'&&<span className="sc-diff-tag is-one-sided">Only in {rightLabel}</span>}{r.note&&<small>{r.note}</small>}</th>
        <Cell label={leftLabel} value={r.provider} sub={r.providerSub} evidence={r.providerEvidence} empty={emptyLeft} navigate={navigate}/>
        <Cell label={rightLabel} value={r.government} sub={r.governmentSub} evidence={r.governmentEvidence} empty={emptyRight} navigate={navigate}/>
      </tr>)}
    </tbody></table></div>
    {!isCourse&&data.current?.value_text&&<p className="sc-summary">The catalogue currently shows: <b>{data.current.value_text}</b>.</p>}
  </section>
}
