// Models & services › AI (v2.16.0, CF-247). Platform Admin, 13 Nov 2026:
//   19:14 "GPT 4.1 mini is too expensive it has exhausted the AI credit. use other cheaper model and define the usage per field in ui under
//          Model and Services. UI is useless and grown organically. define proper and clear controls of OpenRouter key and usage pane, Model
//          classified that can be used - Qwen3, Mimo, mistral small, Kimi K2, Gemini, LLama, deepseek and then Service based Model with
//          cascading, Then Recent usage, remove/retire all other older scripts"
//   19:15 "Keep prompt respective for each service as well"
//   19:23 "all settings corresponding to model using AI model/prompt or services should be defined in Model & services."
//   19:36 the old table showed "—" in the Model column for four AI uses, which hid that they ran on GPT-4.1 mini.
// One page, four panes (each a card, closed until opened and remembered for the session, as every card is: Decision 254; the closed card says
// its state), in this order: 1 OpenRouter key and usage, 2 Models, 3 Services, 4 Recent usage. It replaces AiConfig.jsx (OpenRouter
// account, AI uses and daily guards, central pages model, adapter proposal model, scholarship models, model profiles) and the AI model switches
// of ModelsServices.jsx. Two rules the page never breaks: a model cell is never blank (no model is a red "No model"), and an unknown figure is
// never 0 ("Not measured", "not checked").
// Reads public.admin_ai_overview_v1() and nothing else. Writes public.admin_ai_model_set_v1 and public.admin_ai_route_set_v1 (PIM Admin and above), the existing
// public.admin_toolsets_write for a setting or the OpenRouter mode, and the existing layer3-provider-control for the key (Platform Admin).
// Every save takes a reason and says what changed. Contract: docs/platform/AI-MODELS-SERVICES-CONTRACT.md.
import React, { useEffect, useMemo, useState } from 'react'
import { ArrowDown, ArrowUp, ChevronRight, KeyRound, Plus, RefreshCw, X } from 'lucide-react'
import { supabase } from './lib/supabase'
import Card, { rememberOpen } from './Card'
import { Button, Empty, Loading, fmtDateTime, fmtNumber, humanLabel } from './ui-kit'
import { plainError } from './lib/errors'
import { listShown, parseList, listValid, listError } from './lib/settings-list.js'
import { useViewerRank, PLATFORM_ADMIN_RANK, balanceWords } from './lib/viewer'
import { Switch } from './ModelsServices'
import { hrefFor } from './nav-map'
import { modelGroups, inAllowedFamily, serviceGroups, shortModel, usd, tokens, cascadeOf, serviceState, accountState, usageBy, usageBuckets, refusal } from './lib/ai-overview'
import './ai-models-services.css'

const say = e => refusal(e) || plainError(e)
const NOT_MEASURED = 'Not measured'
const money = v => usd(v) ?? NOT_MEASURED
const count = v => (v == null ? NOT_MEASURED : fmtNumber(Number(v)))
// A setting the server marks as no longer read (replaced by the routes) is shown with its value and cannot be changed here.
const notRead = s => Boolean(s.read_only || s.not_read)

// The four cards. An old link to a retired AI card opens the one that replaced it (nav-map RETIRED_AI_CARDS).
export const PANES = { openrouter: 'services.ai.openrouter', models: 'services.ai.models', services: 'services.ai.services', usage: 'services.ai.usage' }

function NoModel({ what = 'No model' }) { return <span className="cf-chip tone-danger aim-nomodel" data-ai-no-model>{what}</span> }

// What will change, a reason, Save and Cancel. Save stays off until the reason has 4 characters and nothing blocks it.
function SaveBar({ changes, blocked, busy, onSave, onCancel, label = 'Save', what }) {
  const [reason, setReason] = useState('')
  return <div className="aim-save" data-ai-save={what}>
    <ul className="aim-changes" data-ai-changes>{changes.map((c, i) => <li key={i}>{c}</li>)}</ul>
    {blocked && <p className="fr-error" role="alert" data-ai-blocked>{blocked}</p>}
    <div className="aim-save-row">
      <input className="fv-input aim-reason" aria-label={`Reason: ${what || label}`} placeholder="Reason (kept in the log)" value={reason} maxLength={300} onChange={e => setReason(e.target.value)}/>
      <Button compact variant="primary" disabled={busy || Boolean(blocked) || reason.trim().length < 4} onClick={() => onSave(reason.trim())} data-ai-confirm={what}>{busy ? 'Saving…' : label}</Button>
      <Button compact disabled={busy} onClick={onCancel}>Cancel</Button>
    </div>
  </div>
}

