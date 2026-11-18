// CF-247 RM0F (Platform Admin 17 Nov 2026 13:12; decisions G-2, G-3, G-4 approved 11:52; admin DESTINATION-DATA-UI-AND-INGESTION-SPEC.md v1.2):
// the Destination data page. Country and city datasets the website and Zoho read through the API v3 destination action: editions, localities and
// their postcodes, city figures, study rules and career outcomes, each with its source, attribution and approval.
// Reads: public.admin_destination_overview and admin_destination_review (Curator, rank 3, and above; the server refuses lower roles).
// Changes: a row's status and an edition's terms and publication are the Platform Admin's (rank 6) and always carry a reason; settling a postcode
// is Curator and above, also with a reason. A control a role cannot use is shown disabled and says which role it needs; the server is the check.
// Nothing here loads data: loads are scheduled jobs (Platform health › Data delivery › Destination loads).
import{CLIMATE_ICONS,climateIcon}from'./lib/climate-icons.js'
import React,{useCallback,useEffect,useState}from'react'
import{ExternalLink,RefreshCw}from'lucide-react'
import{Button,StatusChip,EmptyInline,Metric,fmtDate,fmtDateTime,fmtNumber}from'./ui-kit'
import{supabase}from'./lib/supabase'
import{plainError}from'./lib/errors'
import{draftEditions}from'./lib/destination-drafts'
import'./destination-data.css'

