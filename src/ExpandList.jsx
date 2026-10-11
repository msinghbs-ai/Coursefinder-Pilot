// v2.15.246 (Platform Admin bugs 11/10-3, Feature 2 and Fix 7): one list pattern for source screens (Layer 1 › Sources,
// Reference data › Reference sources). A toolbar whose filters line up with the columns below, a header row, and rows that show
// pills and open in place for editing. Columns are given once (label, width, render) and used for the header and every row,
// so the fields shown, filtered and edited always match.
import React,{useState}from'react'
import{ChevronRight}from'lucide-react'

export function Pill({tone='neutral',children,title}){return <span className={`xl-pill tone-${tone}`} title={title}>{children}</span>}

export function ExpandList({columns,rows,rowKey,renderBody,empty='Nothing matches these filters.',openKey,onOpen,dataAttr='data-xl-row'}){
  const[own,setOwn]=useState(null)
  const open=openKey!==undefined?openKey:own,setOpen=onOpen||setOwn
  const grid={gridTemplateColumns:`28px ${columns.map(c=>c.width||'1fr').join(' ')}`}
  return <div className="xl" role="table">
    <div className="xl-head" role="row" style={grid}><span/>{columns.map(c=><span key={c.key} role="columnheader" className={c.align==='end'?'xl-end':''}>{c.label}</span>)}</div>
    {rows.length===0&&<p className="xl-empty">{empty}</p>}
    {rows.map(r=>{const k=rowKey(r),isOpen=open===k
      return <article key={k} className={`xl-row${isOpen?' is-open':''}${r.__muted?' is-muted':''}`} {...{[dataAttr]:k}}>
        <div className="xl-line" role="row" style={grid} onClick={e=>{if(e.target.closest('button,a,input,select,label'))return;setOpen(isOpen?null:k)}}>
          <button type="button" className="xl-chev" aria-expanded={isOpen} aria-label={`${isOpen?'Close':'Open'} ${r.__label||k}`} onClick={()=>setOpen(isOpen?null:k)}><ChevronRight size={15} style={{transform:isOpen?'rotate(90deg)':undefined}}/></button>
          {columns.map(c=><span key={c.key} role="cell" className={`xl-cell${c.align==='end'?' xl-end':''}`} data-col={c.key}><small className="xl-cell-label">{c.label}</small>{c.render(r)}</span>)}
        </div>
        {isOpen&&<div className="xl-body">{renderBody(r)}</div>}
      </article>})}
  </div>
}

// The toolbar: search and filters on the left (in the same order as the columns), actions on the right.
export function XlToolbar({children,actions}){return <div className="xl-toolbar"><div className="xl-filters">{children}</div>{actions&&<div className="xl-actions">{actions}</div>}</div>}
export function XlField({label,children,wide}){return <label className={`xl-field${wide?' wide':''}`}><small>{label}</small>{children}</label>}