// One setting, changed in place with the existing audited write. Text is a text box, a number a number box with its range, yes/no a choice.
function AiSetting({ s, can, onSave }) {
  const shown = s.kind === 'list' ? listShown(s.value) : s.value == null ? '' : String(s.value)
  const [v, setV] = useState(shown), [busy, setBusy] = useState(false), [err, setErr] = useState(''), [done, setDone] = useState('')
  useEffect(() => { setV(shown) }, [shown])
  const yn = s.kind === 'boolean', ls = s.kind === 'list', tx = s.kind === 'text', n = Number(v), locked = notRead(s)
  const changed = v !== shown
  const valid = yn || tx ? (yn || v.trim() !== '') : ls ? listValid(s, v) : (v !== '' && Number.isFinite(n) && (s.min == null || n >= Number(s.min)) && (s.max == null || n <= Number(s.max)))
  const value = yn ? v === 'true' : ls ? parseList(v) : tx ? v.trim() : n
  const words = x => (yn ? (String(x) === 'true' ? 'Yes' : 'No') : `${x}${!tx && !ls && s.unit ? ` ${s.unit}` : ''}`)
  const save = async reason => { setBusy(true); setErr(''); setDone(''); try { await onSave(s, value, reason); setDone(`Saved. ${s.label}: ${words(shown)} is now ${words(v)}.`) } catch (e) { setErr(say(e)) } finally { setBusy(false) } }
  const range = !yn && !ls && !tx && s.min != null && s.max != null ? `${fmtNumber(Number(s.min))} to ${fmtNumber(Number(s.max))}` : ''
  return <div className="aim-setting" data-ai-setting={`${s.toolset}.${s.key}`} data-ai-setting-kind={s.kind}>
    <div className="aim-setting-text"><strong>{s.label || s.key}</strong>{s.help && <small>{s.help}</small>}{locked && <small className="aim-quiet">Not read any more: the model comes from the cascade above. Kept for the record.</small>}</div>
    <div className="aim-setting-edit">
      {can && !locked ? <label className="aim-setting-value"><span className="aim-hide">{s.label || s.key}</span>
        {yn ? <select className="fv-input" value={v} onChange={e => setV(e.target.value)}><option value="true">Yes</option><option value="false">No</option></select>
          : tx || ls ? <input className="fv-input aim-text" type="text" value={v} onChange={e => setV(e.target.value)}/>
          : <input className="fv-input aim-num" type="number" inputMode="decimal" step="any" min={s.min ?? undefined} max={s.max ?? undefined} value={v} onChange={e => setV(e.target.value)}/>}
        {!yn && s.unit && <span>{s.unit}</span>}</label>
        : <strong className="aim-setting-read">{shown === '' ? 'Not set' : words(shown)}</strong>}
      {range && <small className="aim-quiet">{range}</small>}
      {changed && !valid && <small className="fr-error">{ls ? listError(s) : tx ? 'Enter a value.' : range ? `Between ${range}.` : 'Enter a number.'}</small>}
      {changed && valid && <SaveBar what={s.key} busy={busy} changes={[`${s.label || s.key}: ${words(shown === '' ? 'not set' : shown)} becomes ${words(v)}`]} onSave={save} onCancel={() => setV(shown)}/>}
      {err && <small className="fr-error" role="alert">{err}</small>}
      {done && <small className="aim-done" role="status">{done}</small>}
    </div>
  </div>
}

const Meter = ({ value, max, label }) => {
  const known = value != null && Number(max) > 0, pct = known ? Math.min(100, Math.round(100 * Number(value) / Number(max))) : 0
  return <div className={`aim-meter${known && pct >= 100 ? ' is-full' : known && pct >= 80 ? ' is-near' : ''}`} role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={Number(max) || 0} aria-valuenow={known ? Number(value) : undefined} aria-valuetext={known ? `${pct}%` : 'not measured'}><span style={{ width: `${pct}%` }}/></div>
}

