// CF-247 s802/s803 (Platform Admin 20 Nov 2026 05:52): the live checks an edited University or Course description shows while a person types.
// Pure functions (no React), shared by src/DescriptionEditAdmit.jsx, src/HumanEditsAudit.jsx and the s802 spec. The limits and word lists come from
// the server (public.admin_layer4_inbox action description_rules, from the readers' own settings); the server checks again on save
// (security.description_text_check_v1), so these are a guide while typing, never the gate.
export const sentencesOf=t=>String(t||'').trim().split(/[.!?]+(?:\s+|$)/).map(s=>s.trim()).filter(Boolean)
export const wordsOf=t=>{const s=String(t||'').trim();return s?s.split(/\s+/).length:0}
const esc=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')
export function bannedIn(text,words){const t=String(text||'');return [...new Set((words||[]).map(String).filter(Boolean))].filter(w=>new RegExp(`(^|[^A-Za-z0-9])${esc(w)}($|[^A-Za-z0-9])`,'i').test(t)).sort()}
// the text a person would admit, against one entity's rules: { chars, sentences, words, banned, problems, ok }
export function checkDescription(text,rules){
  const t=String(text||'').trim(),r=rules||{},chars=t.length,sentences=sentencesOf(t).length,words=wordsOf(t),banned=bannedIn(t,r.words),problems=[]
  if(r.min_chars!=null&&chars<Number(r.min_chars))problems.push(`at least ${r.min_chars} characters (has ${chars})`)
  if(r.max_chars!=null&&chars>Number(r.max_chars))problems.push(`at most ${r.max_chars} characters (has ${chars})`)
  if(r.min_sentences!=null&&sentences<Number(r.min_sentences))problems.push(`at least ${r.min_sentences} sentence${Number(r.min_sentences)===1?'':'s'} (has ${sentences})`)
  if(r.max_sentences!=null&&sentences>Number(r.max_sentences))problems.push(`at most ${r.max_sentences} sentences (has ${sentences})`)
  if(banned.length)problems.push(`words not allowed: ${banned.join(', ')}`)
  return{chars,sentences,words,banned,problems,ok:problems.length===0}
}
// unedited means the trimmed text equals the trimmed candidate (the server compares the same way)
export const isEdited=(text,original)=>String(text||'').trim()!==String(original||'').trim()