const TONE={approved:'success',published:'success',draft:'neutral',in_review:'warning',pending:'warning',restricted:'danger',withdrawn:'danger',superseded:'neutral'}
const Status=({v})=><StatusChip tone={TONE[v]||'neutral'} label={String(v||'—').replace('_',' ')}/>
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept with the decision):`);return r&&r.trim().length>=4?r.trim():null}
const sum=o=>Object.values(o||{}).reduce((a,b)=>a+Number(b||0),0)
const pick=(o,re)=>Object.entries(o||{}).filter(([k])=>re.test(k)).reduce((a,[,v])=>a+Number(v||0),0)
const pct=v=>v==null?'—':`${Math.round(Number(v)*1000)/10}%`
const Src=({url,label})=>url?<a className="cf-link" href={url} target="_blank" rel="noreferrer">{label||(()=>{try{return new URL(url).hostname.replace(/^www\./,'')}catch{return'Source'}})()} <ExternalLink size={11}/></a>:<em>No source</em>

// one guarded action: disabled below its rank, asks for the reason, calls the function, reloads
function Act({label,need,rank,primary,onRun,data}){
  const ok=rank>=need
  return <Button compact variant={primary?'primary':undefined} disabled={!ok} title={ok?undefined:`Needs ${need>=6?'Platform Admin':'Curator'}`} data-dst-action={data} onClick={onRun}>{label}</Button>
}

function useList(rpc,kind,status,tick){
  const[rows,setRows]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{let live=true;setRows(null);setErr('')
    Promise.resolve(rpc('admin_destination_review',{p_kind:kind,p_status:status||null})).then(({data,error})=>{if(!live)return;if(error)setErr(plainError(error));else setRows(data?.rows||[])}).catch(e=>{if(live)setErr(plainError(e))})
    return()=>{live=false}},[kind,status,tick])
  return{rows,err}
}
const Wait=({rows,err,empty,children})=>err?<EmptyInline text={err}/>:!rows?<p className="sl-sub">Loading…</p>:!rows.length?<EmptyInline text={empty}/>:children
const StatusFilter=({value,onChange,options})=><div className="pg-views" role="toolbar" aria-label="Status">{[['','All'],...options.map(o=>[o,o.replace('_',' ')])].map(([k,l])=>
  <button key={k||'all'} type="button" className={`pg-view${value===k?' is-on':''}`} aria-pressed={value===k} onClick={()=>onChange(k)}>{l}</button>)}</div>

function Overview({o,rank,run}){
  const eds=o.editions_list||[],loc=o.localities||{},pc=o.locality_postcodes||{}
  return <div className="dst-stack" data-dst-tab="overview">
    <div className="dst-metrics">
      <Metric label="Editions published" value={fmtNumber(eds.filter(e=>e.status==='published').length)} detail={`${fmtNumber(eds.length)} editions held`}/>
      <Metric label="Editions waiting on terms" value={fmtNumber(eds.filter(e=>e.terms_status!=='approved').length)} tone={eds.some(e=>e.terms_status!=='approved')?'warning':'neutral'}/>
      <Metric label="Localities approved" value={fmtNumber(Number(loc.approved||0)+Number(loc.published||0))} detail={`${fmtNumber(sum(loc))} held`}/>
      <Metric label="Campuses waiting on a locality" value={fmtNumber(o.campuses_waiting_locality||0)} detail="Layer 4 Review › Inbox › Campus locality" tone={o.campuses_waiting_locality?'warning':'neutral'}/>
      <Metric label="Study rules approved" value={fmtNumber(pick(o.study_rules,/:approved$/))} detail={`${fmtNumber(sum(o.study_rules))} held`}/>
      <Metric label="Career outcomes approved" value={fmtNumber(Number(o.career_outcomes?.approved||0)+Number(o.career_outcomes?.published||0))} detail={`${fmtNumber(sum(o.career_outcomes))} held`}/>
    </div>
    <section className="m-panel"><h3>Editions</h3>
      <p className="sl-sub">An edition is one release of a source for one country. It publishes only once its terms of use are approved, and rows left in draft when it publishes are never returned by the API. A published edition is fixed: a change is a new edition.</p>
      {!eds.length?<EmptyInline text="No edition is loaded yet. Study rules and career outcomes arrive as editions from their load jobs (Platform health › Data delivery › Destination loads)."/>:
      <div className="dst-scroll"><table className="cf-table" data-dst-editions><thead><tr><th>Country</th><th>Dataset</th><th>Edition</th><th>Source owner</th><th>Terms of use</th><th>Attribution</th><th>Rows</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody>{eds.map(e=><tr key={e.edition_id} data-dst-edition={e.edition_id}>
          <td>{e.country_code}</td><td>{String(e.domain).replace('_',' ')}</td><td>{e.edition_label}<small className="dst-sub">from {fmtDate(e.effective_from)}{e.effective_to?` to ${fmtDate(e.effective_to)}`:''}</small></td>
          <td>{e.source_owner} <Src url={e.source_url}/></td><td><Status v={e.terms_status}/></td>
          <td>{e.attribution_present?<StatusChip tone="success" label="Present" title={e.attribution_text}/>:<StatusChip tone="danger" label="Missing"/>}</td>
          <td className="num">{fmtNumber(e.rows||0)}{e.rows_approved!=null&&<small className="dst-sub">{fmtNumber(e.rows_approved)} approved</small>}</td><td><Status v={e.status}/></td>
          <td>{e.status==='published'?<small className="dst-sub">Fixed. A change is a new edition.</small>:<span className="dst-actions">
            <Act label="Record terms" need={6} rank={rank} data="edition-terms" onRun={()=>{const t=window.prompt('Terms of use for this edition: approved, pending or restricted','approved');if(!t)return;const r=ask(`Record terms "${t.trim()}" for ${e.country_code} ${e.edition_label}`);if(r)run('admin_destination_edition_set_terms',{p_edition:e.edition_id,p_terms:t.trim(),p_reason:r})}}/>
            <Act label="Publish edition" need={6} rank={rank} primary data="edition-publish" onRun={()=>{const r=ask(`Publish ${e.country_code} ${String(e.domain).replace('_',' ')} ${e.edition_label}. ${fmtNumber(e.rows_approved||0)} of ${fmtNumber(e.rows||0)} rows are approved; the rest are never returned`);if(r)run('admin_destination_edition_publish',{p_edition:e.edition_id,p_reason:r})}}/></span>}</td>
        </tr>)}</tbody></table></div>}
    </section>
    <section className="m-panel" data-dst-health><h3>Publish health</h3><ul className="dst-facts">
      <li><span>Localities without attribution text</span><strong>{fmtNumber(o.localities_without_attribution||0)}</strong></li>
      <li><span>Postcode shares held</span><strong>{fmtNumber(pc.rows||0)}</strong></li>
      <li><span>Postcodes with a primary match ({pct(o.postcode_primary_min_share)} or more of the postcode)</span><strong>{fmtNumber(pc.primary||0)}</strong></li>
      <li><span>Postcodes waiting for a person</span><strong>{fmtNumber(pc.postcodes_needing_review||0)}</strong></li>
      <li><span>Registration and field-of-study schemes registered</span><strong>{fmtNumber(sum(o.registration_schemes))}</strong></li>
    </ul><p className="sl-sub">Counted live at {fmtDateTime(o.checked_at)}. The API v3 destination action returns only approved or published rows.</p></section>
  </div>
}

// v2.16.31 (Platform Admin 18 Nov 2026 07:39): Bulk Approve Drafts. One line per dataset edition that has draft localities in the list shown: how many are
// ready (name and attribution present) and how many would be left, with one button for the Platform Admin. The server approves the edition's clean drafts
// only, with the one reason kept on every row and one control event (public.admin_destination_localities_bulk_approve).
// v2.16.32 (Platform Admin 18 Nov 2026 10:05): the same action for city figures (kind="figure", public.admin_destination_figures_bulk_approve).
const BULK={locality:{one:'locality is',many:'localities are',noun:'localities',left:'without attribution text',fn:'admin_destination_localities_bulk_approve',data:'locality-bulk-approve',none:'No draft locality of this edition has attribution text, so none can be approved.',after:'Each becomes available to the API',foot:'One reason is kept with every locality approved and the action is recorded once in the control log. Figures and study rules are approved on their own tabs.'},
  figure:{one:'figure is',many:'figures are',noun:'figures',left:'without attribution text',fn:'admin_destination_figures_bulk_approve',data:'metric-bulk-approve',none:'No draft figure of this edition has attribution text, so none can be approved.',after:'A figure is returned by the API once its locality is approved too',foot:'One reason is kept with every figure approved and the action is recorded once in the control log. Localities are approved on Localities & postcodes.'}}
function BulkApprove({rows,rank,run,kind='locality'}){const eds=draftEditions(rows,kind),w=BULK[kind]
  if(!eds.length)return null
  return <div className="dst-bulk" data-dst-bulk={kind}>{eds.map(e=><p key={e.edition} className="dst-bulk-row" data-dst-bulk-edition={e.edition}>
    <span><b>{e.edition}</b>: {fmtNumber(e.ready)} draft {e.ready===1?w.one:w.many} ready to approve{e.left?<>; {fmtNumber(e.left)} {w.left} will be left as draft</>:null}.</span>
    <Act label="Bulk Approve Drafts" need={6} rank={rank} primary data={w.data} onRun={()=>{if(!e.ready)return window.alert(w.none)
      const r=ask(`Approve all ${e.ready} clean draft ${w.noun} of ${e.edition}${e.left?` (${e.left} ${w.left} stay draft)`:''}. ${w.after}`);if(r)run(w.fn,{p_dataset_edition:e.edition,p_reason:r})}}/></p>)}
    <p className="sl-sub">{w.foot}</p></div>}

function Localities({rpc,rank,run,tick,share}){
  const[status,setStatus]=useState('')
  const loc=useList(rpc,'locality',status,tick),pcs=useList(rpc,'postcode','',tick)
  return <div className="dst-stack" data-dst-tab="localities">
    <section className="m-panel"><h3>Localities</h3>
      <p className="sl-sub">One official geography unit per boundary edition, for example an ABS Significant Urban Area on ASGS Edition 3. A locality reaches the API once it is approved.</p>
      <StatusFilter value={status} onChange={setStatus} options={['draft','in_review','approved','published','withdrawn']}/>
      <BulkApprove rows={loc.rows||[]} rank={rank} run={run}/>
      <Wait {...loc} empty="No locality is loaded yet. The ABS population and postcode load creates them (Platform health › Data delivery › Destination loads).">
        <div className="dst-scroll"><table className="cf-table" data-dst-localities><thead><tr><th>Locality</th><th>Geography</th><th>Boundary</th><th>Edition</th><th>Attribution</th><th>Postcodes</th><th>Figures</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>{(loc.rows||[]).map(l=><tr key={l.id} data-dst-locality={l.id}><td>{l.name}<small className="dst-sub">{l.country_code}</small></td><td>{l.geography_type} {l.geography_code}</td><td>{l.boundary_vintage}</td><td>{l.dataset_edition}</td>
            <td>{l.attribution_text||<StatusChip tone="danger" label="Missing"/>}</td>
            <td className="num">{fmtNumber(l.postcodes_primary||0)} primary{l.postcodes_review?<small className="dst-sub">{fmtNumber(l.postcodes_review)} to review</small>:null}</td><td className="num">{fmtNumber(l.metrics||0)}</td><td><Status v={l.status}/></td>
            <td><span className="dst-actions">{!['approved','published'].includes(l.status)&&<Act label="Approve" need={6} rank={rank} primary data="locality-approve" onRun={()=>{if(!l.attribution_text)return window.alert('This locality has no attribution text, so it cannot be approved.');const r=ask(`Approve locality ${l.name}`);if(r)run('admin_destination_set_status',{p_kind:'locality',p_id:l.id,p_status:'approved',p_reason:r})}}/>}
              {l.status!=='withdrawn'&&<Act label="Withdraw" need={6} rank={rank} data="locality-withdraw" onRun={()=>{const r=ask(`Withdraw locality ${l.name}. It stops being returned by the API`);if(r)run('admin_destination_set_status',{p_kind:'locality',p_id:l.id,p_status:'withdrawn',p_reason:r})}}/>}</span></td></tr>)}</tbody></table></div>
      </Wait></section>
    <section className="m-panel" data-dst-postcodes><h3>Postcodes below {pct(share)}</h3>
      <p className="sl-sub">A campus postcode maps to a locality by itself only when at least {pct(share)} of the postcode lies in it. The rest wait here and in Layer 4 Review › Inbox › Campus locality, one item per campus. One decision settles the postcode for every campus in it.</p>
      <Wait {...pcs} empty="No postcode is waiting for a person.">
        <div className="dst-scroll"><table className="cf-table"><thead><tr><th>Postcode</th><th>Candidate localities and share of the postcode</th><th>Campuses</th><th>Waiting since</th><th>Actions</th></tr></thead>
          <tbody>{(pcs.rows||[]).map(p=>{const top=(p.candidates||[])[0];return <tr key={`${p.country_code}:${p.postcode}`} data-dst-postcode={p.postcode}><td>{p.postcode}<small className="dst-sub">{p.country_code}</small></td>
            <td>{(p.candidates||[]).map(c=><span key={c.locality_id} className="dst-cand">{c.name} {pct(c.containment_share)}</span>)}</td><td className="num">{fmtNumber(p.campuses||0)}</td><td>{fmtDate(p.opened_at)}</td>
            <td><span className="dst-actions">{top&&<Act label={`Accept ${top.name}`} need={3} rank={rank} primary data="postcode-accept" onRun={()=>{const r=ask(`Map postcode ${p.postcode} to ${top.name} (${pct(top.containment_share)})`);if(r)run('admin_destination_postcode_resolve',{p_country_code:p.country_code,p_postcode:p.postcode,p_locality_id:top.locality_id,p_reason:r})}}/>}
              {(p.candidates||[]).length>1&&<Act label="Choose another" need={3} rank={rank} data="postcode-choose" onRun={()=>{const n=window.prompt(`Which candidate for postcode ${p.postcode}? Enter its name:\n${p.candidates.map(c=>c.name).join(', ')}`);const c=n&&p.candidates.find(c=>c.name.toLowerCase()===n.trim().toLowerCase());if(!c)return;const r=ask(`Map postcode ${p.postcode} to ${c.name}`);if(r)run('admin_destination_postcode_resolve',{p_country_code:p.country_code,p_postcode:p.postcode,p_locality_id:c.locality_id,p_reason:r})}}/>}
              <Act label="No locality" need={3} rank={rank} data="postcode-none" onRun={()=>{const r=ask(`Record postcode ${p.postcode} as outside every locality`);if(r)run('admin_destination_postcode_resolve',{p_country_code:p.country_code,p_postcode:p.postcode,p_locality_id:null,p_reason:r})}}/></span></td></tr>})}</tbody></table></div>
      </Wait></section>
  </div>
}

function Metrics({rpc,rank,run,tick}){
  const[status,setStatus]=useState('')
  const m=useList(rpc,'locality_metric',status,tick)
  const first=(m.rows||[]).find(x=>x.metric_category==='population')||(m.rows||[])[0]
  return <div className="dst-stack" data-dst-tab="metrics">
    <section className="m-panel"><h3>City figures</h3>
      <p className="sl-sub">Population, climate and living-cost figures for each locality, one value per measure, period and dataset edition. Every figure carries its source and the attribution the website must show beside it.</p>
      <StatusFilter value={status} onChange={setStatus} options={['draft','in_review','approved','published','withdrawn']}/>
      <BulkApprove rows={m.rows||[]} rank={rank} run={run} kind="figure"/>
      <Wait {...m} empty="No city figure is loaded yet. Population arrives with the ABS load; climate and living costs follow once their sources are approved.">
        <div className="dst-scroll"><table className="cf-table" data-dst-metrics><thead><tr><th>Locality</th><th>Category</th><th>Measure</th><th>Value</th><th>Period</th><th>Edition</th><th>Source</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>{(m.rows||[]).map(x=><tr key={x.id} data-dst-metric={x.id}><td>{x.locality_name}<small className="dst-sub">{x.country_code}</small></td><td>{String(x.metric_category).replace('_',' ')}</td><td><ClimateMark row={x}/>{x.metric_key}</td>
            <td className="num">{x.currency_code?`${x.currency_code} `:''}{fmtNumber(x.numeric_value)} {x.unit}</td><td>{x.reference_period}</td><td>{x.dataset_edition}</td><td><Src url={x.source_url}/></td><td><Status v={x.status}/></td>
            <td><span className="dst-actions">{!['approved','published'].includes(x.status)&&<Act label="Approve" need={6} rank={rank} primary data="metric-approve" onRun={()=>{const r=ask(`Approve ${x.metric_key} for ${x.locality_name}`);if(r)run('admin_destination_set_status',{p_kind:'locality_metric',p_id:x.id,p_status:'approved',p_reason:r})}}/>}
              {x.status!=='withdrawn'&&<Act label="Withdraw" need={6} rank={rank} data="metric-withdraw" onRun={()=>{const r=ask(`Withdraw ${x.metric_key} for ${x.locality_name}`);if(r)run('admin_destination_set_status',{p_kind:'locality_metric',p_id:x.id,p_status:'withdrawn',p_reason:r})}}/>}</span></td></tr>)}</tbody></table></div>
        {first&&<div className="dst-preview" data-dst-attribution-preview><small>Attribution preview: what the website shows beside the figure</small>
          <p><strong>{first.currency_code?`${first.currency_code} `:''}{fmtNumber(first.numeric_value)}</strong> {first.unit} · {first.locality_name} · {first.reference_period}. <span>{first.attribution_text}</span></p></div>}
      </Wait></section>
  </div>
}

function Rules({rpc,rank,run,tick}){
  const[status,setStatus]=useState(''),[open,setOpen]=useState('')
  const q=useList(rpc,'study_rule',status,tick)
  return <div className="dst-stack" data-dst-tab="rules">
    <section className="m-panel"><h3>Study rules</h3>
      <p className="sl-sub">Rules a student must meet or may rely on: application routes, visa funds, work rights, post-study work, visa fee and processing times. Each rule has effective dates, the words on the official page it rests on, and where it is proven to apply. A rule is returned by the API when it is approved, its edition is published and today is inside its dates.</p>
      <StatusFilter value={status} onChange={setStatus} options={['draft','approved','superseded','withdrawn']}/>
      <Wait {...q} empty="No study rule is loaded yet. Rules are captured from their official pages into a draft edition, approved here, and then the edition is published on Overview & editions.">
        <div className="dst-scroll"><table className="cf-table" data-dst-rules><thead><tr><th>Rule</th><th>Category</th><th>Applies to</th><th>In effect</th><th>Edition</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>{(q.rows||[]).map(r=>{const fixed=r.edition_status==='published',title=r.title||r.visa_name||'Rule';return <React.Fragment key={r.id}><tr data-dst-rule={r.id}>
            <td><button type="button" className="dst-link" aria-expanded={open===r.id} onClick={()=>setOpen(open===r.id?'':r.id)}>{title}</button><small className="dst-sub">{r.country_code}{r.state_code?` · ${r.state_code}`:''}</small></td>
            <td>{String(r.rule_category||'visa summary').replaceAll('_',' ')}</td><td>{r.applicant_scope||'—'}</td>
            <td>{r.effective_from?fmtDate(r.effective_from):'—'} – {r.effective_to?fmtDate(r.effective_to):'open'}</td><td>{r.edition_label} <Status v={r.edition_status}/></td><td><Status v={r.approval_status}/></td>
            <td>{fixed?<small className="dst-sub">Edition published: fixed. Start a new edition to change it.</small>:<span className="dst-actions">
              {r.approval_status!=='approved'&&<Act label="Approve" need={6} rank={rank} primary data="rule-approve" onRun={()=>{const x=ask(`Approve rule "${title}"`);if(x)run('admin_destination_set_status',{p_kind:'study_rule',p_id:r.id,p_status:'approved',p_reason:x})}}/>}
              {r.approval_status!=='withdrawn'&&<Act label="Withdraw" need={6} rank={rank} data="rule-withdraw" onRun={()=>{const x=ask(`Withdraw rule "${title}"`);if(x)run('admin_destination_set_status',{p_kind:'study_rule',p_id:r.id,p_status:'withdrawn',p_reason:x})}}/>}</span>}</td></tr>
            {open===r.id&&<tr className="dst-detail"><td colSpan={7}><div className="dst-two" data-dst-quote-verifier>
              <div><small>Quote on page, stored with the rule</small>{r.quote_on_page?<blockquote>{r.quote_on_page}</blockquote>:<p><StatusChip tone="warning" label="No quote stored"/></p>}
                <p className="sl-sub">{r.summary||''}{r.numeric_threshold!=null?` Threshold: ${r.currency_code||''} ${fmtNumber(r.numeric_threshold)}.`:''} Evidence date {r.evidence_date?fmtDate(r.evidence_date):'not recorded'}.</p></div>
              <div><small>Source to check it against</small><p><Src url={r.source_url} label="Official page"/></p>
                {r.evidence?.stored?<p><a className="cf-link" href={`#evidence?evidence_id=${encodeURIComponent(r.evidence.evidence_id)}`} data-dst-stored-page>Open the stored copy of the page</a> <small className="dst-sub">captured {fmtDate(r.evidence.captured_at)}</small></p>
                  :<p><StatusChip tone="warning" label="No stored copy" title="The rule was loaded without a stored page, so the quote can only be checked against the live page"/></p>}</div></div>
              <div data-dst-applicability><small>Where it applies</small>{(r.applicability||[]).length?<ul className="dst-facts">{r.applicability.map(a=><li key={a.id}><span>{a.entity_name||a.entity_code||a.entity_type} <em>({a.entity_type})</em> <Src url={a.evidence_url}/></span>
                <StatusChip tone={a.status==='proven'?'success':'danger'} label={a.status==='proven'?'Proven':'Excluded'} title={a.quote_on_page||undefined}/></li>)}</ul>:<p className="sl-sub">No applicability row is recorded for this rule.</p>}</div></td></tr>}</React.Fragment>})}</tbody></table></div>
      </Wait></section>
  </div>
}