// ---- 1 OpenRouter key and usage -----------------------------------------------------------------------------------------------------------
function OpenRouterPane({ d, admin, saveSetting, reload, onError }) {
  const or = d.openrouter || {}, state = accountState(or)
  const [key, setKey] = useState(''), [keyMode, setKeyMode] = useState(''), [busy, setBusy] = useState(false), [msg, setMsg] = useState(''), [mode, setMode] = useState(false)
  const profile = or.key?.profile_id || null // what Replace and Verify need; the key itself is never returned by anything
  const run = async (fn) => { setBusy(true); setMsg(''); try { await fn() } catch (e) { onError?.(say(e)) } finally { setBusy(false) } }
  const saveKey = reason => run(async () => {
    const { data: r, error } = await supabase.functions.invoke('layer3-provider-control', { body: { action: 'set_credential', profile_id: profile, credential: key, reason } })
    if (error) throw error; if (r?.error) throw new Error(r.error)
    setKey(''); setKeyMode(''); setMsg('The OpenRouter key is replaced and stored in the vault. Press Verify to test it.'); await reload()
  })
  const verify = () => run(async () => {
    const { data: r, error } = await supabase.functions.invoke('layer3-provider-control', { body: { action: 'verify_credential', profile_id: profile } })
    if (error) throw error
    setMsg(r?.ok ? `Key verified: ${r.provider_model || 'the model'} answered.` : `Key not accepted: ${r?.message || r?.error || 'no answer'}`)
  })
  const flip = reason => run(async () => {
    const next = or.mode === 'observe' ? 'stop' : 'observe'
    const { error } = await supabase.rpc('admin_toolsets_write', { p_action: 'enforcement', p_args: { toolset: 'openrouter', enforcement: next, reason } })
    if (error) throw error
    setMode(false); setMsg(`Saved. Mode: ${next === 'stop' ? 'Stop at limits' : 'Observe only'}.`); await reload()
  })
  const main = ['credit_floor_usd', 'low_balance_warn_usd', 'budgets.ai_daily_ceiling_usd']
  const settings = or.settings || [], first = main.map(k => settings.find(s => s.key === k)).filter(Boolean), rest = settings.filter(s => !main.includes(s.key))
  const bal = or.balance_usd
  return <Card id={PANES.openrouter} level={2} className="aim-pane" data-ai-pane="openrouter" title="1 · OpenRouter key and usage" subtitle="Every AI model is called through OpenRouter with one key. The credit, the floor and the one daily spend ceiling for all services."
      meta={<><span className={`cf-chip tone-${state.tone}`} data-ai-account-chip={state.key}>{state.label}</span><span className="aim-quiet">{money(or.spent_today_usd)} of {usd(or.daily_ceiling_usd) ?? 'no ceiling'} today</span></>}
      action={<Button compact onClick={reload} disabled={busy}><RefreshCw size={14}/>Refresh</Button>}>
    <p className={`aim-state tone-${state.tone}`} data-ai-account-state={state.key} role="status"><span className={`cf-chip tone-${state.tone}`}>{state.label}</span><span>{state.text}</span></p>
    {or.balance_known === false && state.key !== 'unread' && <p className="aim-state tone-warning" role="status" data-ai-balance-unknown><span className="cf-chip tone-warning">Balance not measured</span><span>{or.balance_note || 'There is no balance reading, so the credit floor holds nothing.'}</span></p>}
    {d.caps_exceed_ceiling && <p className="aim-state tone-warning" role="status" data-ai-caps-exceed><span className="cf-chip tone-warning">Caps over the ceiling</span><span>Service caps add up to {money(d.caps_total_usd)} a day, more than the {money(d.ceiling_usd ?? or.daily_ceiling_usd)} ceiling: the ceiling will stop work first.</span></p>}
    <div className="aim-tiles">
      <div className="aim-tile" data-ai-key>
        <small><KeyRound size={12} aria-hidden/> Key</small>
        <strong>{or.key_present ? 'Present' : 'Not seen'}</strong>
        <span>{or.key?.secret || or.key_secret_name || 'OPENROUTER_API_KEY'} · never shown{or.key?.shared_by_profiles ? ` · shared by ${fmtNumber(Number(or.key.shared_by_profiles))} model profiles` : ''}</span>
      </div>
      <div className="aim-tile" data-ai-balance={admin ? 'figure' : 'words'}>
        <small>Credit balance</small>
        <strong>{or.balance_known === false ? 'Balance not measured' : admin ? (usd(bal) ?? 'Not read yet') : balanceWords(bal, or.floor_usd)}</strong>
        <span>{admin && or.total_credits_usd != null ? `of ${usd(or.total_credits_usd)} bought · ` : ''}read {or.balance_observed_at ? fmtDateTime(or.balance_observed_at) : 'never'}</span>
      </div>
      <div className="aim-tile" data-ai-floor>
        <small>Low-balance warning and floor</small>
        <strong>{usd(or.low_warn_usd) ?? 'Not set'} · {usd(or.floor_usd) ?? 'Not set'}</strong>
        <span>warning below the first; no credit at the second</span>
      </div>
      <div className="aim-tile aim-tile-wide" data-ai-ceiling>
        <small>Spent today (UTC) against the daily ceiling</small>
        <strong>{money(or.spent_today_usd)} of {usd(or.daily_ceiling_usd) ?? 'no ceiling'}</strong>
        <Meter value={or.spent_today_usd} max={or.daily_ceiling_usd} label="Today's spend against the daily ceiling"/>
        <span>All services together. At the ceiling every service is held until the UTC day changes.</span>
      </div>
    </div>
    <p className="aim-line" data-ai-mode={or.mode || 'unknown'}><strong>Mode:</strong> {or.mode === 'stop' ? 'Stop at limits' : or.mode === 'observe' ? 'Observe only' : 'Not recorded'}
      <span className="aim-quiet"> {or.mode === 'stop' ? 'The older daily guards and the credit floor stop AI.' : or.mode === 'observe' ? 'The older daily guards raise notices only. The daily ceiling and each service\'s cap still hold.' : ''}</span>
      {admin && or.mode && !mode && <Button compact disabled={busy} onClick={() => setMode(true)}>{or.mode === 'observe' ? 'Switch to stop at limits' : 'Switch to observe only'}</Button>}</p>
    {mode && <SaveBar what="mode" busy={busy} changes={[`Mode: ${or.mode === 'observe' ? 'Observe only becomes Stop at limits' : 'Stop at limits becomes Observe only'}`]} onSave={flip} onCancel={() => setMode(false)}/>}
    {admin ? <div className="aim-keyrow" data-ai-key-controls>
      <label className="aim-keyfield"><span>Replace the key (write-only)</span>
        <input className="fv-input" type="password" autoComplete="new-password" aria-label="New OpenRouter key" placeholder="Paste the new key; it replaces the old one" value={key} disabled={busy} onChange={e => { setKey(e.target.value); setKeyMode('') }}/></label>
      {keyMode !== 'save' && <Button compact variant="primary" disabled={busy || key.trim().length < 20 || !profile} onClick={() => setKeyMode('save')}>Replace key</Button>}
      <Button compact disabled={busy || !profile} onClick={verify}>Verify</Button>
      {!profile && <small className="aim-quiet">No model profile holds the key, so it cannot be replaced or verified from here.</small>}
    </div> : <p className="l3v-note">Only a Platform Admin can replace or verify the key and change these limits.</p>}
    {keyMode === 'save' && <SaveBar what="key" label="Replace key" busy={busy} changes={['The OpenRouter key used by every AI model is replaced. The key is never shown again.']} onSave={saveKey} onCancel={() => setKeyMode('')}/>}
    {msg && <p role="status" className="aim-done" data-ai-msg>{msg}</p>}
    <div className="aim-settings" data-ai-openrouter-settings>
      {first.map(s => <AiSetting key={`${s.toolset}.${s.key}`} s={s} can={admin} onSave={saveSetting}/>)}
      {rest.length > 0 && <details className="aim-more"><summary>Other OpenRouter settings ({fmtNumber(rest.length)})</summary>
        {rest.map(s => <AiSetting key={`${s.toolset}.${s.key}`} s={s} can={admin} onSave={saveSetting}/>)}</details>}
      {!settings.length && <p className="l3v-note">No OpenRouter settings were returned.</p>}
    </div>
  </Card>
}

