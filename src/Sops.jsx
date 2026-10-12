// Guides › Platform Admin SOP and Operator SOP (v2.15.257, Platform Admin 12 Oct 2026). The words live in src/guide/sops.js, which also
// writes the versioned documents (docs/sops/*.md, copied to the admin repo). Every step opens its screen, so the SOP never relies on
// screenshots. Reviewed with every release (contract test: SOP_REVIEWED_FOR equals the UI version).
import React from'react'
import{ArrowRight,ClipboardList,Download}from'lucide-react'
import{PAGES,canOpen}from'./nav-map'
import{UI_VERSION}from'./release-manifest'
import{AUTOMATION,RULES,SOPS,SOP_REVIEWED_FOR,sopMarkdown}from'./guide/sops'

const label=(page,tab)=>{const p=PAGES[page];const t=(p?.tabs||[]).find(x=>x.key===tab);return[p?.label||page,t?.label].filter(Boolean).join(' › ')}

export default function Sop({id,rank=1,navigate}){
  const s=SOPS.find(x=>x.id===id)||SOPS[0]
  const Open=({x})=>x.page&&canOpen(x.page,rank)?<button type="button" className="m-secondary compact pg-open" onClick={()=>navigate?.(x.page,x.tab?{tab:x.tab}:{})}>{label(x.page,x.tab)}<ArrowRight size={12}/></button>:x.page?<small className="pg-meta">{label(x.page,x.tab)}</small>:null
  const download=()=>{const b=new Blob([sopMarkdown(s,label)],{type:'text/markdown'});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=`StudySearch-${s.id}-v${s.version}.md`;a.click();URL.revokeObjectURL(a.href)}
  return <div className="m-page-stack pg sop" data-sop={s.id}>
    <section className="m-panel">
      <div className="sop-head"><div><h2><ClipboardList size={18}/> {s.title}</h2><p className="pg-lead">{s.purpose}</p>
        <p className="pg-meta" data-sop-version>Version {s.version} · {s.audience} · reviewed for v{SOP_REVIEWED_FOR}{SOP_REVIEWED_FOR!==UI_VERSION?` · this app is v${UI_VERSION}`:''}</p></div>
        <button type="button" className="m-secondary compact" onClick={download} data-sop-download><Download size={13}/> Download (Markdown)</button></div>
      <h3>What you own</h3><ul className="sop-list">{s.owns.map(o=><li key={o}>{o}</li>)}</ul>
    </section>
    <section className="m-panel" data-sop-automation>
      <h3>How the platform automates, and where a person decides</h3>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Stage</th><th>Runs by itself</th><th>Scheduled jobs</th><th>Where a person decides</th></tr></thead>
        <tbody>{AUTOMATION.map(a=><tr key={a.stage}><td><strong>{a.stage}</strong></td><td>{a.runs}</td><td className="pg-meta">{a.jobs}</td><td>{a.person}</td></tr>)}</tbody></table></div>
      <h3>Rules that never change</h3><ol className="sop-list">{RULES.map(r=><li key={r}>{r}</li>)}</ol>
    </section>
    <section className="m-panel" data-sop-daily>
      <h3>Daily routine</h3>
      {s.schedule.map(b=><div key={b.when} className="sop-block"><h4>{b.when}</h4><ol className="pg-steps sop-steps">{b.steps.map((x,i)=><li key={i} data-sop-step>
        <div><strong>{x.role?`${x.role}: `:''}{x.do}</strong>{x.why&&<span>Why: {x.why}</span>}{x.done&&<span>Done when: {x.done}</span>}</div><Open x={x}/></li>)}</ol></div>)}
      <h3>Weekly</h3><ul className="sop-list">{s.weekly.map((x,i)=><li key={i}>{x.role?<strong>{x.role}: </strong>:null}{x.do} <Open x={x}/></li>)}</ul>
    </section>
    <section className="m-panel" data-sop-interventions>
      <h3>Where a person intervenes</h3>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>When you see</th><th>Do</th><th>Where</th></tr></thead>
        <tbody>{s.interventions.map(x=><tr key={x.trigger}><td><strong>{x.trigger}</strong></td><td>{x.action}</td><td>{x.where}</td></tr>)}</tbody></table></div>
      <h3>What to pay attention to</h3><ul className="sop-list">{s.watch.map(w=><li key={w}>{w}</li>)}</ul>
      <h3>Escalation</h3><ul className="sop-list">{s.escalate.map(e=><li key={e}>{e}</li>)}</ul>
    </section>
    <section className="m-panel" data-sop-history>
      <h3>Version history</h3>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Version</th><th>Date</th><th>Release</th><th>Change</th></tr></thead>
        <tbody>{s.changes.map(c=><tr key={c.version}><td>{c.version}</td><td>{c.date}</td><td>v{c.release}</td><td>{c.change}</td></tr>)}</tbody></table></div>
      <p className="pg-meta">The versioned copy is kept in the admin repository (docs/sops/{s.id}.md) with the change-control record (CF-247).</p>
    </section>
  </div>
}