function Careers({rpc,rank,run,tick}){
  const[status,setStatus]=useState('')
  const q=useList(rpc,'career_outcome',status,tick)
  return <div className="dst-stack" data-dst-tab="careers">
    <section className="m-panel"><h3>Careers and outcomes</h3>
      <p className="sl-sub" data-dst-careers-note>Occupation outcomes in the country&rsquo;s own scheme (ANZSCO, NOC or SOC). Earnings here are labour-market outcomes. The funds a student must show for a visa are a study rule (category visa funds) and never appear in this table.</p>
      <StatusFilter value={status} onChange={setStatus} options={['draft','in_review','approved','published','withdrawn']}/>
      <Wait {...q} empty="No career outcome is loaded yet. They arrive as an edition once the source terms are approved.">
        <div className="dst-scroll"><table className="cf-table" data-dst-careers><thead><tr><th>Occupation</th><th>Scheme and code</th><th>Area</th><th>Median annual earnings</th><th>Demand</th><th>Period</th><th>Edition</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>{(q.rows||[]).map(o=>{const fixed=o.edition_status==='published';return <tr key={o.id} data-dst-career={o.id}><td>{o.occupation_title}</td><td>{o.occupation_scheme||'—'} {o.occupation_code}</td><td>{o.locality_name||o.state_code||o.country_code}</td>
            <td className="num">{o.salary_period==='annual'&&o.median_salary!=null?`${o.salary_currency||''} ${fmtNumber(o.median_salary)}`:'Not published'}</td><td>{o.job_outlook_rating||'—'}</td><td>{o.reference_period||'—'}</td><td>{o.edition_label} <Status v={o.edition_status}/></td><td><Status v={o.status}/></td>
            <td>{fixed?<small className="dst-sub">Edition published: fixed.</small>:<span className="dst-actions">
              {!['approved','published'].includes(o.status)&&<Act label="Approve" need={6} rank={rank} primary data="career-approve" onRun={()=>{const x=ask(`Approve outcome for ${o.occupation_title}`);if(x)run('admin_destination_set_status',{p_kind:'career_outcome',p_id:o.id,p_status:'approved',p_reason:x})}}/>}
              {o.status!=='withdrawn'&&<Act label="Withdraw" need={6} rank={rank} data="career-withdraw" onRun={()=>{const x=ask(`Withdraw outcome for ${o.occupation_title}`);if(x)run('admin_destination_set_status',{p_kind:'career_outcome',p_id:o.id,p_status:'withdrawn',p_reason:x})}}/>}</span>}</td></tr>})}</tbody></table></div>
      </Wait></section>
  </div>
}