// ---- 2 Models -----------------------------------------------------------------------------------------------------------------------------
function ModelsPane({ d, can, act }) {
  const groups = modelGroups(d.models || []), sLabel = Object.fromEntries((d.services || []).map(s => [s.service_code, s.label]))
  const [edit, setEdit] = useState(null), [busy, setBusy] = useState(false), [err, setErr] = useState(''), [done, setDone] = useState('')
  const save = async reason => { const m = edit; setBusy(true); setErr(''); setDone('')
    try { const next = m.status === 'allowed' ? 'not_allowed' : 'allowed'; await act('admin_ai_model_set_v1', { p_code: m.code, p_status: next, p_reason: reason }); setDone(`Saved. ${m.label} is now ${next === 'allowed' ? 'allowed' : 'not allowed'}.`); setEdit(null) }
    catch (e) { setErr(say(e)) } finally { setBusy(false) } }
  const allowedN = (d.models || []).filter(m => m.status === 'allowed').length, l3 = d.legacy?.layer3 || null
  return <Card id={PANES.models} level={2} className="aim-pane" data-ai-pane="models" title="2 · Models" subtitle="The one list of models a service may use, by family. A model that is not allowed is skipped in every cascade."
      meta={<><span className="aim-quiet" data-ai-models-count>{fmtNumber(allowedN)} of {fmtNumber((d.models || []).length)} allowed</span>{Number(d.guard) > 0 && <span className="cf-chip tone-warning">{fmtNumber(Number(d.guard))} to check</span>}</>}>
    {!can && <p className="l3v-note">You can view the list. A PIM Admin or above allows or disallows a model.</p>}
    {done && <p className="aim-done" role="status">{done}</p>}{err && <p className="fr-error" role="alert">{err}</p>}
    {Number(d.guard) > 0 && <p className="aim-state tone-warning" role="status" data-ai-guard={d.guard}><span className="cf-chip tone-warning">{fmtNumber(Number(d.guard))} to check</span><span>{Number(d.guard) === 1 ? 'One place' : `${fmtNumber(Number(d.guard))} places`} outside the services still name{Number(d.guard) === 1 ? 's' : ''} a model that is not allowed. No service uses {Number(d.guard) === 1 ? 'it' : 'them'}; see Layer 3 below.</span></p>}
    {!groups.length ? <Empty text="No models are listed."/> : <div className="cf-table-wrap aim-wrap"><table className="cf-table aim-table aim-models" data-ai-models data-no-resize>
      <thead><tr><th>Model</th><th>OpenRouter id</th><th className="num">Price in / out, per million tokens</th><th className="num">Context</th><th>Used by</th><th>Allowed</th></tr></thead>
      {groups.map(g => <tbody key={g.key} data-ai-family={g.key}>
        <tr className="aim-group"><th colSpan={6} scope="rowgroup">{g.label}{g.key === 'not_allowed' && <small> GPT, Claude and anything outside the seven families</small>}</th></tr>
        {g.models.map(m => { const on = m.status === 'allowed', family = inAllowedFamily(m), price = m.input_usd_per_mtok != null && m.output_usd_per_mtok != null
          return <React.Fragment key={m.code}><tr className={on ? '' : 'aim-off'} data-ai-model={m.code} data-ai-model-status={m.status}>
            <td data-label="Model"><strong>{m.label || m.code}</strong>{m.note && <small className="aim-sub">{m.note}</small>}</td>
            <td data-label="OpenRouter id"><code className="aim-code">{m.model_identifier || 'Not recorded'}</code></td>
            <td data-label="Price in / out per M tokens" className="num" data-ai-price={price ? 'known' : 'not-checked'}>{price ? <><span>{usd(m.input_usd_per_mtok, 2)} / {usd(m.output_usd_per_mtok, 2)}</span>{m.price_checked_at && <small className="aim-sub">checked {fmtDateTime(m.price_checked_at)}</small>}</> : <span className="aim-quiet">not checked</span>}</td>
            <td data-label="Context" className="num">{tokens(m.context_tokens) ? <span>{tokens(m.context_tokens)}</span> : <span className="aim-quiet">not checked</span>}</td>
            <td data-label="Used by">{(m.used_by || []).length ? <span className="aim-usedby">{m.used_by.map(c => <span key={c} className="cf-chip tone-neutral">{sLabel[c] || humanLabel(c)}</span>)}</span> : <span className="aim-quiet">No service</span>}</td>
            <td data-label="Allowed"><span className="aim-allow"><Switch on={on} label={`${on ? 'Disallow' : 'Allow'} ${m.label || m.code}`} disabled={!can || busy || (!on && !family)} onChange={() => { setErr(''); setEdit(m) }}/>
              <span className={on ? '' : 'aim-quiet'}>{on ? 'Allowed' : 'Not allowed'}</span>{on && !family && <span className="cf-chip tone-warning">Outside the families</span>}</span>
              {!on && !family && <small className="aim-sub" data-ai-family-refused>Not in a family the Platform Admin allows; adding a family is a release.</small>}
              {(m.reason || m.changed_at) && <small className="aim-sub">{m.reason}{m.changed_at ? ` · ${fmtDateTime(m.changed_at)}` : ''}</small>}</td>
          </tr>
          {edit?.code === m.code && <tr className="aim-editrow"><td colSpan={6}><SaveBar what={`model-${m.code}`} busy={busy} onSave={save} onCancel={() => setEdit(null)}
            changes={[`${m.label}: ${on ? 'Allowed becomes Not allowed' : 'Not allowed becomes Allowed'}`,
              ...(on && (m.used_by || []).length ? [`${fmtNumber(m.used_by.length)} service${m.used_by.length === 1 ? ' names' : 's name'} it (${m.used_by.map(c => sLabel[c] || c).join(', ')}). It stays in their cascades and is skipped; a service left with no allowed model stops.`] : []),
              ...(!on ? ['It is offered again when a cascade is edited. It is not added to any cascade by this.'] : [])]}/></td></tr>}
          </React.Fragment> })}
      </tbody>)}
    </table></div>}
    {l3 && <details className="aim-more" data-ai-layer3><summary>Layer 3 (retired 12 Oct 2026): {fmtNumber((l3.profiles_switched_on || []).length)} model profile{(l3.profiles_switched_on || []).length === 1 ? '' : 's'} still switched on in its own table</summary>
      <p className="aim-note">{l3.note || 'Layer 3 is retired and does not use the services above.'} Last call: {l3.last_call_at ? fmtDateTime(l3.last_call_at) : 'not recorded'}. Scheduled jobs that name it: {(l3.jobs || []).length ? l3.jobs.join(', ') : 'none'}.</p>
      {(l3.profiles_switched_on || []).length > 0 && <ul className="aim-events">{l3.profiles_switched_on.map(p => <li key={p.code}><code className="aim-code">{p.model_identifier || 'No model'}</code> {(p.tasks || []).map(humanLabel).join(', ')} <span className={`cf-chip tone-${p.catalogue_status === 'allowed' ? 'neutral' : 'danger'}`}>{p.catalogue_status === 'allowed' ? 'Allowed model' : 'Model not allowed'}</span> {p.in_active_tier ? 'in an active tier' : 'not in an active tier'}</li>)}</ul>}
    </details>}
  </Card>
}

