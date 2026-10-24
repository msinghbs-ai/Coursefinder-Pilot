// v2.15.341 (Platform Admin 24 Oct 2026 11:27, UI audit Phase 0): one plain reading of any error shown to a person.
// Nothing internal reaches the screen: no "ERROR:" prefix, no CONTEXT or SQL statement, no function signatures, schema-qualified
// names, job slugs or vendor names. Each error that reaches the global banner gets a short reference; the full text is written to
// pipeline.ui_error_log (public.admin_ui_error_report) so the Platform Admin can look it up by that reference.

const KNOWN=[
  [/statement timeout|canceling statement/i,'The database took too long to answer and stopped the request. Try again in a moment; if it keeps happening, tell the Platform Admin.'],
  [/deadlock/i,'Two jobs tried to change the same data at once; one was stopped and will run again.'],
  [/could not obtain lock|lock timeout/i,'Another job was using the same data; this one will run again.'],
  [/permission denied|not allowed|role required|42501/i,'Your role is not allowed to do this.'],
  [/jwt|not signed in|invalid claim|401/i,'Your sign-in has expired. Sign in again.'],
  [/fetch failed|network|Failed to fetch|ECONN|connection/i,'Could not reach the platform. Check the connection and try again.'],
  [/full https:\/\/ web address/i,'A course page address was not a secure (https) web address, so it was left for a person to check.'],
  [/duplicate key value/i,'The same record was being written twice at once; nothing was lost.'],
  [/BOOT_ERROR|failed to start/i,'The worker could not start. This happens for a minute while a new version is being released.'],
  [/WORKER_RESOURCE_LIMIT|compute resources/i,'The worker ran out of memory or time on this run; the next run picks up where it stopped.'],
  [/dynamically imported module|Importing a module script failed/i,'A newer version of this screen is available. Reload the page.'],
]
// Words that name plumbing, replaced in any text that is still shown
const INTERNAL=[
  [/\b(security|pipeline|public|catalogue|search|scholarship|ref|api)\.[a-z0-9_]+(\([^)]*\))?/gi,'a platform step'],
  [/\b[a-z0-9_]+_(v\d+|impl)\([^)]*\)/gi,'a platform step'],
  [/\bfirecrawl\b/gi,'the page-reading service'],
  [/\bopenrouter\b/gi,'the AI service'],
  [/\bsupabase\b/gi,'the platform'],
  [/\bpg_cron\b|\bcron\b/gi,'the scheduler'],
  // a job slug (coverage-admit, zero-yield-detect, provider-basis-rule-admit) is read as its words
  [/\b(coverage|scholarship|provider|course|central|source|programme|credential|companion|logo|flag|fee|enrich|zero-yield|health|ledger|stats|gap|retention|waste|hygiene|openrouter|search|university|policy|register|adapter|consumer|mode|platform|statistics|cricos|nz|ca|au)-[a-z0-9]+(-[a-z0-9]+)*\b/g,x=>'"'+x.replace(/-/g,' ').replace(/^./,c=>c.toUpperCase())+'"'],
]
export function rawFirstLine(raw){
  let m=String(raw?.message??raw??'')
  // the message ends where Postgres starts explaining itself (on a new line or inline)
  m=m.split(/\s*\b(CONTEXT|DETAIL|HINT|SQL statement|PL\/pgSQL function|SQL function|LINE \d+)\b:?/i)[0]
  m=m.replace(/\bERROR:\s*/gi,'')
  return m.replace(/\s+/g,' ').trim()
}
/** Plain reading of an error: a known sentence, or the first line with internals replaced, never longer than 160 characters. */
export function plainError(raw){
  const m=String(raw?.message??raw??'')
  const hit=KNOWN.find(([r])=>r.test(m))
  if(hit)return hit[1]
  let t=rawFirstLine(m)
  for(const[r,w]of INTERNAL)t=t.replace(r,w)
  t=t.replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,'a record').replace(/\b[0-9a-f]{32,64}\b/gi,'a file')
  if(!t)return'Something went wrong. Try again; if it keeps happening, tell the Platform Admin.'
  t=t.slice(0,160)
  return /[.!?]$/.test(t)?t:t+'.'
}
/** For text that is usually fine (a title, a detail line) but may carry a raw error: cleaned only when it does. */
export function scrubInternals(text){
  const t=String(text??'')
  if(/ERROR:|CONTEXT:|PL\/pgSQL|SQL statement|SQL function|\b[a-z0-9_]+_(v\d+|impl)\(|\b(security|pipeline)\.[a-z0-9_]+\(/i.test(t))return plainError(t)
  let o=t;for(const[r,w]of INTERNAL)o=o.replace(r,w);return o
}
const refOf=()=>{const a='abcdefghjkmnpqrstuvwxyz23456789';let s='';for(let i=0;i<6;i++)s+=a[Math.floor(Math.random()*a.length)];return s.toUpperCase()}
/**
 * For the global banner: a generic line with a reference, and the full detail written server-side. Never throws, never waits.
 * Returns the text to show. The reference lets the Platform Admin find the full error: select * from pipeline.ui_error_log where ref = '…'.
 */
export function reportError(raw,page=''){
  const ref=refOf(),plain=plainError(raw)
  const detail={message:String(raw?.message??raw??''),code:raw?.code??null,details:raw?.details??null,hint:raw?.hint??null,stack:raw?.stack?String(raw.stack).slice(0,2000):null,page,href:typeof location!=='undefined'?location.hash:'',at:new Date().toISOString()}
  // the client is loaded on demand so this file stays free of browser-only setup (the contract test imports it in Node)
  try{import('./supabase').then(({supabase})=>supabase.rpc('admin_ui_error_report',{p_ref:ref,p_page:page,p_message:plain,p_detail:detail})).then(()=>{},()=>{})}catch{}
  return`${plain} (ref ${ref})`
}