// v2.16.42 (Platform Admin 18 Nov 2026 14:23): a climate figure shows the icon the website is given in the developer guide (src/lib/climate-icons.js)
function ClimateMark({row}){if(row.metric_category!=='climate')return null;const k=climateIcon(row.metric_key,row.numeric_value);if(!k)return null;const[I,label]=CLIMATE_ICONS[k]
  return <span className="dst-climate" data-dst-climate={k} title={`${label} (long-term average, not a forecast)`}><I size={14} aria-hidden="true"/><span className="sr-only">{label}: </span></span>}

export default function DestinationData({tab='overview',rank=0,onError,client=null}){
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const[o,setO]=useState(null),[err,setErr]=useState(''),[tick,setTick]=useState(0),[note,setNote]=useState('')
  const load=useCallback(()=>{Promise.resolve(rpc('admin_destination_overview',{})).then(({data,error})=>{if(error)setErr(plainError(error));else{setErr('');setO(data)}}).catch(e=>setErr(plainError(e)))},[])
  useEffect(()=>{load()},[tick])
  const run=async(fn,args)=>{setNote('')
    try{const{data,error}=await rpc(fn,args);if(error)throw error
      setNote(data?.approved!=null&&data?.dataset_edition?`Approved ${data.approved} of ${data.drafts} draft ${data.kind==='figures'?'figures':'localities'} of ${data.dataset_edition}${(data.left_without_attribution||data.left_without_value_or_attribution)?`; ${data.left_without_attribution||data.left_without_value_or_attribution} without attribution text left as draft`:''}.`:data?.locality?`Postcode ${data.postcode} now maps to ${data.locality}.`:data?.to?`Recorded: ${data.from||'—'} to ${data.to}.`:'Recorded.');setTick(t=>t+1)}
    catch(e){const m=plainError(e);setNote(m);onError?.(m)}}
  if(rank<3)return <EmptyInline text="Destination data opens for Curator and above."/>
  const body=err?<EmptyInline text={err}/>:!o?<p className="sl-sub">Loading…</p>
    :tab==='localities'?<Localities rpc={rpc} rank={rank} run={run} tick={tick} share={o.postcode_primary_min_share}/>
    :tab==='metrics'?<Metrics rpc={rpc} rank={rank} run={run} tick={tick}/>
    :tab==='rules'?<Rules rpc={rpc} rank={rank} run={run} tick={tick}/>
    :tab==='careers'?<Careers rpc={rpc} rank={rank} run={run} tick={tick}/>
    :<Overview o={o} rank={rank} run={run}/>
  return <div className="dst" data-destination-data data-dst-rank={rank}>
    <div className="dst-bar"><p className="sl-sub">Approval, publication and withdrawal are the Platform Admin&rsquo;s and always carry a reason. Curators review and settle postcodes.</p>
      <Button compact onClick={()=>setTick(t=>t+1)} data-dst-refresh><RefreshCw size={13}/> Refresh</Button></div>
    {note&&<p className="dst-note" role="status" data-dst-note>{note}</p>}
    {body}
  </div>
}