// ---- 3 Services ---------------------------------------------------------------------------------------------------------------------------
function Cascade({ items }) {
  if (!items.length) return <NoModel/>
  return <span className="aim-cascade" data-ai-cascade>{items.map((m, i) => <React.Fragment key={m.code}>
    {i > 0 && <span className="aim-arrow" aria-hidden>→</span>}
    <span className={`aim-chip${m.allowed ? '' : ' is-out'}`} title={`${m.label}${m.model_identifier ? ` (${m.model_identifier})` : ''}${m.allowed ? '' : ': not allowed, skipped'}`} data-ai-cascade-model={m.code}><b>{i + 1}</b> {shortModel(m.label)}{!m.allowed && <em> not allowed</em>}</span>
  </React.Fragment>)}</span>
}

// where a prompt is kept, in plain words (the stored name stays on hover)
const promptSource = src => { const v = String(src || '').trim(); if (!v) return 'Not recorded'; const m = v.match(/^[a-z_]+\.([a-z0-9_]+)$/); return m ? `the platform's database (${m[1].replace(/_/g, ' ')})` : v }
const capWords = (v, unit) => (v == null ? 'no cap' : unit === 'usd' ? usd(v) : `${fmtNumber(Number(v))} calls`)
const sameList = (a, b) => a.length === b.length && a.every((x, i) => x === b[i])

