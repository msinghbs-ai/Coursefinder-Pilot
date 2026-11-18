// Layer 4 › Inbox › Grid › Clusters (v2.16.43, Platform Admin 18 Nov 2026 19:20): the pure parts. Held items are grouped by
// (kind, university, refusal reason, quote), with the reason and the quote normalised so the same refusal on the same words is one cluster
// whatever its numbers, spacing, case or links. Kept apart from the screen so it is tested on its own
// (tests/uat/cf-247-s660-layer4-clusters-contract.spec.mjs). Nothing here reads or writes the database.
import{quoteValuePairs}from'./layer4-grid'

// kinds whose items are inspected in clusters but always decided one at a time: the AER audit sample and entry requirements (each read is
// verified on its own), identity and departures, campus postcodes, and requests for human input (Platform Admin 18 Nov 2026 13:02, as
// S2-Build's Grouped decisions)
export const NEVER_SETTLE=['aer_review','campus_locality','intervention','provider_departure']

export function normText(s){
  return String(s??'').normalize('NFKC').toLowerCase()
    .replace(/https?:\/\/\S+/g,' <url> ')
    .replace(/\d+(?:[.,:/-]\d+)*/g,'#')
    .replace(/[^\p{L}\p{N}#<>]+/gu,' ')
    .replace(/\s+/g,' ').trim()
}

const flat=v=>v==null?'':Array.isArray(v)?v.map(flat).filter(Boolean).join(' '):typeof v==='object'?Object.values(v).map(flat).filter(Boolean).join(' '):String(v)

// the words an item's decision rests on, wherever its kind keeps them
export function quoteOf(item,hook){
  const d=item?.detail||{}
  const direct=[d.quote,d.evidence?.quote,d.value_quote,d.audience_quote,Array.isArray(d.refused)?d.refused.map(r=>r?.quote).find(Boolean):d.refused?.quote].find(x=>typeof x==='string'&&x.trim())
  if(direct)return direct.trim()
  const pair=quoteValuePairs(item).find(p=>p.quote&&String(p.quote).trim())
  if(pair)return String(pair.quote).trim()
  const sec=(hook?.sections||[]).find(s=>/quote/i.test(`${s?.key||''} ${s?.title||''}`))
  return sec?flat(sec.body).trim():''
}

export const clusterKey=(item,hook)=>[item?.kind||'',item?.provider_id||'',normText(item?.why),normText(quoteOf(item,hook)).slice(0,240)].join('|')

// clusters of two or more items, largest first; hooks is a map "kind:ref" -> hook_detail
export function clusterItems(items,hooks={}){
  const m=new Map()
  for(const it of items||[]){const h=hooks[`${it.kind}:${it.ref}`],k=clusterKey(it,h)
    if(!m.has(k))m.set(k,{key:k,kind:it.kind,provider_id:it.provider_id||null,provider:it.provider||'',why:it.why||'',quote:quoteOf(it,h),items:[]})
    m.get(k).items.push(it)}
  return[...m.values()].filter(c=>c.items.length>1).sort((a,b)=>b.items.length-a.items.length||String(a.provider).localeCompare(String(b.provider)))
}

// the choices a whole cluster can take: no value to type, no link to open, the person's rank, and never for the kinds decided one at a time
export function settleChoices(kind,k,rank){
  if(NEVER_SETTLE.includes(kind))return[]
  return(k?.choices||[]).filter(c=>!c.input&&!c.link&&Number(rank)>=Number(c.rank||0))
}
export const confirmPhrase=(choice,n)=>`${String(choice||'').toUpperCase()} ${n}`
