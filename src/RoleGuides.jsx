// Guides › Role guides (v2.16.35, Platform Admin 18 Nov 2026 10:33): one guide per role, the signed-in person's own first. The words live in
// src/guide/roleGuides.js, which also writes docs/role-guides/*.md (mirrored to the admin repository's docs/platform/role-guides/). The pages listed
// under "Pages you can open" come from the menu, so a guide never names a page the role cannot open.
import React,{useState}from'react'
import{ArrowRight,BookOpen,Download}from'lucide-react'
import{canOpen}from'./nav-map'
import{UI_VERSION}from'./release-manifest'
import{ROLE_GUIDES,ROLE_GUIDES_REVIEWED_FOR,guideForRank,pagesFor,roleGuideMarkdown}from'./guide/roleGuides'

export default function RoleGuides({rank=1,navigate}){
  const mine=guideForRank(rank),[open,setOpen]=useState(mine.id),g=ROLE_GUIDES.find(x=>x.id===open)||mine
  const download=()=>{const b=new Blob([roleGuideMarkdown(g)],{type:'text/markdown'});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=`StudySearch-${g.id}-guide-v${g.version}.md`;a.click();URL.revokeObjectURL(a.href)}
  return <div className="m-page-stack pg rg" data-role-guides>
    <section className="m-panel">
      <div className="pg-views" role="tablist" aria-label="Role">{ROLE_GUIDES.map(x=><button key={x.id} type="button" role="tab" aria-selected={open===x.id} className={`pg-view${open===x.id?' is-on':''}`} data-role-guide-pick={x.id} onClick={()=>setOpen(x.id)}>{x.role}{x.id===mine.id?' (you)':''}</button>)}</div>
      <div className="sop-head"><div><h2><BookOpen size={18}/> {g.role} guide</h2><p className="pg-lead">{g.purpose}</p>
        <p className="pg-meta" data-role-guide-version>Version {g.version} · rank {g.rank} · reviewed for v{ROLE_GUIDES_REVIEWED_FOR}{ROLE_GUIDES_REVIEWED_FOR!==UI_VERSION?` · this app is v${UI_VERSION}`:''}</p></div>
        <button type="button" className="m-secondary compact" onClick={download} data-role-guide-download><Download size={13}/> Download (Markdown)</button></div>
      {g.id!==mine.id&&<p className="pg-meta" data-role-guide-other>You are reading another role&rsquo;s guide. Your own is the {mine.role} guide.</p>}
    </section>
    <div className="rg-two">
      <section className="m-panel" data-role-guide-can><h3>What you can do</h3><ul className="sop-list">{g.can.map(x=><li key={x}>{x}</li>)}</ul></section>
      <section className="m-panel" data-role-guide-cannot><h3>What you cannot do</h3><ul className="sop-list">{g.cannot.map(x=><li key={x}>{x}</li>)}</ul></section>
    </div>
    <section className="m-panel" data-role-guide-pages><h3>Pages you can open</h3>
      <ul className="rg-pages">{pagesFor(g.rank).map(p=><li key={p.key}>{canOpen(p.key,rank)?<button type="button" className="cf-link" onClick={()=>navigate?.(p.key)}>{p.label}<ArrowRight size={12}/></button>:<strong>{p.label}</strong>}{p.tabs.length>0&&<small>{p.tabs.join(' · ')}</small>}</li>)}</ul>
    </section>
    <section className="m-panel" data-role-guide-start><h3>Where to start</h3><ul className="sop-list">{g.start.map(x=><li key={x}>{x}</li>)}</ul>
      {g.tasks.map(t=><div key={t.task} className="sop-block"><h4>{t.task}</h4><ol className="pg-steps sop-steps">{t.steps.map((s,i)=><li key={i}><div><strong>{s}</strong></div></li>)}</ol></div>)}
      <h3>When to ask someone</h3><p>{g.ask}</p>
    </section>
    <section className="m-panel" data-role-guide-history><h3>Version history</h3>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Version</th><th>Date</th><th>Release</th><th>Change</th></tr></thead>
        <tbody>{g.changes.map(c=><tr key={c.version}><td>{c.version}</td><td>{c.date}</td><td>v{c.release}</td><td>{c.change}</td></tr>)}</tbody></table></div>
      <p className="pg-meta">The versioned copy is kept in the admin repository (docs/platform/role-guides/{g.id}.md).</p>
    </section>
  </div>
}