function ServiceRow({ s, d, can, admin, act, saveSetting, open, onToggle, onError }) {
  const models = d.models || [], items = cascadeOf(s, models), state = serviceState(s)
  const [draft, setDraft] = useState(null), [busy, setBusy] = useState(false), [err, setErr] = useState(''), [done, setDone] = useState(''), [promptEdit, setPromptEdit] = useState(false)
  const byCode = Object.fromEntries(models.map(m => [m.code, m]))
  const begin = (patch = {}) => { setErr(''); setDone(''); setDraft({ cascade: [...(s.cascade || [])], usd: s.daily_usd_cap == null ? '' : String(s.daily_usd_cap), calls: s.daily_calls_cap == null ? '' : String(s.daily_calls_cap), enabled: s.enabled !== false, ...patch }); if (!open) onToggle(true) }
  const set = patch => setDraft(x => ({ ...x, ...patch }))
  // the model in use: `model` (the first allowed model of the cascade); `model_in_effect` is the same thing in the contract's first issue
  const inUse = s.model ?? s.model_in_effect ?? null
  const effect = inUse ? (models.find(m => m.model_identifier === inUse)?.label || inUse) : null
  const firstAllowed = (s.models || [])[0]?.model_identifier || null
  const prompt = s.prompt || {}, inWorker = /worker code/i.test(String(prompt.source || ''))
  // ---- the draft: what changed and whether it may be saved
  let changes = [], blocked = '', payload = null
  if (draft) {
    const usdN = draft.usd.trim() === '' ? null : Number(draft.usd), callsN = draft.calls.trim() === '' ? null : Number(draft.calls)
    const name = c => `${shortModel(byCode[c]?.label || c)}`, line = list => (list.length ? list.map((c, i) => `${i + 1} ${name(c)}`).join(' → ') : 'no model')
    if (!sameList(draft.cascade, s.cascade || [])) changes.push(`Cascade: ${line(s.cascade || [])} becomes ${line(draft.cascade)}`)
    if (usdN !== (s.daily_usd_cap == null ? null : Number(s.daily_usd_cap))) changes.push(`Daily cap (US$): ${capWords(s.daily_usd_cap, 'usd')} becomes ${Number.isFinite(usdN) || usdN == null ? capWords(usdN, 'usd') : draft.usd}`)
    if (callsN !== (s.daily_calls_cap == null ? null : Number(s.daily_calls_cap))) changes.push(`Daily cap (calls): ${capWords(s.daily_calls_cap, 'calls')} becomes ${Number.isFinite(callsN) || callsN == null ? capWords(callsN, 'calls') : draft.calls}`)
    if (draft.enabled !== (s.enabled !== false)) changes.push(`Switch: ${s.enabled !== false ? 'On becomes Off' : 'Off becomes On'}`)
    const out = draft.cascade.filter(c => byCode[c]?.status !== 'allowed')
    if (!draft.cascade.length) blocked = 'The cascade is empty: name at least one allowed model.'
    else if (out.length) blocked = `Not an allowed model: ${out.map(c => byCode[c]?.label || c).join(', ')}. Remove it, or allow it in Models first.`
    else if (usdN == null) blocked = 'Give a daily US$ cap: every service has one.'
    else if ((usdN != null && !(usdN >= 0)) || (callsN != null && !(callsN >= 0 && Number.isInteger(callsN)))) blocked = 'A cap is a number that is not negative (calls: a whole number). The calls cap may be left empty for none.'
    payload = { p_service: s.service_code, p_cascade: draft.cascade, p_daily_usd_cap: usdN, p_daily_calls_cap: callsN, p_enabled: draft.enabled }
  }
  const save = async reason => { setBusy(true); setErr(''); setDone('')
    try { const said = changes.join(' '); await act('admin_ai_route_set_v1', { ...payload, p_reason: reason }); setDone(`Saved. ${said}`); setDraft(null) } catch (e) { setErr(say(e)) } finally { setBusy(false) } }
  const addable = models.filter(m => m.status === 'allowed' && !(draft?.cascade || []).includes(m.code))
  const move = (i, by) => { const c = [...draft.cascade], j = i + by; if (j < 0 || j >= c.length) return; [c[i], c[j]] = [c[j], c[i]]; set({ cascade: c }) }
  const spent = s.spent_today || {}
  return <>
    <tr className={`aim-service${open ? ' is-open' : ''}${s.enabled === false ? ' aim-off' : ''}`} data-ai-service={s.service_code} data-ai-service-state={state.key}>
      <td data-label="Service"><button type="button" className="aim-toggle" aria-expanded={open} aria-controls={`aim-d-${s.service_code}`} onClick={() => onToggle(!open)}><ChevronRight size={15} className="aim-chev" aria-hidden/><strong>{s.label || humanLabel(s.service_code)}</strong></button>
        {s.field && <small className="aim-sub aim-indent">Field: {humanLabel(s.field)}</small>}</td>
      <td data-label="Model cascade" data-ai-model-cell><Cascade items={items}/>
        {items.length > 0 && !(s.models || []).length && <NoModel what="No allowed model"/>}
        {(s.models || []).length > 0 && !inUse && <small className="aim-sub" data-ai-in-effect>In use today: <NoModel/></small>}
        {inUse && inUse !== firstAllowed && <small className="aim-sub" data-ai-in-effect>In use today: <strong title={inUse}>{shortModel(effect)}</strong></small>}
</td>
      <td data-label="On"><span className="aim-allow"><Switch on={s.enabled !== false} label={`${s.enabled !== false ? 'Switch off' : 'Switch on'} ${s.label}`} disabled={!can || busy} onChange={on => begin({ enabled: on })}/></span></td>
      <td data-label="Daily cap"><span>{s.daily_usd_cap == null ? 'No US$ cap' : usd(s.daily_usd_cap)}</span><small className="aim-sub">{s.daily_calls_cap == null ? 'no call cap' : `${fmtNumber(Number(s.daily_calls_cap))} calls`}</small></td>
      <td data-label="Spent today" data-ai-spent><span>{money(spent.usd)}{s.daily_usd_cap != null ? ` of ${usd(s.daily_usd_cap)}` : ''}</span>
        {s.daily_usd_cap != null && <Meter value={spent.usd} max={s.daily_usd_cap} label={`${s.label}: today's spend against its cap`}/>}
        <small className="aim-sub">{spent.calls == null ? 'calls not measured' : `${fmtNumber(Number(spent.calls))} call${Number(spent.calls) === 1 ? '' : 's'}`}{s.daily_calls_cap != null ? ` of ${fmtNumber(Number(s.daily_calls_cap))}` : ''}</small></td>
      <td data-label="State"><span className={`cf-chip tone-${state.tone}`} title={state.why} data-ai-state-pill>{state.label}</span>{state.why && state.key !== 'running' && <small className="aim-sub">{state.why}</small>}
        {s.would_hold_now && <small className="aim-sub" data-ai-would-hold>Would be held now: no scheduled work is handed out.</small>}</td>
    </tr>
    {open && <tr className="aim-detailrow" id={`aim-d-${s.service_code}`} data-ai-service-detail={s.service_code}><td colSpan={6}><div className="aim-detail">
      {done && <p className="aim-done" role="status" data-ai-saved>{done}</p>}{err && <p className="fr-error" role="alert" data-ai-error>{err}</p>}
      <div className="aim-block" data-ai-route>
        <h4>Model cascade, switch and daily cap</h4>
        {!draft ? <><p className="aim-line"><Cascade items={items}/></p>
          <p className="aim-quiet">The first allowed model is the one in use. Where the reader can, it tries the next one when a call fails technically (an error, a time-out, an unreadable answer), never because of what a model answered. Only allowed models can be added.</p>
          {(s.enforced === false || s.wired === false) && <p className="aim-note tone-warn" data-ai-unwired>This reader does not ask its route yet: what is saved here is kept but may not act on it.</p>}
          {s.note && <p className="aim-note">{s.note}</p>}
          {can ? <Button compact onClick={() => begin()} data-ai-edit={s.service_code}>Change cascade, switch or cap</Button> : <p className="l3v-note">A PIM Admin or above changes a service.</p>}</>
        : <div className="aim-editor" data-ai-editor={s.service_code}>
          <ol className="aim-steps">{draft.cascade.map((c, i) => { const m = byCode[c], ok = m?.status === 'allowed'
            return <li key={c} className={ok ? '' : 'is-out'} data-ai-step={c}><span><b>{i + 1}</b> {m?.label || c}{!ok && <em> not allowed</em>}</span>
              <span className="aim-step-acts"><button type="button" className="aim-icon" aria-label={`Move ${m?.label || c} up`} disabled={i === 0} onClick={() => move(i, -1)}><ArrowUp size={14}/></button>
                <button type="button" className="aim-icon" aria-label={`Move ${m?.label || c} down`} disabled={i === draft.cascade.length - 1} onClick={() => move(i, 1)}><ArrowDown size={14}/></button>
                <button type="button" className="aim-icon" aria-label={`Remove ${m?.label || c}`} onClick={() => set({ cascade: draft.cascade.filter(x => x !== c) })}><X size={14}/></button></span></li> })}
            {!draft.cascade.length && <li className="aim-empty-step"><NoModel/> Add at least one allowed model.</li>}</ol>
          <label className="aim-add"><span><Plus size={13} aria-hidden/> Add a model</span>
            <select className="fv-input" aria-label={`Add a model to ${s.label}`} value="" disabled={!addable.length} onChange={e => { if (e.target.value) set({ cascade: [...draft.cascade, e.target.value] }) }}>
              <option value="">{addable.length ? 'Choose an allowed model' : 'No other allowed model'}</option>
              {addable.map(m => <option key={m.code} value={m.code}>{m.label}{m.input_usd_per_mtok != null ? ` · ${usd(m.input_usd_per_mtok)} / ${usd(m.output_usd_per_mtok)}` : ' · price not checked'}</option>)}</select></label>
          <div className="aim-caps">
            <label><span>Daily cap, US$</span><input className="fv-input aim-num" inputMode="decimal" aria-label={`Daily cap in US dollars for ${s.label}`} placeholder="required" value={draft.usd} onChange={e => set({ usd: e.target.value })}/></label>
            <label><span>Daily cap, calls</span><input className="fv-input aim-num" inputMode="numeric" aria-label={`Daily cap in calls for ${s.label}`} placeholder="no cap" value={draft.calls} onChange={e => set({ calls: e.target.value })}/></label>
            <label className="aim-onoff"><span>Service</span><span className="aim-allow"><Switch on={draft.enabled} label={`${s.label} on or off`} onChange={on => set({ enabled: on })}/>{draft.enabled ? 'On' : 'Off'}</span></label>
          </div>
          {changes.length || blocked ? <SaveBar what={`route-${s.service_code}`} busy={busy} changes={changes.length ? changes : ['Nothing changed yet.']} blocked={blocked || (changes.length ? '' : ' ')} onSave={save} onCancel={() => setDraft(null)}/>
            : <p className="aim-save-row"><span className="aim-quiet">Nothing changed yet.</span><Button compact onClick={() => setDraft(null)}>Cancel</Button></p>}
        </div>}
      </div>
      <div className="aim-block" data-ai-prompt={s.service_code}>
        <h4>Prompt</h4>
        <p className="aim-line"><strong>Source:</strong> <span title={prompt.source || undefined}>{promptSource(prompt.source)}</span> <strong>Version:</strong> {prompt.version || 'Not recorded'}</p>
        {prompt.text ? <pre className="aim-prompt" tabIndex={0} aria-label={`Prompt of ${s.label} (read only)`}>{prompt.text}</pre>
          : <p className="aim-note" data-ai-prompt-kept>{inWorker || prompt.version ? 'The prompt text is kept in the worker. It changes with a worker release, as a new version.' : 'The prompt text is not held here.'}</p>}
        {prompt.source === 'pipeline.provider_description_prompts' && admin && (promptEdit
          ? <React.Suspense fallback={<Loading compact label="Reading the prompt…"/>}><PromptEditor onError={onError}/></React.Suspense>
          : <Button compact onClick={() => setPromptEdit(true)}>Edit this prompt as a new version</Button>)}
        {prompt.source === 'pipeline.scholarship_ai_prompts' && <p className="aim-line"><a className="cf-link" href={hrefFor('scholarships', 'extraction')}>Instructions, sample pages and qualification are on Scholarships › Coverage › Extraction</a></p>}
      </div>
      <div className="aim-block" data-ai-service-settings={s.service_code}>
        <h4>Other AI settings of this service</h4>
        {(s.settings || []).length ? s.settings.map(x => <AiSetting key={`${x.toolset}.${x.key}`} s={x} can={admin} onSave={saveSetting}/>) : <p className="aim-quiet">This service has no other AI settings.</p>}
        {(s.settings || []).length > 0 && !admin && <p className="l3v-note">Only a Platform Admin changes a setting.</p>}
      </div>
      <p className="aim-meta">Spend counted from: {humanLabel(s.lane) || 'not recorded'}. Last change: {s.reason || 'none recorded'}{s.changed_by ? ` · ${s.changed_by}` : ''}{s.changed_at ? ` · ${fmtDateTime(s.changed_at)}` : ''}</p>
    </div></td></tr>}
  </>
}
const PromptEditor = React.lazy(() => import('./ProviderDescriptionPrompt'))

