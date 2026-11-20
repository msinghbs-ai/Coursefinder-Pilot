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

// CF-247 s819/s820 (Platform Admin 20 Nov 2026 10:21): the promotional words removed the same way the server does (security.description_strip_text_v1):
// each word of the list (with an intensifier straight before it: most, very, highly, truly, particularly), then the spaces, commas, a conjunction left
// with nothing to join, the article ("an innovative university" becomes "a university") and the capital letter. Nothing is added. The server checks the
// result again when it is admitted.
const INTENS='(?:(?:most|very|highly|truly|particularly)\\s+)?'
export function stripBanned(text,words){
  let t=String(text||'');const removed=[]
  for(const w of [...new Set((words||[]).map(x=>String(x).trim()).filter(Boolean))].sort((a,b)=>b.length-a.length||a.localeCompare(b))){
    const re=new RegExp(`(^|[^A-Za-z0-9])${INTENS}${esc(w)}(?=$|[^A-Za-z0-9])`,'gi'),before=t
    t=t.replace(re,'$1');if(t!==before)removed.push(w.toLowerCase())
  }
  if(!removed.length)return{text:String(text||''),removed,changed:false}
  t=t.replace(/\b(and|or)\s+(?=(?:and|or)\b)/gi,'').replace(/(\b(?:a|an|the)\s+)(?:and|or)\s+/gi,'$1').replace(/\b(a|an|the)\s*,\s*/gi,'$1 ')
    .replace(/\s*,\s*(?:and|or)\s*(?=[.!?;:]|$)/gi,'').replace(/\b(?:and|or)\s*(?=[,.!?;:]|$)/gi,'').replace(/,\s*(?=[,.!?;:])/g,'')
    .replace(/\s+([,.!?;:])/g,'$1').replace(/\s{2,}/g,' ').replace(/^[\s,;:]+/,'').trim()
  t=t.replace(/\b(a)\s+(?=(?:hour|honour|honest|heir)|[aeio]|u(?!ni|se|su|ti|tu|ra|re))/gi,'$1n ')
    .replace(/\b(an)\s+(?=(?:uni|use|usu|uti|utu|eu|one\b)|[b-df-hj-np-tv-z])(?!(?:hour|honour|honest|heir))/gi,m=>m[0]==='A'?'A ':'a ')
  if(t)t=t[0].toUpperCase()+t.slice(1)
  return{text:t,removed,changed:true}
}
// s820: the main reason a description is held, in plain English, from the card's own facts: the banned words in the candidate first, then the machine
// rule's code (the raw code stays reachable under Technical detail)
const HOLD_WORDS={
  validation_first_sentence:'The first sentence does not name the university',validation_quote_not_on_page:'A quote is not on the stored page',
  validation_unsupported_sentence:'A sentence is not supported by its quote',validation_length:'Shorter or longer than the length rules allow',
  validation_sentence_count:'Too few or too many sentences',machine_text_figure:'Contains a figure the automatic rule does not admit on its own',
  machine_text_entity_encoded:'Contains page markup',validation_duplicate:'Almost the same words as another university',
  machine_admission_off:'The automatic rule is switched off',identity_not_ok:'The page does not prove it is this university'}
export const holdCode=why=>{const m=/did not admit this:\s*([a-z0-9_]+)/i.exec(String(why||''));return m?m[1]:''}
export function holdReason(why,candidate,rules){
  const banned=bannedIn(candidate,rules?.words),code=holdCode(why)
  if(banned.length)return{kind:'banned',banned,title:`Contains ${banned.length} banned word${banned.length===1?'':'s'}`,words:banned,code}
  if(/refused_word/.test(code))return{kind:'refused_word',banned:[],title:'Contains a word the automatic rule does not admit on its own',code}
  return{kind:'other',banned:[],title:HOLD_WORDS[code]||(code?code.replace(/_/g,' '):'Held for a person to decide'),code}
}
// s819 (Platform Admin 20 Nov 2026 10:21): what reviewers take out. The words of the machine text that the admitted human text no longer has, per edit,
// and over all edits the words removed most often, each marked as already on the readers' list (removed automatically from now on) or not (a candidate
// for the list, which a Platform Admin adds in Settings › Pipeline settings). Worked out from the Human Edits records; nothing is written.
const STOP=new Set(['the','and','for','with','its','are','was','has','have','from','that','this','which','their','also','into','over','more','than','our','your','who','who','been','being','as','at','by','in','is','it','of','on','or','to','an','a'])
const tokens=t=>String(t||'').toLowerCase().replace(/[^a-z0-9\s-]/g,' ').split(/\s+/).filter(w=>w.length>=3&&!STOP.has(w)&&!/^\d+$/.test(w))
export function removedWords(original,edited){const keep=new Set(tokens(edited));return [...new Set(tokens(original).filter(w=>!keep.has(w)))]}
export function ruleCandidates(items,listWords){
  const list=new Set((listWords||[]).map(w=>String(w).toLowerCase())),count=new Map()
  for(const x of items||[]){if(!x||!x.original)continue;for(const w of removedWords(x.original,x.current||x.edited))count.set(w,(count.get(w)||0)+1)}
  return [...count.entries()].map(([word,n])=>({word,n,on_list:list.has(word)})).sort((a,b)=>b.n-a.n||a.word.localeCompare(b.word))
}

// CF-247 s838 (Platform Admin 20 Nov 2026 14:40): the proposed text in pieces, with each word from the lists marked (shown in soft yellow on the card).
// The same word match as bannedIn: whole words, any case. Returns [{text, word}] where word is the list word for a marked piece, '' otherwise.
export function markBanned(text,words){const t=String(text||''),ws=[...new Set((words||[]).map(x=>String(x).trim()).filter(Boolean))].sort((a,b)=>b.length-a.length)
  if(!t||!ws.length)return[{text:t,word:''}]
  const re=new RegExp(`(^|[^A-Za-z0-9])(${ws.map(esc).join('|')})(?=$|[^A-Za-z0-9])`,'gi'),out=[];let last=0,m
  while((m=re.exec(t))){const at=m.index+m[1].length;if(at>last)out.push({text:t.slice(last,at),word:''});out.push({text:m[2],word:m[2].toLowerCase()});last=at+m[2].length;re.lastIndex=last}
  if(last<t.length)out.push({text:t.slice(last),word:''})
  return out}
