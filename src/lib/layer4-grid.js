// CF-247 UI/UX audit Phase 5 (18 Nov 2026): the pure parts of Layer 4 › Inbox › Grid (columns, CSV, the quote and value pairs of an item), kept
// apart from the screen so they are tested on their own (tests/uat/cf-247-s620-layer4-review-grid-contract.spec.mjs).
export const GRID_COLUMNS={kind:'Kind',subject:'Item',provider:'University',country:'Country',why:'Why it is here',suggestion:'Suggested next step',created_at:'Waiting since',age_days:'Days waiting'}
export const DEFAULT_COLS=['kind','subject','provider','why','age_days']
const csvCell=v=>{const s=v==null?'':String(v);return/[",\n\r]/.test(s)?`"${s.replace(/"/g,'""')}"`:s}
export function toCsv(rows,cols){return[cols.map(c=>csvCell(GRID_COLUMNS[c]||c)).join(','),...rows.map(r=>cols.map(c=>csvCell(r[c])).join(','))].join('\r\n')}
export const urlOf=v=>typeof v==='string'&&/^https?:\/\//i.test(v)?v:null

// the quote and the value it produced, as each kind's detail holds them
export function quoteValuePairs(item){const d=item?.detail||{},p=d.proposed||{},out=[]
  if(Array.isArray(p.sample))for(const r of p.sample)out.push({quote:r.quote||'',value:[r.kind,r.description||r.min_entry_score_basis,r.audience].filter(Boolean).join(' · ')})
  if(p.course_url||p.url)out.push({quote:d.quote||d.evidence?.quote||'',value:p.course_url||p.url,before:Array.isArray(d.before)?d.before.join(', '):d.before?.url||null,link:true})
  if(d.value!=null&&!out.length)out.push({quote:d.quote||'',value:typeof d.value==='object'?JSON.stringify(d.value):String(d.value)})
  if(!out.length&&d.evidence?.page_url)out.push({quote:'',value:d.evidence.page_url,link:true})
  return out}