function ServicesPane({ d, can, admin, act, saveSetting, focus, onError }) {
  const groups = serviceGroups(d.services || [])
  const [open, setOpen] = useState(() => (focus ? { [focus]: true } : {}))
  useEffect(() => { if (focus) setOpen(o => ({ ...o, [focus]: true })) }, [focus])
  const noModel = (d.services || []).filter(s => !(s.models || []).length)
  const held = (d.services || []).filter(s => ['cap', 'ceiling', 'credit_floor', 'held'].includes(serviceState(s).key)).length
  return <Card id={PANES.services} level={2} className="aim-pane" data-ai-pane="services" title="3 · Services" subtitle="What the platform uses AI for, one row each: its model cascade, switch, daily cap and today's spend. Open a row for its prompt and its other AI settings."
      meta={<><span className="aim-quiet">{fmtNumber((d.services || []).length)} services</span>{noModel.length > 0 && <span className="cf-chip tone-danger" data-ai-no-model-chip>{fmtNumber(noModel.length)} with no model</span>}{held > 0 && <span className="cf-chip tone-warning">{fmtNumber(held)} held</span>}</>}>
    {noModel.length > 0 && <p className="aim-state tone-danger" role="alert" data-ai-no-model-warning><span className="cf-chip tone-danger">No model</span><span>{noModel.map(s => s.label).join(', ')}: no allowed model. {noModel.length === 1 ? 'It does' : 'They do'} not run until a cascade names one.</span></p>}
    {!groups.length ? <Empty text="No services are listed."/> : <div className="cf-table-wrap aim-wrap"><table className="cf-table aim-table aim-services" data-ai-services data-no-resize>
      <thead><tr><th>Service</th><th>Model cascade</th><th>On</th><th>Daily cap</th><th>Spent today (UTC)</th><th>State</th></tr></thead>
      {groups.map(g => <tbody key={g.area} data-ai-area={g.area}>
        <tr className="aim-group"><th colSpan={6} scope="rowgroup">{g.area}</th></tr>
        {g.services.map(s => <ServiceRow key={s.service_code} s={s} d={d} can={can} admin={admin} act={act} saveSetting={saveSetting} onError={onError} open={Boolean(open[s.service_code])} onToggle={v => setOpen(o => ({ ...o, [s.service_code]: v }))}/>)}
      </tbody>)}
    </table></div>}
    {(d.events || []).length > 0 && <details className="aim-more" data-ai-events><summary>Changes made here ({fmtNumber(d.events.length)} most recent)</summary>
      <ul className="aim-events">{d.events.map((e, i) => <li key={i}><small>{fmtDateTime(e.at)}</small> <strong>{e.action === 'model_set' ? 'Model' : e.action === 'route_set' ? 'Service' : humanLabel(e.action)}</strong> {e.target}{e.detail?.reason ? `: ${e.detail.reason}` : ''}{e.by ? ` · ${e.by}` : ''}</li>)}</ul></details>}
  </Card>
}

