// CF-247 AER Phase B (Platform Admin mandate 2 Nov 2026 14:45, §13 and §15): academic entry requirements on Coverage & completeness.
// Four measures, each a count of eligible AU/NZ providers over the same denominator (never every country of the reference table, and one
// provider's row count cannot hide another's gap): source discovery, extraction, verified admission and consumer-resolvable. Open P0/P1/P2,
// new, resolved and reopened gaps, progress over 7 and 30 days, the root causes (one per defect, linked to every provider it affects), and a
// provider drill-down with the next action and its owner. Read through public.admin_aer('coverage' / 'coverage_provider'): Curator (rank 3)
// and above; viewers and counsellors are not shown it and the server refuses them. Read-only: nothing here changes data.
import React,{useEffect,useState}from'react'
import{GraduationCap,RefreshCw}from'lucide-react'
import{Button,Metric,StatusChip,EmptyInline,fmtDateTime,fmtNumber,fmtShare}from'./ui-kit'
import{aer}from'./AerWorkspace'
import{plainError}from'./lib/errors'

export const AER_MIN_RANK=3
const MEASURES=[['discovery_n','Source discovery','Eligible providers with an official AER source read'],
  ['extraction_n','Extraction','Providers whose read sources have no open extraction gap'],
  ['admission_n','Verified admission','Providers with active requirements and none waiting for Layer 4'],
  ['consumer_n','Consumer-resolvable','Providers with a course that resolves to an admitted requirement, no open P0']]
const SEV_TONE={P0:'danger',P1:'warning',P2:'info'}
const STATE_TONE={open:'warning',reopened:'danger',resolved:'success'}
const COUNTRY={ALL:'AU and NZ',AU:'Australia',NZ:'New Zealand'}
const PAGE=50
// Platform Admin 2 Nov 2026 15:43: report dispositions of the catalogue-first gap queue (report words, not admission statuses)
export const DISPOSITIONS=[['source_held','Source held','warning'],['reader_failed','Reader failed','danger'],['not_discovered','Not discovered','neutral'],
  ['awaiting_layer4','Awaiting Layer 4','info'],['course_only','Course-level only','info'],['source_not_published_evidenced','Not published (evidenced)','neutral'],
  ['not_applicable_evidenced','Not applicable (evidenced)','neutral'],['active_verified','Active and verified','success']]
// Layer 4 recovery mandate (2 Nov 2026 16:33 §9): readiness classes of pending AER items (report classes, not Layer 4 statuses)
export const READINESS=[['review_ready','Review-ready'],['reader_correction_required','Reader correction required'],['evidence_required','Evidence required'],
  ['superseded_invalid','Superseded or invalid'],['awaiting_human_review','Awaiting human review']]
const DISP=Object.fromEntries(DISPOSITIONS.map(([k,l,t])=>[k,{label:l,tone:t}]))
const STATE_WORD={not_discovered:'no source',source_read:'source read',source_unreadable:'source unreadable',none:'none',complete:'complete',held:'held',failed:'failed',
  active:'active',awaiting:'awaiting Layer 4',active_and_awaiting:'active, more awaiting'}

