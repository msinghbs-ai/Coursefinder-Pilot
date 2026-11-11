// CF-247 F-PDESC prompt-based provider descriptions (Platform Admin 11 Nov 2026 14:51 and 14:57): "the Platform Admin can maintain the prompt in
// the settings from the UI"; "AI spend, controls and progress should be visible on the UI" (06:11).
// ProviderDescriptionStatus: the reader's AI spend against its ceiling and daily guard, Firecrawl use against its allowance and daily share,
// progress (admitted in 24 hours, described, queued, held, written by hand) and the two jobs' last runs. Read only.
// ProviderDescriptionPrompt: the active prompt (pipeline.provider_description_prompts) with its version and history; the Platform Admin saves a
// new version with a reason (public.admin_provider_description_prompt_v1). A save is never an edit in place.
import React, { useEffect, useState } from 'react'
import { supabase } from './lib/supabase'
import Card from './Card'
import { Button, Loading, StatusChip } from './ui-kit'
import { fmtDateTime, fmtNumber } from './lib/format.js'
import { plainError } from './lib/errors'
import './provider-description-prompt.css'

const money = v => (v == null ? '—' : `US$${Number(v).toFixed(2)}`)
const when = v => (v ? fmtDateTime(v) : 'not yet')
export async function readPromptState() {
  const { data, error } = await supabase.rpc('admin_provider_description_prompt_v1', { p_action: 'read', p_args: {} })
  if (error) throw error
  return data || {}
}

export function ProviderDescriptionStatus({ state }) {
  const s = state?.status
  if (!s) return null
  const rows = [
    ['AI spend (lane)', `${money(s.ai_spent_usd)} of ${money(s.ai_ceiling_usd)}`],
    ['AI spend today', `${money(s.ai_today_usd)} of ${money(s.ai_daily_guard_usd)} a day`],
    ['Firecrawl reads', `${fmtNumber(s.firecrawl_used_window)} of ${fmtNumber(s.firecrawl_allowance)} in ${fmtNumber(s.firecrawl_window_hours)} h`],
    ['Firecrawl share left today', `${fmtNumber(s.firecrawl_share_left_today)} of ${fmtNumber(s.firecrawl_share_day)} credits`],
    ['Regular scan', `${fmtNumber(s.batch)} providers every ${fmtNumber(s.reader_every_minutes)} min · last ${when(s.reader_last?.at)}`],
    ['Self-heal', `last ${when(s.self_heal_last?.at)}${s.self_heal_last?.status ? ` (${s.self_heal_last.status})` : ''}`],
    ['Admitted in 24 h', fmtNumber(s.admitted_24h)],
    ['Providers described', fmtNumber(s.described)],
    ['Waiting', `${fmtNumber(s.queued)} queued${s.on_demand_waiting ? ` · ${fmtNumber(s.on_demand_waiting)} asked for by an operator` : ''}`],
    ['Held', fmtNumber(s.held)],
    ['Written by hand (never replaced)', fmtNumber(s.manual)],
  ]
  return <dl className="pdp-status" data-pdesc-status>
    {rows.map(([k, v]) => <div key={k} className="pdp-status-row"><dt>{k}</dt><dd>{v}</dd></div>)}
  </dl>
}

export default function ProviderDescriptionPrompt({ onError }) {
  const [d, setD] = useState(null), [text, setText] = useState(''), [reason, setReason] = useState(''), [busy, setBusy] = useState(false), [msg, setMsg] = useState('')
  const load = async () => { try { const x = await readPromptState(); setD(x); setText(x?.active?.system_prompt || '') } catch (e) { onError?.(plainError(e)) } }
  useEffect(() => { load() }, [])
  const changed = d?.active && text.trim() !== String(d.active.system_prompt || '').trim()
  const save = async () => {
    setBusy(true); setMsg('')
    try {
      const { data, error } = await supabase.rpc('admin_provider_description_prompt_v1', { p_action: 'save', p_args: { system_prompt: text, reason } })
      if (error) throw error
      setMsg(`Saved as version ${data?.version}. It is used from the next read; descriptions held under the earlier prompt are read again by the self-heal job.`)
      setReason(''); await load()
    } catch (e) { onError?.(plainError(e)) } finally { setBusy(false) }
  }
  return <Card id="services.ai.provider-description-prompt" title="Provider description prompt" data-pdesc-prompt
    subtitle="The instructions the AI follows to write a provider's description from its official About page. The checks that always apply are listed below the prompt."
    meta={d ? <StatusChip value={d.prompt_on ? 'enabled' : 'paused'} label={d.prompt_on ? `In use · version ${d.active?.version ?? '—'}` : 'Built-in prompt in use'}/> : null}>
    {!d ? <Loading label="Reading the prompt…"/> : <div className="pdp">
      <ProviderDescriptionStatus state={d}/>
      <label className="pdp-label" htmlFor="pdp-text">Prompt{d.can_edit ? '' : ' (read only: the Platform Admin edits it)'}</label>
      <textarea id="pdp-text" className="pdp-text" value={text} onChange={e => setText(e.target.value)} readOnly={!d.can_edit} rows={18} spellCheck/>
      <p className="pdp-note">Always checked, whatever the prompt says: the page is the provider&apos;s own About page and names it; every supporting passage is on the page; every number appears in its passage; a sentence is complete and supported by its passages; the first sentence names the provider; {d.length ? `${d.length.min_sentences} to ${d.length.max_sentences} sentences and ${d.length.min_chars} to ${d.length.max_chars} characters; ` : ''}never these words: {(Array.isArray(d.refused_words) ? d.refused_words : []).join(', ')}. A description written by hand is never replaced.</p>
      {d.can_edit && <div className="pdp-save">
        <input type="text" aria-label="Reason for the new prompt version" placeholder="Reason (kept in the log)" value={reason} onChange={e => setReason(e.target.value)} maxLength={300}/>
        <Button variant="primary" disabled={busy || !changed || reason.trim().length < 4} onClick={save}>Save as a new version</Button>
      </div>}
      {msg && <p role="status" className="pdp-note">{msg}</p>}
      {(d.history || []).length > 0 && <details className="pdp-history"><summary>Versions ({d.history.length})</summary>
        <ul>{d.history.map(h => <li key={h.version}><strong>Version {h.version}</strong> · {h.status} · {when(h.activated_at || h.created_at)} · {h.reason}</li>)}</ul>
      </details>}
    </div>}
  </Card>
}