// ---- 4 Recent usage -----------------------------------------------------------------------------------------------------------------------
function UsagePane({ d }) {
  const [unit, setUnit] = useState('hour'), [by, setBy] = useState('service')
  const rows = unit === 'hour' ? d.usage?.by_hour_24h : d.usage?.by_day_14d
  const groups = useMemo(() => usageBy(rows, by, d), [rows, by, d]), buckets = useMemo(() => usageBuckets(rows, unit), [rows, unit])
  const top = Math.max(0, ...(groups || []).map(g => Number(g.usd || 0))), peak = Math.max(0, ...(buckets || []).map(b => Number(b.usd || 0)))
  const total = groups && groups.some(g => g.usd != null) ? groups.reduce((n, g) => n + Number(g.usd || 0), 0) : null
  const calls = groups && groups.some(g => g.calls != null) ? groups.reduce((n, g) => n + Number(g.calls || 0), 0) : null
  const when = b => (unit === 'hour' ? new Date(b.t).toISOString().slice(11, 16) : new Date(b.t).toISOString().slice(5, 10).split('-').reverse().join('/'))
  const pick = (cur, set, items, label) => <div className="pg-views" role="toolbar" aria-label={label}>{items.map(([k, l]) => <button key={k} type="button" className={`pg-view${cur === k ? ' is-on' : ''}`} aria-pressed={cur === k} onClick={() => set(k)} data-ai-usage-pick={k}>{l}</button>)}</div>
  return <Card id={PANES.usage} level={2} className="aim-pane" data-ai-pane="usage" title="4 · Recent usage" subtitle="Spend and calls by service and by model. Times and days are UTC, the same day the caps and the ceiling count."
      meta={<span className="aim-quiet">{money(d.openrouter?.spent_today_usd)} today</span>}>
    <div className="aim-usage-picks">{pick(unit, setUnit, [['hour', 'Last 24 hours, by hour'], ['day', 'Last 14 days, by day']], 'Period')}{pick(by, setBy, [['service', 'By service'], ['model', 'By model']], 'Group by')}</div>
    {!groups ? <p className="aim-note" data-ai-usage-none>{NOT_MEASURED}: no usage figures were returned for this period.</p> : <>
      <p className="aim-line" data-ai-usage-total><strong>{money(total)}</strong> spent · <strong>{count(calls)}</strong> calls {unit === 'hour' ? 'in the last 24 hours' : 'in the last 14 days'}</p>
      <ol className="aim-strip" data-ai-usage-strip={unit} aria-label={unit === 'hour' ? 'Spend in each of the last 24 hours' : 'Spend on each of the last 14 days'}>
        {buckets.map(b => <li key={b.t} title={`${when(b)}: ${b.recorded ? `${money(b.usd)}, ${count(b.calls)} calls` : 'nothing recorded'}`}>
          <span className="aim-bar" aria-hidden><span style={{ height: `${b.usd != null && peak > 0 ? Math.max(4, Math.round(100 * b.usd / peak)) : 0}%` }}/></span>
          <span className="aim-strip-label">{when(b)}</span><span className="aim-hide">{b.recorded ? `${money(b.usd)}, ${count(b.calls)} calls` : 'nothing recorded'}</span></li>)}
      </ol>
      {!groups.length ? <p className="aim-note" data-ai-usage-empty>Nothing was recorded in this period.</p> : <div className="cf-table-wrap aim-wrap"><table className="cf-table aim-table" data-no-resize data-ai-usage={`${unit}-${by}`}>
        <thead><tr><th>{by === 'service' ? 'Service' : 'Model'}</th><th className="num">Calls</th><th className="num">Spend</th><th>Share of the largest</th></tr></thead>
        <tbody>{groups.map(g => <tr key={g.key} data-ai-usage-row={g.key}>
          <td data-label={by === 'service' ? 'Service' : 'Model'}><strong>{g.label}</strong>{g.sub && <small className="aim-sub"><code className="aim-code">{g.sub}</code></small>}{by === 'model' && g.key === '(none)' && <small className="aim-sub">Spend recorded before models were recorded per call.</small>}</td>
          <td data-label="Calls" className="num"><span>{count(g.calls)}</span></td>
          <td data-label="Spend" className="num"><span>{money(g.usd)}</span></td>
          <td data-label="Share"><span className="aim-hbar" aria-hidden><span style={{ width: `${g.usd != null && top > 0 ? Math.max(2, Math.round(100 * g.usd / top)) : 0}%` }}/></span></td>
        </tr>)}</tbody>
      </table></div>}
    </>}
  </Card>
}

// ---- the page -----------------------------------------------------------------------------------------------------------------------------
export default function AiModelsServices({ onError, focusService = '' }) {
  const rank = useViewerRank(), admin = rank >= PLATFORM_ADMIN_RANK
  const [d, setD] = useState(null), [failed, setFailed] = useState('')
  const load = async () => { setFailed(''); try { const { data, error } = await supabase.rpc('admin_ai_overview_v1'); if (error) throw error; if (!data || Array.isArray(data) || !data.openrouter) throw new Error('The AI overview is not available yet.'); setD(data) } catch (e) { setFailed(say(e)) } }
  useEffect(() => { load() }, [])
  if (focusService) rememberOpen(PANES.services) // a link to one service opens the Services card
  // Both writes answer with the whole overview, so the page shows exactly what was saved
  const act = async (fn, args) => { const { data, error } = await supabase.rpc(fn, args); if (error) throw error; if (data && data.openrouter) setD(data); else await load() }
  const saveSetting = async (s, value, reason) => { const { error } = await supabase.rpc('admin_toolsets_write', { p_action: 'setting', p_args: { toolset: s.toolset, key: s.key, value, reason } }); if (error) throw error; await load() }
  if (failed && !d) return <section className="m-panel" data-ai-page="failed"><Empty text={`Models and services could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if (!d) return <section className="m-panel" data-ai-page="loading"><Loading label="Loading models and services…"/></section>
  const can = Boolean(d.can_control)
  return <div className="m-page-stack aim" data-ai-page="ready">
    <OpenRouterPane d={d} admin={admin} saveSetting={saveSetting} reload={load} onError={onError}/>
    <ModelsPane d={d} can={can} act={act}/>
    <ServicesPane d={d} can={can} admin={admin} act={act} saveSetting={saveSetting} focus={focusService} onError={onError}/>
    <UsagePane d={d}/>
  </div>
}