export default function AerCoverage({rank}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState('')
  const[sev,setSev]=useState(''),[country,setCountry]=useState(''),[cause,setCause]=useState(''),[q,setQ]=useState(''),[offset,setOffset]=useState(0),[disp,setDisp]=useState('')
  const[open,setOpen]=useState(null),[detail,setDetail]=useState(null)
  const load=()=>{setBusy(true);setError('');aer('coverage',{severity:sev,country,root_cause:cause,disposition:disp,q,offset,page_size:PAGE}).then(setData).catch(e=>setError(plainError(e))).finally(()=>setBusy(false))}
  useEffect(()=>{if(rank>=AER_MIN_RANK)load()},[rank,sev,country,cause,disp,offset])
  useEffect(()=>{if(!open){setDetail(null);return}aer('coverage_provider',{provider_id:open}).then(setDetail).catch(e=>setError(plainError(e)))},[open])
  if(rank<AER_MIN_RANK)return null
  const all=(data?.measures||[]).find(m=>m.country==='ALL'),byCountry=(data?.measures||[]).filter(m=>m.country!=='ALL')
  const prog=Object.fromEntries((data?.progress||[]).map(p=>[p.days,p]))
  const delta=(k,d)=>{const p=prog[d];if(!p||!all)return'—';const n=Number(all[k]||0)-Number(p[k]||0);return`${n>0?'+':''}${fmtNumber(n)}`}
  const prov=data?.providers||{}
  return <section className="cc-panel" data-aer-coverage>
    <header><div><h2><GraduationCap size={14}/> Academic entry requirements</h2>
      <p>Four measures over the same eligible AU/NZ providers (active, published, enrolling international students). A source that was read is not counted as extracted, and extracted requirements are not counted until Layer 4 admits them.</p></div>
      <div className="aer-cov-head"><small data-aer-asat>{data?.as_at?`Reconciled ${fmtDateTime(data.as_at)}`:'Not reconciled yet'}{data?.job?` · hourly job ${data.job.active?'on':'paused'}`:''}</small>
        <Button compact className="cf-icon-btn" title="Refresh" aria-label="Refresh" onClick={load} disabled={busy}><RefreshCw size={14}/></Button></div></header>
    {error&&<div className="dq-alert" role="alert">{error}</div>}
    {!busy&&!all&&<EmptyInline text="No reconciliation yet: the hourly AER reconciliation (aer-reconcile) has not run."/>}
    {all&&<>
      <div className="cf-metric-grid" data-aer-measures>
        {MEASURES.map(([k,l,d])=><div key={k} data-aer-measure={k}><Metric label={l} value={`${fmtNumber(all[k])} of ${fmtNumber(all.eligible)}`} detail={`${fmtShare(Number(all[k]||0),Number(all.eligible||0))} · ${d}`}/></div>)}
      </div>
      <div className="dq-table-wrap"><table className="dq-table cc-table" data-aer-by-country><thead><tr><th>Country</th><th className="num">Eligible</th>{MEASURES.map(([k,l])=><th key={k} className="num">{l}</th>)}<th className="num">P0</th><th className="num">P1</th><th className="num">P2</th></tr></thead>
        <tbody>{[all,...byCountry].map(m=><tr key={m.country} data-aer-country={m.country}><td><strong>{COUNTRY[m.country]||m.country}</strong></td><td className="num">{fmtNumber(m.eligible)}</td>
          {MEASURES.map(([k])=><td key={k} className="num">{fmtNumber(m[k])}</td>)}<td className="num">{fmtNumber(m.open_p0)}</td><td className="num">{fmtNumber(m.open_p1)}</td><td className="num">{fmtNumber(m.open_p2)}</td></tr>)}</tbody></table></div>
      <div className="cf-metric-grid" data-aer-open>
        {['P0','P1','P2'].map(s=><button key={s} type="button" className={`aer-sev${sev===s?' is-on':''}`} aria-pressed={sev===s} data-aer-sev={s} onClick={()=>{setOffset(0);setSev(sev===s?'':s)}}>
          <StatusChip tone={SEV_TONE[s]} label={s}/> <strong>{fmtNumber(data.open?.[s]||0)}</strong> open</button>)}
        <Metric label="Last 7 days" value={`${fmtNumber(data.changes_7d?.opened||0)} new`} detail={`${fmtNumber(data.changes_7d?.resolved||0)} resolved · ${fmtNumber(data.changes_7d?.reopened||0)} reopened`}/>
        <Metric label="Progress" value={`${delta('consumer_n',7)} in 7 days`} detail={`Consumer-resolvable providers; ${delta('consumer_n',30)} in 30 days`}/>
      </div>
      <p className="cc-note" data-aer-detail>Countries with active requirements: {fmtNumber(all.detail?.countries_published)} · qualifications: {fmtNumber(all.detail?.qualifications_active)} · postgraduate course rows active {fmtNumber(all.detail?.postgraduate?.active_rows)}, waiting {fmtNumber(all.detail?.postgraduate?.proposed_rows)} · Layer 4 waiting: {fmtNumber(Object.values(all.detail?.layer4_pending||{}).reduce((a,n)=>a+Number(n||0),0))}{(data.alerts||[]).length>0&&<strong data-aer-alert> · Critical: {data.alerts.map(a=>a.title).join('; ')}</strong>}</p>
      <h3>Layer 4 review readiness</h3>
      <p className="cc-note" data-aer-readiness>Pending AER items: {READINESS.map(([k,l])=>`${l} ${fmtNumber(data.readiness?.[k]||0)}`).join(' · ')}. Classes are reported here only; decisions stay in Layer 4, one item at a time.</p>
      {data.weekly&&!data.weekly.error&&<details className="m-admin-advanced" data-aer-weekly><summary>Weekly report, week of {data.weekly.week_start}{data.weekly_email?' · e-mailed on Monday':' · Monday e-mail off'}</summary>
        <ul>{MEASURES.map(([k,l])=>{const w=data.weekly.measures?.[k.replace('_n','')];return <li key={k}>{l}: {w?`${fmtNumber(w.n)} of ${fmtNumber(w.of)} (prior week ${w.prior_week==null?'—':fmtNumber(w.prior_week)})`:'not measured'}</li>})}
          <li>Opened {fmtNumber(data.weekly.changes?.opened||0)}, resolved {fmtNumber(data.weekly.changes?.resolved||0)}, reopened {fmtNumber(data.weekly.changes?.reopened||0)}</li>
          <li>Providers with no progress: {fmtNumber(data.weekly.no_progress_providers||0)} · entry-matrix AI spend US${Number(data.weekly.spend_usd||0).toFixed(2)}</li>
          <li>Decisions for the Platform Admin: {(data.weekly.decisions||[]).join('; ')||'none'}</li></ul></details>}
      <h3>Root causes</h3>
      <div className="dq-table-wrap"><table className="dq-table" data-aer-root-causes><thead><tr><th>Root cause</th><th>Severity</th><th className="num">Providers</th><th className="num">Findings</th><th>Next action</th><th>Owner</th></tr></thead>
        <tbody>{(data.root_causes||[]).map(r=><tr key={r.code} data-aer-cause={r.code}><td><button type="button" className="dq-entity-link" onClick={()=>{setOffset(0);setCause(cause===r.code?'':r.code)}}><strong>{r.label}</strong></button></td>
          <td><StatusChip tone={SEV_TONE[r.severity]} label={r.severity}/></td><td className="num">{fmtNumber(r.providers)}</td><td className="num">{fmtNumber(r.findings)}</td><td>{r.next_action}</td><td>{r.owner_role}</td></tr>)}</tbody></table></div>
      <h3>Gap queue</h3>
      <p className="cc-note" data-aer-population>{data.population?<>Eligible providers this run: {Object.entries(data.population.by_country||{}).map(([c,v])=>`${COUNTRY[c]||c} ${fmtNumber(v.eligible)} (baseline ${fmtNumber(v.baseline)}, ${v.delta===0?'no change':`${v.delta>0?'+':''}${fmtNumber(v.delta)}`})`).join(' · ')}
        {(data.population.joined||[]).length>0&&` · joined ${fmtNumber(data.population.joined.length)}`}{(data.population.left||[]).length>0&&` · left ${fmtNumber(data.population.left.length)}`}</>:'Population not reconciled yet.'} Universities and tertiary providers come first, with held sources next to them.</p>
      <div className="pg-views" role="toolbar" aria-label="Disposition" data-aer-dispositions>
        {DISPOSITIONS.map(([k,l])=><button key={k} type="button" className={`pg-view${disp===k?' is-on':''}`} aria-pressed={disp===k} data-aer-disposition={k} onClick={()=>{setOffset(0);setDisp(disp===k?'':k)}}>{l} <strong>{fmtNumber(data.dispositions?.[k]||0)}</strong></button>)}
      </div>
      <section className="cf-filterbar" aria-label="AER provider filters">
        <label><span>Country</span><select className="fv-filter" value={country} onChange={e=>{setOffset(0);setCountry(e.target.value)}} aria-label="AER country"><option value="">AU and NZ</option><option value="AU">Australia</option><option value="NZ">New Zealand</option></select></label>
        <input className="au-search" type="search" value={q} onChange={e=>setQ(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'){setOffset(0);load()}}} placeholder="Provider name, then Enter" aria-label="Find a provider"/>
        {(sev||cause||disp)&&<Button compact onClick={()=>{setSev('');setCause('');setDisp('');setOffset(0)}}>Clear filters</Button>}
      </section>
      <div className="dq-table-wrap"><table className="dq-table" data-aer-providers><thead><tr><th className="num">#</th><th>Provider</th><th>Country</th><th>Disposition</th><th>Discovery · extraction · admission</th><th className="num">Sources</th><th className="num">P0</th><th className="num">P1</th><th className="num">P2</th><th>Next action</th><th>Owner</th></tr></thead>
        <tbody>{(prov.items||[]).map(p=><React.Fragment key={p.provider_id}><tr data-aer-provider={p.provider_id}>
          <td className="num">{fmtNumber(p.priority)}</td><td><button type="button" className="dq-entity-link" aria-expanded={open===p.provider_id} onClick={()=>setOpen(open===p.provider_id?null:p.provider_id)}><strong>{p.name}</strong></button>{p.primary_url&&<small><a className="cf-link" href={p.primary_url} target="_blank" rel="noreferrer">Official AER page</a></small>}</td>
          <td>{p.country}</td><td data-aer-disp={p.disposition}><StatusChip tone={DISP[p.disposition]?.tone||'neutral'} label={DISP[p.disposition]?.label||p.disposition}/></td>
          <td data-aer-states><small>{[p.discovery,p.extraction,p.admission].map(x=>STATE_WORD[x]||x).join(' · ')}</small></td><td className="num">{fmtNumber(p.sources)}</td>
          <td className="num">{fmtNumber(p.p0)}</td><td className="num">{fmtNumber(p.p1)}</td><td className="num">{fmtNumber(p.p2)}</td><td>{p.next_action||'Nothing open'}</td><td>{p.owner_role||'—'}</td></tr>
          {open===p.provider_id&&<tr className="aer-cov-detail"><td colSpan={11}><ProviderDetail d={detail}/></td></tr>}</React.Fragment>)}</tbody></table></div>
      <footer className="dq-pager"><button disabled={offset===0||busy} onClick={()=>setOffset(Math.max(0,offset-PAGE))}>Previous</button><span data-aer-total>{fmtNumber(Math.min(offset+1,prov.total||0))}–{fmtNumber(Math.min(offset+PAGE,prov.total||0))} of {fmtNumber(prov.total)}</span><button disabled={offset+PAGE>=(prov.total||0)||busy} onClick={()=>setOffset(offset+PAGE)}>Next</button></footer>
    </>}
  </section>
}

function ProviderDetail({d}){
  if(!d)return <span>Loading…</span>
  return <div className="aer-cov-provider" data-aer-provider-detail>
    <p>Active: {fmtNumber(d.active?.rows)} rows · {(d.active?.countries||[]).join(', ')||'no countries'} · {fmtNumber(d.active?.qualifications)} qualifications · course requirements active {fmtNumber(d.course?.active)}, waiting {fmtNumber(d.course?.proposed)}</p>
    <ul className="aer-cov-sources">{(d.sources||[]).map(s=><li key={s.id} data-aer-source={s.id}><a className="cf-link" href={s.url} target="_blank" rel="noreferrer">{s.title||s.url}</a> <small>{s.status}{s.shape?` · ${s.shape.replace(/_/g,' ')}`:''}{s.expected!=null?` · ${fmtNumber(s.matched)} of ${fmtNumber(s.expected)} cells`:''}{s.reason?` · ${s.reason}`:''}</small></li>)}</ul>
    <ul className="aer-cov-findings">{(d.findings||[]).map(f=><li key={f.id} data-aer-finding={f.state}><StatusChip tone={SEV_TONE[f.severity]} label={f.severity}/> <StatusChip tone={STATE_TONE[f.state]} label={f.state==='reopened'?`Reopened (${f.reopen_count})`:f.state==='resolved'?'Resolved':'Open'}/> <strong>{f.label}</strong>{f.scope?` · ${f.scope}`:''}{f.study_level?` · ${f.study_level}`:''} <small>first seen {fmtDateTime(f.first_seen)}, last seen {fmtDateTime(f.last_seen)} · {f.next_action} ({f.owner_role})</small></li>)}</ul>
  </div>
}
