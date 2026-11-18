// CF-247 S1-Courses s664 (Platform Admin 18 Nov 2026): the plain-English hold explanations and the four course description decisions of Layer 4 › Inbox.
// Pure data and functions (no React), shared by src/CourseDescriptionPanel.jsx and the s664 spec.
export const CD_HOLD={
  identity_margin_thin:{title:'The page match is not clear enough',why:'The page was found by an AI match, or another page scored almost as high, and the page itself does not prove the course by its own CRICOS or NZQA code or exact title.',action:'Open the official page. If it is this course\'s own page, approve as read; if it is another course or a shared page, reject (bad page / wrong course).'},
  binding_ambiguous:{title:'More than one page could be this course',why:'The course has more than one candidate page, so the platform has not settled which page is its own.',action:'Check the page against the course title and code, then approve as read or reject (bad page / wrong course).'},
  first_provider_sample:{title:'Waiting for the machine check',why:'This description has not been checked by the machine rule yet. It is admitted automatically when its own page proves the course and every sentence matches its quote.',action:'Nothing to do unless it stays here after the next run; then read the reason again.'},
  sentence_count_over_2:{title:'Longer than 1 to 2 sentences',why:'The description was written by the earlier reader and has more sentences than the limit now allows.',action:'Choose Re-read (1-2 sentences). The stored page is read again; nothing is marked bad.'},
  length:{title:'Longer than the limit',why:'The description has more characters than the limit now allows.',action:'Choose Re-read (1-2 sentences).'},
  boilerplate_detected:{title:'Marketing or claim wording',why:'A word the admission policy does not admit on its own (for example "accredited", "innovative" or "leading") is in the description.',action:'Choose Re-read (1-2 sentences); the reader leaves such words out. Approve as read only if the page itself supports the word.'},
  quote_mismatch:{title:'A sentence is not supported by its quote',why:'At least one sentence does not match the words it quotes from the stored page.',action:'Choose Re-read (1-2 sentences), or reject if the page is not about this course.'},
  evidence_moved:{title:'The page changed after it was read',why:'A newer copy of the course page was stored after this description was written.',action:'Choose Re-read (1-2 sentences) so the new copy is read.'},
  wrong_page_kind:{title:'Not a course overview page',why:'The page is an entry, fees, how-to-apply or structure page, or a university-wide page, so it does not describe this course.',action:'Reject (bad page / wrong course), then set the right page on the course record.'},
  duplicate:{title:'Same wording as another course',why:'Another course already holds, or is waiting with, almost the same words (often shared qualification wording).',action:'Check that the page is this course\'s own; approve as read only if the wording truly belongs to this course.'},
  rejected_before:{title:'A person refused this before',why:'A person rejected an earlier description for this course, this page or these words.',action:'Decide it yourself; the machine rule never overrides a person.'},
  other:{title:'Held by a check',why:'The machine rule did not admit it.',action:'Read the reason and the page, then decide.'}
}
// the machine rule's code (with the check_ / policy_ prefixes it records) to the explanation key above
export function cdHoldKey(code,d){
  const c=String(code||'')
  if(!c)return 'first_provider_sample'
  if(c==='identity_margin_thin'||c==='identity_not_allowed')return 'identity_margin_thin'
  if(c==='binding_ambiguous')return 'binding_ambiguous'
  if(c==='check_sentence_count')return 'sentence_count_over_2'
  if(c==='check_length')return 'length'
  if(c.startsWith('policy_')||c==='check_unsupported_claim'||c==='check_unsupported_marketing')return 'boilerplate_detected'
  if(/^check_(quote_not_on_page|unsupported_sentence|copied_sentence)$/.test(c)||c==='source_recheck_failed')return 'quote_mismatch'
  if(c==='evidence_moved'||c==='page_url_changed'||c==='reading_other_evidence')return 'evidence_moved'
  if(c==='wrong_page_kind')return 'wrong_page_kind'
  if(c.startsWith('duplicate_')||c==='check_duplicate_other_course')return 'duplicate'
  if(c.startsWith('rejected_before')||c==='withdrawn_awaiting_person')return 'rejected_before'
  return 'other'
}
// the course description card's four decisions: university descriptions keep their two
export const CD_CHOICE_LABEL={approve:'Approve as read',reread:'Re-read (1-2 sentences)',approve_provider:'Approve all verified for provider',reject:'Reject (bad page / wrong course)'}
export const CD_CHOICE_ORDER=['approve','reread','approve_provider','reject']
export function cdChoices(choices,isCourse){
  const list=choices||[]
  if(!isCourse)return list.filter(c=>c.key!=='reread'&&c.key!=='approve_provider')
  return CD_CHOICE_ORDER.map(k=>list.find(c=>c.key===k)).filter(Boolean).map(c=>({...c,label:CD_CHOICE_LABEL[c.key]||c.label}))
}