// Platform health › Data delivery: the destination load jobs (built and scheduled by the loaders' own releases) with Run now
export function DestinationLoads({rpc,rank=0}){
  const[o,setO]=useState(null),[err,setErr]=useState(''),[note,setNote]=useState('')
  useEffect(()=>{let live=true;if(rank<3)return;Promise.resolve(rpc('admin_destination_overview',{})).then(({data,error})=>{if(!live)return;if(error)setErr(plainError(error));else setO(data)}).catch(e=>{if(live)setErr(plainError(e))});return()=>{live=false}},[rank])
  if(rank<3)return null
  const head=<h4>Destination loads (localities, city figures, study rules, career outcomes)</h4>
  if(err)return <section className="dd-recognition" data-dd-destination="unknown">{head}<p className="sl-sub">Not measured: {err}</p></section>
  if(!o)return <section className="dd-recognition" data-dd-destination="loading">{head}<p className="sl-sub">Loading…</p></section>
  const loads=o.loads||[]
  const start=async j=>{const r=ask(`Run ${j.label||j.jobname} now`);if(!r)return;setNote('')
    try{const{error}=await rpc('admin_job_run_now_v1',{p_job:j.jobname,p_reason:r,p_args:{}});if(error)throw error;setNote(`${j.label||j.jobname}: started.`)}catch(e){setNote(plainError(e))}}
  return <section className="dd-recognition" data-dd-destination="known">{head}
    <p className="sl-sub">Loads write drafts. Nothing reaches the API until it is approved on <a className="cf-link" href="#destination-data">Destination data</a>.</p>
    <ul>
      <li data-dd-stage-row="dst_localities"><span>Localities held (approved or published)</span><strong>{fmtNumber(sum(o.localities))} ({fmtNumber(Number(o.localities?.approved||0)+Number(o.localities?.published||0))})</strong></li>
      <li data-dd-stage-row="dst_waiting"><span>Campuses waiting on a locality (<a className="cf-link" href="#layer-4-review">Layer 4 Review › Inbox › Campus locality</a>)</span><strong>{fmtNumber(o.campuses_waiting_locality||0)}</strong></li>
      <li data-dd-stage-row="dst_rules"><span>Study rules held</span><strong>{fmtNumber(sum(o.study_rules))}</strong></li>
      <li data-dd-stage-row="dst_careers"><span>Career outcomes held</span><strong>{fmtNumber(sum(o.career_outcomes))}</strong></li>
    </ul>
    {!loads.length?<p className="sl-sub" data-dd-destination-empty>No destination load job is catalogued yet. Each loader adds its job here when it is released.</p>:
      <ul data-dd-destination-loads>{loads.map(j=><li key={j.jobname} data-dd-load={j.jobname}><span>{j.label||j.jobname}<small className="dst-sub">{j.description}</small></span>
        <Button compact disabled={rank<Number(j.control_rank||6)} title={rank<Number(j.control_rank||6)?'Your role cannot start this job':undefined} onClick={()=>start(j)} data-dd-load-run>Run now</Button></li>)}</ul>}
    {note&&<p className="sl-sub" role="status">{note}</p>}
  </section>
}
