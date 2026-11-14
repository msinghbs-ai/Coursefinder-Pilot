// Models & services › AI (v2.16.0, CF-247). Platform Admin, 13 Nov 2026:
//   19:14 "GPT 4.1 mini is too expensive it has exhausted the AI credit. use other cheaper model and define the usage per field in ui under
//          Model and Services. UI is useless and grown organically. define proper and clear controls of OpenRouter key and usage pane, Model
//          classified that can be used - Qwen3, Mimo, mistral small, Kimi K2, Gemini, LLama, deepseek and then Service based Model with
//          cascading, Then Recent usage, remove/retire all other older scripts"
//   19:15 "Keep prompt respective for each service as well"
//   19:23 "all settings corresponding to model using AI model/prompt or services should be defined in Model & services."
//   19:36 the old table showed "—" in the Model column for four AI uses, which hid that they ran on GPT-4.1 mini.
// One page, four panes (each a card that can be collapsed; a collapsed card still says its state and its warnings), in this order: 1 OpenRouter key and usage, 2 Models, 3 Services, 4 Recent usage. It replaces AiConfig.jsx (OpenRouter
// account, AI uses and daily guards, central pages model, adapter proposal model, scholarship models, model profiles) and the AI model switches
// of ModelsServices.jsx. Two rules the page never breaks: a model cell is never blank (no model is a red "No model"), and an unknown figure is
// never 0 ("Not measured", "not checked").
// Reads public.admin_ai_overview_v1() and nothing else. Writes public.admin_ai_model_set_v1 and public.admin_ai_route_set_v1 (PIM Admin and above), the existing
// public.admin_toolsets_write for a setting or the OpenRouter mode, and the existing layer3-provider-control for the key (Platform Admin).
// Platform Admin written review, 13 Nov 2026 22:10 (the decisions this page follows):
//   "Default to expanded panes on desktop. Allow collapsing, but keep warnings visible." The four cards open by default at desktop width (the
//       stated exception to cards-start-closed, Decision 254); on a phone they start closed; a closed card still shows its warnings.
//   "Do not silently remove role-3 read-only access." Curator and above read the page; a control a role cannot use says which role it needs:
//       route, cap and switch PIM Admin (rank 5); the model list, qualification, the daily ceiling and the key Platform Admin (rank 6).
//   "Scholarship Extraction configuration belongs in Models & Services." It opens inside the Scholarship pages service.
//   "Do not display a model cascade as operational unless the worker actually executes it." migration_state decides: routed shows the cascade
//       editor; routed_single one model and "Fallback not available for this service yet"; not_migrated a read-only row with the model in effect.
//       A model that is allowed but not qualified for a service cannot be added to its cascade.
// Every save takes a reason and says what changed. Contract: docs/platform/AI-MODELS-SERVICES-CONTRACT.md.
import React, { useEffect, useMemo, useState } from 'react'
import { ArrowDown, ArrowUp, ChevronRight, KeyRound, Plus, RefreshCw, X } from 'lucide-react'
import { supabase } from './lib/supabase'
import Card, { rememberOpen } from './Card'
import { Button, Empty, Loading, fmtDateTime, fmtNumber, fmtRelative, humanLabel } from './ui-kit'
import { plainError } from './lib/errors'
import { listShown, parseList, listValid, listError } from './lib/settings-list.js'
import { useViewerRank, PLATFORM_ADMIN_RANK, balanceWords } from './lib/viewer'
import { Switch } from './ModelsServices'
import { modelGroups, inAllowedFamily, serviceGroups, shortModel, usd, tokens, cascadeOf, serviceState, accountState, usageBy, usageBuckets, refusal, migrationOf, qualification, isQualified, lastCall, recoveryOf, wouldHold, recoveryWords, callErrorWords, noModelKind, noModelWords, heldReasons, failureSummary } from './lib/ai-overview'
import './ai-models-services.css'

const say = e => refusal(e) || plainError(e)
const NOT_MEASURED = 'Not measured'
const ROLE = { 5: 'PIM Admin', 6: 'Platform Admin' }
const Needs = ({ rank, what }) => <small className="aim-need" data-ai-needs={rank}>{what ? `${what}: needs` : 'Needs'} {ROLE[rank]}</small>
// the four cards open by default at desktop width only (Platform Admin 13 Nov 2026 22:10); on a phone they start closed, as every card does
const desktop = () => { try { return window.matchMedia('(min-width: 761px)').matches } catch { return false } }
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

// ---- the limits banner (Platform Admin 14 Nov 2026: "Make the Observe vs. Stop mode banner clearer and unmissable at the top of the page so the
// Platform Admin immediately sees whether caps/ceilings are enforcing or only reporting"). Above the four cards, so a collapsed card cannot hide it.
// The switch itself stays in card 1; this only says what is in force.
function ModeBanner({ d }) {
  const or = d.openrouter || {}, mode = d.mode ?? or.mode ?? null, services = d.services || []
  const ceiling = usd(d.ceiling_usd ?? or.daily_ceiling_usd), spent = money(or.spent_today_usd)
  const would = services.filter(s => s.enabled !== false && wouldHold(s)).length
  const heldByLimit = services.filter(s => ['cap', 'ceiling'].includes(s.held_kind)).length
  const n = v => `${fmtNumber(v)} service${v === 1 ? '' : 's'}`
  const tone = mode === 'stop' ? 'success' : mode === 'observe' ? 'warning' : 'danger'
  return <section className={`aim-state aim-banner tone-${tone}`} role="status" aria-label="AI limits" data-ai-mode-banner={mode || 'unknown'}>
    <span className={`cf-chip tone-${tone}`}>{mode === 'stop' ? 'Limits enforced' : mode === 'observe' ? 'Limits not enforced' : 'Limit mode not recorded'}</span>
    <span className="aim-banner-text">
      {mode === 'stop' ? <><strong>Enforcing (stop at limits).</strong> The daily ceiling ({ceiling ?? 'not set'}) and each service's cap stop scheduled work when reached. Spent today (UTC): {spent}. {heldByLimit ? `${n(heldByLimit)} held by a cap or the ceiling now.` : 'No service is held by a cap or the ceiling now.'}</>
        : mode === 'observe' ? <><strong>Observing only: limits are reported, not enforced.</strong> The daily ceiling ({ceiling ?? 'not set'}) and the service caps stop nothing. Spent today (UTC): {spent}. {would ? `${n(would)} would be held now if limits were enforced.` : 'No service would be held now if limits were enforced.'}</>
        : <><strong>The limit mode is not recorded.</strong> Whether the ceiling and the caps stop work cannot be told from here.</>}
      {' '}In both modes a service still stops when it is switched off, has no allowed or qualified model, or there is no credit or no recent balance reading. The mode is changed in 1 · OpenRouter key and usage.</span>
  </section>
}

// ---- 1 OpenRouter key and usage -----------------------------------------------------------------------------------------------------------
function OpenRouterPane({ d, admin, saveSetting, reload, onError }) {
  const or = d.openrouter || {}, limitMode = d.mode ?? or.mode ?? null, state = accountState({ ...or, mode: limitMode })
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
    const next = limitMode === 'observe' ? 'stop' : 'observe'
    const { error } = await supabase.rpc('admin_toolsets_write', { p_action: 'enforcement', p_args: { toolset: 'openrouter', enforcement: next, reason } })
    if (error) throw error
    setMode(false); setMsg(`Saved. Mode: ${next === 'stop' ? 'Stop at limits' : 'Observe only'}.`); await reload()
  })
  const main = ['credit_floor_usd', 'low_balance_warn_usd', 'budgets.ai_daily_ceiling_usd']
  const settings = or.settings || [], first = main.map(k => settings.find(s => s.key === k)).filter(Boolean), rest = settings.filter(s => !main.includes(s.key))
  const bal = or.balance_usd
  return <Card id={PANES.openrouter} level={2} defaultOpen={desktop()} className="aim-pane" data-ai-pane="openrouter" title="1 · OpenRouter key and usage" subtitle="Every AI model is called through OpenRouter with one key. The credit, the floor and the one daily spend ceiling for all services."
      meta={<><span className={`cf-chip tone-${state.tone}`} data-ai-account-chip={state.key}>{state.label}</span>{d.caps_exceed_ceiling && <span className="cf-chip tone-warning" data-ai-caps-chip>Caps over the ceiling</span>}<span className="aim-quiet">{money(or.spent_today_usd)} of {usd(or.daily_ceiling_usd) ?? 'no ceiling'} today</span></>}
      action={<Button compact onClick={reload} disabled={busy}><RefreshCw size={14}/>Refresh</Button>}>
    <p className={`aim-state tone-${state.tone}`} data-ai-account-state={state.key} role="status"><span className={`cf-chip tone-${state.tone}`}>{state.label}</span><span>{state.text}</span></p>
    {d.caps_exceed_ceiling && <p className="aim-state tone-warning" role="status" data-ai-caps-exceed><span className="cf-chip tone-warning">Caps over the ceiling</span><span>Service caps add up to {money(d.caps_total_usd)} a day, more than the {money(d.ceiling_usd ?? or.daily_ceiling_usd)} ceiling: {limitMode === 'observe' ? 'the ceiling would stop work first if limits were enforced.' : 'the ceiling will stop work first.'}</span></p>}
    <div className="aim-tiles">
      <div className="aim-tile" data-ai-key>
        <small><KeyRound size={12} aria-hidden/> Key</small>
        <strong>{(or.key?.present ?? or.key_present) ? 'Present' : 'Not seen'}</strong>
        <span>{or.key?.secret || or.key_secret_name || 'The key'} · never shown{or.key?.shared_by_profiles ? ` · shared by ${fmtNumber(Number(or.key.shared_by_profiles))} model profiles` : ''}</span>
      </div>
      <div className="aim-tile" data-ai-balance={admin ? 'figure' : 'words'}>
        <small>Credit balance</small>
        <strong>{or.balance_known === false || bal == null ? 'Balance not measured' : admin ? (usd(bal) ?? 'Not read yet') : balanceWords(bal, or.floor_usd)}</strong>
        <span>{admin && or.total_credits_usd != null ? `of ${usd(or.total_credits_usd)} bought · ` : ''}read {or.balance_observed_at ? <span title={fmtDateTime(or.balance_observed_at)} data-ai-balance-age>{fmtRelative(or.balance_observed_at)}</span> : 'never'}</span>
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
    <p className={`aim-state tone-${limitMode === 'stop' ? 'success' : 'warning'}`} data-ai-mode={limitMode || 'unknown'} role="status">
      <span className={`cf-chip tone-${limitMode === 'stop' ? 'success' : 'warning'}`}>{limitMode === 'stop' ? 'Enforcing' : limitMode === 'observe' ? 'Observing' : 'Mode not recorded'}</span>
      <span>{limitMode === 'stop' ? 'Enforcing: the daily ceiling and each service\'s cap stop scheduled work when reached.' : limitMode === 'observe' ? 'Observing: limits are reported, not enforced. The daily ceiling and the caps stop nothing; a service that is over one says "Would be held".' : ''} In both modes these always stop a service, Run now included: switched off, no allowed or qualified model, no credit, and a balance that is not measured or too old.</span>
      {admin && limitMode && !mode && <Button compact disabled={busy} onClick={() => setMode(true)}>{limitMode === 'observe' ? 'Switch to enforcing (stop at limits)' : 'Switch to observing only'}</Button>}</p>
    {mode && <SaveBar what="mode" busy={busy} changes={[`Limits: ${limitMode === 'observe' ? 'Observing (reported, not enforced) becomes Enforcing (stop at limits)' : 'Enforcing (stop at limits) becomes Observing (reported, not enforced)'}`]} onSave={flip} onCancel={() => setMode(false)}/>}
    {admin ? <div className="aim-keyrow" data-ai-key-controls>
      <label className="aim-keyfield"><span>Replace the key (write-only)</span>
        <input className="fv-input" type="password" autoComplete="new-password" aria-label="New OpenRouter key" placeholder="Paste the new key; it replaces the old one" value={key} disabled={busy} onChange={e => { setKey(e.target.value); setKeyMode('') }}/></label>
      {keyMode !== 'save' && <Button compact variant="primary" disabled={busy || key.trim().length < 20 || !profile} onClick={() => setKeyMode('save')}>Replace key</Button>}
      <Button compact disabled={busy || !profile} onClick={verify}>Verify</Button>
      {!profile && <small className="aim-quiet">No model profile holds the key, so it cannot be replaced or verified from here.</small>}
    </div> : <p className="l3v-note" data-ai-key-readonly>The key is {(or.key?.present ?? or.key_present) ? 'present' : 'absent'}. <Needs rank={6} what="Replace or verify the key, change the floor or the daily ceiling"/></p>}
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
function ModelsPane({ d, can, act }) { // can: Platform Admin (the model list is rank 6)
  const groups = modelGroups(d.models || []), sLabel = Object.fromEntries((d.services || []).map(s => [s.service_code, s.label]))
  const [edit, setEdit] = useState(null), [busy, setBusy] = useState(false), [err, setErr] = useState(''), [done, setDone] = useState('')
  const save = async reason => { const m = edit; setBusy(true); setErr(''); setDone('')
    try { const next = m.status === 'allowed' ? 'not_allowed' : 'allowed'; await act('admin_ai_model_set_v1', { p_code: m.code, p_status: next, p_reason: reason }); setDone(`Saved. ${m.label} is now ${next === 'allowed' ? 'allowed' : 'not allowed'}.`); setEdit(null) }
    catch (e) { setErr(say(e)) } finally { setBusy(false) } }
  const allowedN = (d.models || []).filter(m => m.status === 'allowed').length, l3 = d.legacy?.layer3 || null
  // qualification by service, where the services say; the spend each model really had in the last 14 days
  const anyQual = (d.services || []).some(s => qualification(s)), qual = {}
  if (anyQual) for (const m of d.models || []) qual[m.code] = (d.services || []).filter(s => isQualified(s, m.code)).map(s => s.service_code)
  const days = d.usage?.by_day_14d, spend14 = Array.isArray(days) ? days.reduce((o, r) => { if (r.model && r.usd != null) o[r.model] = (o[r.model] || 0) + Number(r.usd); return o }, {}) : null
  return <Card id={PANES.models} level={2} defaultOpen={desktop()} className="aim-pane" data-ai-pane="models" title="2 · Models" subtitle="The one list of models a service may use, by family. A model that is not allowed is skipped in every cascade."
      meta={<><span className="aim-quiet" data-ai-models-count>{fmtNumber(allowedN)} of {fmtNumber((d.models || []).length)} allowed</span>{Number(d.guard) > 0 && <span className="cf-chip tone-warning">{fmtNumber(Number(d.guard))} to check</span>}</>}>
    {!can && <p className="l3v-note">You can view the list. <Needs rank={6} what="Allow or disallow a model"/></p>}
    {done && <p className="aim-done" role="status">{done}</p>}{err && <p className="fr-error" role="alert">{err}</p>}
    {Number(d.guard) > 0 && <p className="aim-state tone-warning" role="status" data-ai-guard={d.guard}><span className="cf-chip tone-warning">{fmtNumber(Number(d.guard))} to check</span><span>{Number(d.guard) === 1 ? 'One place' : `${fmtNumber(Number(d.guard))} places`} outside the services still name{Number(d.guard) === 1 ? 's' : ''} a model that is not allowed. No service uses {Number(d.guard) === 1 ? 'it' : 'them'}; see Layer 3 below.</span></p>}
    {!groups.length ? <Empty text="No models are listed."/> : <div className="cf-table-wrap aim-wrap"><table className="cf-table aim-table aim-models" data-ai-models data-no-resize>
      <thead><tr><th>Model</th><th>OpenRouter id</th><th className="num">Price in / out, per million tokens</th><th className="num">Context</th><th>Used by, qualified for</th><th className="num">Spend, 14 days</th><th>Allowed</th></tr></thead>
      {groups.map(g => <tbody key={g.key} data-ai-family={g.key}>
        <tr className="aim-group"><th colSpan={7} scope="rowgroup">{g.label}{g.key === 'not_allowed' && <small> GPT, Claude and anything outside the seven families</small>}</th></tr>
        {g.models.map(m => { const on = m.status === 'allowed', family = inAllowedFamily(m), price = m.input_usd_per_mtok != null && m.output_usd_per_mtok != null
          return <React.Fragment key={m.code}><tr className={on ? '' : 'aim-off'} data-ai-model={m.code} data-ai-model-status={m.status}>
            <td data-label="Model"><strong>{m.label || m.code}</strong>{m.note && <small className="aim-sub">{m.note}</small>}</td>
            <td data-label="OpenRouter id"><code className="aim-code">{m.model_identifier || 'Not recorded'}</code></td>
            <td data-label="Price in / out per M tokens" className="num" data-ai-price={price ? 'known' : 'not-checked'}>{price ? <><span>{usd(m.input_usd_per_mtok, 2)} / {usd(m.output_usd_per_mtok, 2)}</span>{m.price_checked_at && <small className="aim-sub">checked {fmtDateTime(m.price_checked_at)}</small>}</> : <span className="aim-quiet">not checked</span>}</td>
            <td data-label="Context" className="num">{tokens(m.context_tokens) ? <span>{tokens(m.context_tokens)}</span> : <span className="aim-quiet">not checked</span>}</td>
            <td data-label="Used by">{(m.used_by || []).length ? <span className="aim-usedby">{m.used_by.map(c => <span key={c} className="cf-chip tone-neutral">{sLabel[c] || humanLabel(c)}</span>)}</span> : <span className="aim-quiet">No service</span>}
              {qual[m.code] && <small className="aim-sub" data-ai-qualified-for>{qual[m.code].length ? `Qualified for: ${qual[m.code].map(c => sLabel[c] || c).join(', ')}` : 'Not qualified for any service'}</small>}</td>
            <td data-label="Spend, 14 days" className="num" data-ai-model-spend><span>{spend14 == null ? NOT_MEASURED : m.model_identifier in spend14 ? money(spend14[m.model_identifier]) : 'none recorded'}</span></td>
            <td data-label="Allowed"><span className="aim-allow"><Switch on={on} label={`${on ? 'Disallow' : 'Allow'} ${m.label || m.code}`} disabled={!can || busy || (!on && !family)} onChange={() => { setErr(''); setEdit(m) }}/>
              <span className={on ? '' : 'aim-quiet'}>{on ? 'Allowed' : 'Not allowed'}</span>{on && !family && <span className="cf-chip tone-warning">Outside the families</span>}</span>
              {!on && !family && <small className="aim-sub" data-ai-family-refused>Not in a family the Platform Admin allows; adding a family is a release.</small>}
              {(m.reason || m.changed_at) && <small className="aim-sub">{m.reason}{m.changed_at ? ` · ${fmtDateTime(m.changed_at)}` : ''}</small>}</td>
          </tr>
          {edit?.code === m.code && <tr className="aim-editrow"><td colSpan={7}><SaveBar what={`model-${m.code}`} busy={busy} onSave={save} onCancel={() => setEdit(null)}
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
  const models = d.models || [], mig = migrationOf(s), all = cascadeOf(s, models), items = mig === 'routed_single' ? all.slice(0, 1) : mig === 'not_migrated' ? [] : all, state = serviceState(s), last = lastCall(s), recovery = recoveryOf(s), would = wouldHold(s), quals = qualification(s), noKind = noModelKind(s, models), reasons = state.key === 'running' ? [] : heldReasons(s, models)
  const [draft, setDraft] = useState(null), [busy, setBusy] = useState(false), [err, setErr] = useState(''), [done, setDone] = useState(''), [promptEdit, setPromptEdit] = useState(false), [qualify, setQualify] = useState(null)
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
    else if (draft.cascade.some(c => isQualified(s, c) === false)) blocked = `Not qualified for this service: ${draft.cascade.filter(c => isQualified(s, c) === false).map(c => byCode[c]?.label || c).join(', ')}. Remove it, or record its qualification first.`
    else if (mig === 'routed_single' && draft.cascade.length > 1) blocked = 'Fallback not available for this service yet: keep exactly one model.'
    else if (usdN == null) blocked = 'Give a daily US$ cap: every service has one.'
    else if ((usdN != null && !(usdN >= 0)) || (callsN != null && !(callsN >= 0 && Number.isInteger(callsN)))) blocked = 'A cap is a number that is not negative (calls: a whole number). The calls cap may be left empty for none.'
    payload = { p_service: s.service_code, p_cascade: draft.cascade, p_daily_usd_cap: usdN, p_daily_calls_cap: callsN, p_enabled: draft.enabled }
  }
  const save = async reason => { setBusy(true); setErr(''); setDone('')
    try { const said = changes.join(' '); await act('admin_ai_route_set_v1', { ...payload, p_reason: reason }); setDone(`Saved. ${said}`); setDraft(null) } catch (e) { setErr(say(e)) } finally { setBusy(false) } }
  // allowed models, apart from those the service says are not qualified for it (no qualification data: the server decides)
  const unq = mig === 'not_migrated' ? [] : models.filter(m => m.status === 'allowed' && isQualified(s, m.code) === false)
  const addable = models.filter(m => m.status === 'allowed' && isQualified(s, m.code) !== false && !(draft?.cascade || []).includes(m.code))
  const single = mig === 'routed_single'
  const saveQualify = async reason => { setBusy(true); setErr(''); setDone('')
    try { const m = byCode[qualify.code]; await act('admin_ai_qualification_set_v1', { p_service: s.service_code, p_code: qualify.code, p_evidence: qualify.evidence.trim(), p_reason: reason, p_status: 'qualified' }); setDone(`Saved. ${m?.label || qualify.code} is recorded as qualified for ${s.label}.`); setQualify(null) } catch (e) { setErr(say(e)) } finally { setBusy(false) } }
  const move = (i, by) => { const c = [...draft.cascade], j = i + by; if (j < 0 || j >= c.length) return; [c[i], c[j]] = [c[j], c[i]]; set({ cascade: c }) }
  const spent = s.spent_today || {}
  return <>
    <tr className={`aim-service${open ? ' is-open' : ''}${s.enabled === false ? ' aim-off' : ''}`} data-ai-service={s.service_code} data-ai-service-state={state.key}>
      <td data-label="Service"><button type="button" className="aim-toggle" aria-expanded={open} aria-controls={`aim-d-${s.service_code}`} onClick={() => onToggle(!open)}><ChevronRight size={15} className="aim-chev" aria-hidden/><strong>{s.label || humanLabel(s.service_code)}</strong></button>
        {s.field && <small className="aim-sub aim-indent">Field: {humanLabel(s.field)}</small>}</td>
      <td data-label="Model cascade" data-ai-model-cell data-ai-migration={mig}>{mig === 'not_migrated' ? <span className="aim-cascade">{effect ? <span className="aim-chip is-plain" title={inUse}>{shortModel(effect)}</span> : <NoModel/>}</span> : <Cascade items={items}/>}
        {mig === 'routed_single' && <small className="aim-sub" data-ai-single>Fallback not available for this service yet</small>}
        {mig === 'not_migrated' && <small className="aim-sub">The model in effect. This service does not take its model from here yet.</small>}
        {mig !== 'not_migrated' && items.length > 0 && !(s.models || []).length && <NoModel what={noModelWords(noKind) || 'No allowed model'}/>}
        <small className="aim-sub" data-ai-last>Last used: {last?.model ? <span title={last.model}>{shortModel(models.find(m => m.model_identifier === last.model)?.label || last.model)}</span> : 'not measured'}{last?.at ? `, ${fmtRelative(last.at)}` : ''}{last?.outcome ? ` · ${humanLabel(last.outcome)}` : ''}</small>
        {s.previous_model && s.previous_model !== inUse && <small className="aim-sub aim-was" data-ai-was-on>Was on: <span title={s.previous_model}>{shortModel(models.find(m => m.model_identifier === s.previous_model)?.label || s.previous_model)}</span></small>}
        {(s.skipped || []).length > 0 && mig !== 'not_migrated' && <small className="aim-sub" data-ai-skipped>Not handed out: {s.skipped.map(x => `${shortModel(byCode[x.code]?.label || x.code)} (${x.why})`).join(', ')}</small>}
        {(s.models || []).length > 0 && !inUse && <small className="aim-sub" data-ai-in-effect>In use today: <NoModel/></small>}
        {(s.models || []).length > 0 && inUse && inUse !== firstAllowed && <small className="aim-sub" data-ai-in-effect>In use today: <strong title={inUse}>{shortModel(effect)}</strong></small>}
</td>
      <td data-label="On"><span className="aim-allow"><Switch on={s.enabled !== false} label={`${s.enabled !== false ? 'Switch off' : 'Switch on'} ${s.label}`} disabled={!can || busy || mig === 'not_migrated'} onChange={on => begin({ enabled: on })}/></span></td>
      <td data-label="Daily cap"><span>{s.daily_usd_cap == null ? 'No US$ cap' : usd(s.daily_usd_cap)}</span><small className="aim-sub">{s.daily_calls_cap == null ? 'no call cap' : `${fmtNumber(Number(s.daily_calls_cap))} calls`}</small></td>
      <td data-label="Spent today" data-ai-spent><span>{money(spent.usd)}{s.daily_usd_cap != null ? ` of ${usd(s.daily_usd_cap)}` : ''}</span>
        {s.daily_usd_cap != null && <Meter value={spent.usd} max={s.daily_usd_cap} label={`${s.label}: today's spend against its cap`}/>}
        <small className="aim-sub">{spent.calls == null ? 'calls not measured' : `${fmtNumber(Number(spent.calls))} call${Number(spent.calls) === 1 ? '' : 's'}`}{s.daily_calls_cap != null ? ` of ${fmtNumber(Number(s.daily_calls_cap))}` : ''}</small></td>
      <td data-label="State"><span className={`cf-chip tone-${state.tone}`} title={state.why} data-ai-state-pill>{state.label}</span>{mig === 'not_migrated' && <span className="cf-chip tone-neutral" data-ai-not-migrated>Not migrated</span>}{reasons.length > 0 && <ul className="aim-why" data-ai-held-reasons aria-label={`Why ${s.label} is not running`}>{reasons.map((r, i) => <li key={i}>{r}</li>)}</ul>}
        {state.key === 'running' && last?.outcome === 'failed' && <small className="aim-sub" data-ai-row-failing><span className="cf-chip tone-danger">Last call failed</span> {callErrorWords(last.error) || 'the error was not recorded'}{last.at ? `, ${fmtRelative(last.at)}` : ''}</small>}
        {would && <small className="aim-sub aim-would" data-ai-would-hold={would.kind || 'yes'}><span className="cf-chip tone-warning">Would be held</span> {would.label.replace(/^Held: /, '')}: {would.reason} Limits are observed, not enforced, so it runs.</small>}</td>
    </tr>
    {open && <tr className="aim-detailrow" id={`aim-d-${s.service_code}`} data-ai-service-detail={s.service_code}><td colSpan={6}><div className="aim-detail">
      {done && <p className="aim-done" role="status" data-ai-saved>{done}</p>}{err && <p className="fr-error" role="alert" data-ai-error>{err}</p>}
      <div className="aim-block" data-ai-route>
        <h4>Model cascade, switch and daily cap</h4>
        {!draft ? <><p className="aim-line">{mig === 'not_migrated' ? (effect ? <span className="aim-chip is-plain" title={inUse}>{shortModel(effect)}</span> : <NoModel/>) : <Cascade items={items}/>}</p>
          {mig === 'routed' && <p className="aim-quiet">The first allowed model is the one in use. The worker tries the next one when a call fails technically (an error, a time-out, an unreadable answer), never because of what a model answered. Only models that are allowed and qualified for this service can be added.</p>}
          {mig === 'routed_single' && <p className="aim-note" data-ai-single-note>Fallback not available for this service yet: its worker uses one model, so one model is set here.</p>}
          {mig === 'not_migrated' && <p className="aim-note" data-ai-unwired>Not migrated: this service does not take its model, cap or switch from here yet, so nothing is changed here. The model shown is the one in effect.</p>}
          {s.note && <p className="aim-note">{s.note}</p>}
          {mig === 'not_migrated' ? null : can ? <Button compact onClick={() => begin()} data-ai-edit={s.service_code}>{mig === 'routed_single' ? 'Change model, switch or cap' : 'Change cascade, switch or cap'}</Button> : <p className="l3v-note"><Needs rank={5} what="Change the cascade, switch or cap"/></p>}
          {quals && <p className="aim-line" data-ai-qualified><strong>Qualified for this service:</strong> {[...quals].filter(([, q]) => q.qualified).length ? [...quals].filter(([, q]) => q.qualified).map(([code, q]) => <span key={code} className={`cf-chip tone-${q.provisional ? 'warning' : 'success'}`} data-ai-qualified-model={code} data-ai-provisional={q.provisional ? 'true' : undefined} title={q.evidence || undefined}>{shortModel(byCode[code]?.label || code)}{q.provisional ? ` · Provisional: ${q.evidence || 'evidence not recorded'}` : ''}</span>) : <NoModel what="No qualified model"/>}</p>}
          {unq.length > 0 && <div className="aim-unq" data-ai-unqualified>
            <p className="aim-quiet">Not qualified for this service (allowed, but cannot be added to its cascade):</p>
            <ul>{unq.map(m => <li key={m.code} data-ai-unqualified-model={m.code}><span>{m.label}{quals?.get(m.code)?.status === 'pending' ? ' (qualification pending)' : ''}</span>
              {admin ? (qualify?.code === m.code ? null : <Button compact onClick={() => { setErr(''); setQualify({ code: m.code, evidence: '' }) }} data-ai-qualify={m.code}>Record qualification</Button>) : <Needs rank={6} what="Record qualification"/>}
              {qualify?.code === m.code && <div className="aim-qualify"><label className="aim-add"><span>Evidence (where the test results are: a run, a document, a link)</span>
                <input className="fv-input aim-text" aria-label={`Evidence that ${m.label} is qualified for ${s.label}`} value={qualify.evidence} onChange={e => setQualify({ ...qualify, evidence: e.target.value })}/></label>
                <SaveBar what={`qualify-${s.service_code}-${m.code}`} label="Record qualification" busy={busy} blocked={qualify.evidence.trim().length < 10 ? 'Say what the qualification rests on (the evidence), in at least 10 characters.' : ''} changes={[`${m.label} is recorded as qualified for ${s.label}. It can then be added to the cascade; this adds it to nothing.`]} onSave={saveQualify} onCancel={() => setQualify(null)}/></div>}</li>)}</ul></div>}</>
        : <div className="aim-editor" data-ai-editor={s.service_code}>
          <ol className="aim-steps">{draft.cascade.map((c, i) => { const m = byCode[c], ok = m?.status === 'allowed'
            return <li key={c} className={ok ? '' : 'is-out'} data-ai-step={c}><span><b>{i + 1}</b> {m?.label || c}{!ok && <em> not allowed</em>}</span>
              <span className="aim-step-acts"><button type="button" className="aim-icon" aria-label={`Move ${m?.label || c} up`} hidden={single} disabled={i === 0} onClick={() => move(i, -1)}><ArrowUp size={14}/></button>
                <button type="button" className="aim-icon" aria-label={`Move ${m?.label || c} down`} hidden={single} disabled={i === draft.cascade.length - 1} onClick={() => move(i, 1)}><ArrowDown size={14}/></button>
                <button type="button" className="aim-icon" aria-label={`Remove ${m?.label || c}`} onClick={() => set({ cascade: draft.cascade.filter(x => x !== c) })}><X size={14}/></button></span></li> })}
            {!draft.cascade.length && <li className="aim-empty-step"><NoModel/> Add at least one allowed model.</li>}</ol>
          <label className="aim-add"><span><Plus size={13} aria-hidden/> {single ? 'Use another model (one model: fallback not available for this service yet)' : 'Add a model'}</span>
            <select className="fv-input" aria-label={single ? `Model of ${s.label}` : `Add a model to ${s.label}`} value="" disabled={!addable.length} onChange={e => { if (e.target.value) set({ cascade: single ? [e.target.value] : [...draft.cascade, e.target.value] }) }}>
              <option value="">{addable.length ? 'Choose an allowed, qualified model' : 'No other allowed, qualified model'}</option>
              {addable.map(m => <option key={m.code} value={m.code}>{m.label}{m.input_usd_per_mtok != null ? ` · ${usd(m.input_usd_per_mtok)} / ${usd(m.output_usd_per_mtok)}` : ' · price not checked'}</option>)}
              {unq.filter(m => !draft.cascade.includes(m.code)).map(m => <option key={m.code} value="" disabled>{m.label} · Not qualified for this service</option>)}</select></label>
          <div className="aim-caps">
            <label><span>Daily cap, US$</span><input className="fv-input aim-num" inputMode="decimal" aria-label={`Daily cap in US dollars for ${s.label}`} placeholder="required" value={draft.usd} onChange={e => set({ usd: e.target.value })}/></label>
            <label><span>Daily cap, calls</span><input className="fv-input aim-num" inputMode="numeric" aria-label={`Daily cap in calls for ${s.label}`} placeholder="no cap" value={draft.calls} onChange={e => set({ calls: e.target.value })}/></label>
            <label className="aim-onoff"><span>Service</span><span className="aim-allow"><Switch on={draft.enabled} label={`${s.label} on or off`} onChange={on => set({ enabled: on })}/>{draft.enabled ? 'On' : 'Off'}</span></label>
          </div>
          {changes.length || blocked ? <SaveBar what={`route-${s.service_code}`} busy={busy} changes={changes.length ? changes : ['Nothing changed yet.']} blocked={blocked || (changes.length ? '' : ' ')} onSave={save} onCancel={() => setDraft(null)}/>
            : <p className="aim-save-row"><span className="aim-quiet">Nothing changed yet.</span><Button compact onClick={() => setDraft(null)}>Cancel</Button></p>}
        </div>}
      </div>
      <div className="aim-block" data-ai-last-call={s.service_code}>
        <h4>Most recent call</h4>
        {last ? <p className="aim-line"><strong>Model used:</strong> {last.model ? <code className="aim-code">{last.model}</code> : NOT_MEASURED} <strong>When:</strong> {last.at ? fmtDateTime(last.at) : NOT_MEASURED} <strong>Outcome:</strong> {last.outcome ? humanLabel(last.outcome) : NOT_MEASURED}</p>
          : <p className="aim-quiet">{NOT_MEASURED}: no call of this service is recorded here.</p>}
        {last?.error && <p className="fr-error" data-ai-last-error>Last error: {callErrorWords(last.error)}{last.attempt_no > 1 ? ` (attempt ${last.attempt_no})` : ''}</p>}
        <p className="aim-line" data-ai-recovery={recovery || 'not-measured'}><strong>Recovery:</strong> {recoveryWords(recovery) || NOT_MEASURED}</p>
      </div>
      <div className="aim-block" data-ai-prompt={s.service_code}>
        <h4>Prompt</h4>
        <p className="aim-line"><strong>Source:</strong> <span title={prompt.source || undefined}>{promptSource(prompt.source)}</span> <strong>Version:</strong> {prompt.version || 'Not recorded'}{prompt.sha256 && <> <strong>sha256:</strong> <code className="aim-code" data-ai-prompt-sha>{prompt.sha256}</code></>}</p>
        {prompt.text ? <pre className="aim-prompt" tabIndex={0} data-ai-prompt-text="database" aria-label={`Prompt of ${s.label} (read only, complete)`}>{prompt.text}</pre>
          : <WorkerPrompts service={s.service_code} label={s.label} textRef={prompt.text_ref} inWorker={inWorker || Boolean(prompt.version)}/>}
        {prompt.source === 'pipeline.provider_description_prompts' && admin && (promptEdit
          ? <React.Suspense fallback={<Loading compact label="Reading the prompt…"/>}><PromptEditor onError={onError}/></React.Suspense>
          : <Button compact onClick={() => setPromptEdit(true)}>Edit this prompt as a new version</Button>)}
        {s.config && <div className="aim-note" data-ai-config-summary><strong>AI admission:</strong> {s.config.ai_admission ? 'On' : 'Off'}. <strong>Instruction versions:</strong> {(s.config.prompts || []).length ? s.config.prompts.map(p => `${p.version}${p.current ? ' (current)' : ''}`).join(', ') : 'none recorded'}.
          {(s.config.prompts || []).filter(p => !p.current && p.text).map(p => <details key={p.version} className="aim-more"><summary>Version {p.version}{p.sha256 ? ` · sha256 ${String(p.sha256).slice(0, 12)}…` : ''}</summary><pre className="aim-prompt">{p.text}</pre></details>)}</div>}
        {(s.service_code === 'scholarship_extraction' || s.config?.write === 'public.admin_scholarship_ai') && <div className="aim-sxconfig" data-ai-scholarship-config>
          <React.Suspense fallback={<Loading compact label="Reading the scholarship extraction configuration…"/>}><ScholarshipConfig part="config" onError={onError}/></React.Suspense></div>}
      </div>
      <div className="aim-block" data-ai-service-settings={s.service_code}>
        <h4>Other AI settings of this service</h4>
        {(s.settings || []).length ? s.settings.map(x => <AiSetting key={`${x.toolset}.${x.key}`} s={x} can={admin} onSave={saveSetting}/>) : <p className="aim-quiet">This service has no other AI settings.</p>}
        {(s.settings || []).length > 0 && !admin && <p className="l3v-note"><Needs rank={6} what="Change a setting"/></p>}
      </div>
      <p className="aim-meta">Spend counted from: {humanLabel(s.lane) || 'not recorded'}. Last change: {s.reason || 'none recorded'}{s.changed_by ? ` · ${s.changed_by}` : ''}{s.changed_at ? ` · ${fmtDateTime(s.changed_at)}` : ''}</p>
    </div></td></tr>}
  </>
}
const PromptEditor = React.lazy(() => import('./ProviderDescriptionPrompt'))
// A prompt written in the worker: its complete text comes from docs/platform/ai-prompts.json, generated from the worker source and checked in
// (scripts/ai-prompts-export.mjs; a test fails when it is stale). Read at build time, loaded when a service is opened. Read only.
let promptFile = null
function WorkerPrompts({ service, label, textRef, inWorker }) {
  const [f, setF] = useState(promptFile), [failed, setFailed] = useState(false)
  useEffect(() => { if (f) return; import('../docs/platform/ai-prompts.json').then(m => { promptFile = m.default || m; setF(promptFile) }).catch(() => setFailed(true)) }, [])
  const key = String(textRef || '').split('#')[1] || service, entry = f?.services?.[key]
  if (!f && !failed) return <Loading compact label="Reading the prompt…"/>
  if (!entry || !(entry.prompts || []).length) return <p className="aim-note" data-ai-prompt-kept>{inWorker ? 'The prompt text is kept in the worker and is not in this build\'s prompt file. It changes with a worker release, as a new version.' : 'The prompt text is not held here.'}</p>
  return <div className="aim-wprompts" data-ai-prompt-text="worker">
    <p className="aim-quiet" data-ai-prompt-kept>Kept in the worker ({f.worker}); complete text, read only. It changes with a worker release, as a new version. <span>sha256 of this service's prompts: <code className="aim-code">{entry.sha256}</code></span></p>
    {entry.prompts.map(p => <details key={p.name} className="aim-more" open={entry.prompts.length === 1} data-ai-worker-prompt={p.name}>
      <summary>{humanLabel(p.name)} · version {p.version}</summary>
      <p className="aim-quiet">{p.where} · sha256 <code className="aim-code">{p.sha256}</code>{p.complete === false ? ' · goes on with the data of the request (shown as <data of the request>)' : ''}{p.note ? ` · ${p.note}` : ''}</p>
      <pre className="aim-prompt" tabIndex={0} aria-label={`Prompt ${p.name} of ${label} (read only, complete)`}>{p.text}</pre></details>)}
  </div>
}
// Platform Admin 13 Nov 2026 22:10: "Scholarship Extraction configuration belongs in Models & Services": AI admission and its settings,
// qualification on the sample, instructions and a test page, drawn once, here (its results stay on Scholarships › Coverage)
const ScholarshipConfig = React.lazy(() => import('./ScholarshipExtraction'))

function ServicesPane({ d, can, admin, act, saveSetting, focus, onError }) {
  const groups = serviceGroups(d.services || [])
  const [open, setOpen] = useState(() => (focus ? { [focus]: true } : {}))
  useEffect(() => { if (focus) setOpen(o => ({ ...o, [focus]: true })) }, [focus])
  // a service that is switched on and gets no model: the alarm. One that is switched off is Off on purpose, and its row says why (live 14 Nov 2026:
  // the five services seeded off were listed here as having "no allowed model", although the reason was that none is qualified yet)
  const models = d.models || [], noModel = (d.services || []).filter(s => s.enabled !== false && !(s.models || []).length)
  const held = (d.services || []).filter(s => ['cap', 'ceiling', 'credit_floor', 'held'].includes(serviceState(s).key)).length
  return <Card id={PANES.services} level={2} defaultOpen={desktop()} className="aim-pane" data-ai-pane="services" title="3 · Services" subtitle="What the platform uses AI for, one row each: its model cascade, switch, daily cap and today's spend. Open a row for its prompt and its other AI settings."
      meta={<><span className="aim-quiet">{fmtNumber((d.services || []).length)} services</span>{noModel.length > 0 && <span className="cf-chip tone-danger" data-ai-no-model-chip>{fmtNumber(noModel.length)} with no model</span>}{held > 0 && <span className="cf-chip tone-warning">{fmtNumber(held)} held</span>}</>}>
    {noModel.length > 0 && <p className="aim-state tone-danger" role="alert" data-ai-no-model-warning><span className="cf-chip tone-danger">No model</span><span>{noModel.map(s => `${s.label} (${(noModelWords(noModelKind(s, models)) || 'No allowed model').toLowerCase()})`).join(', ')}: switched on, but {noModel.length === 1 ? 'it does' : 'they do'} not run until {noModel.length === 1 ? 'its' : 'each'} cascade has an allowed model that is qualified for {noModel.length === 1 ? 'it' : 'the service'}.</span></p>}
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
  const rows = unit === 'hour' ? d.usage?.by_hour_24h : d.usage?.by_day_14d, per = d.usage?.by_model_24h, fails = useMemo(() => failureSummary(per, d.usage?.fallbacks_24h), [per, d])
  const sLabel = Object.fromEntries((d.services || []).map(s => [s.service_code, s.label])), mLabel = Object.fromEntries((d.models || []).map(m => [m.model_identifier, m.label]))
  const groups = useMemo(() => usageBy(rows, by, d), [rows, by, d]), buckets = useMemo(() => usageBuckets(rows, unit), [rows, unit])
  const top = Math.max(0, ...(groups || []).map(g => Number(g.usd || 0))), peak = Math.max(0, ...(buckets || []).map(b => Number(b.usd || 0)))
  const total = groups && groups.some(g => g.usd != null) ? groups.reduce((n, g) => n + Number(g.usd || 0), 0) : null
  const calls = groups && groups.some(g => g.calls != null) ? groups.reduce((n, g) => n + Number(g.calls || 0), 0) : null
  const when = b => (unit === 'hour' ? new Date(b.t).toISOString().slice(11, 16) : new Date(b.t).toISOString().slice(5, 10).split('-').reverse().join('/'))
  const pick = (cur, set, items, label) => <div className="pg-views" role="toolbar" aria-label={label}>{items.map(([k, l]) => <button key={k} type="button" className={`pg-view${cur === k ? ' is-on' : ''}`} aria-pressed={cur === k} onClick={() => set(k)} data-ai-usage-pick={k}>{l}</button>)}</div>
  return <Card id={PANES.usage} level={2} defaultOpen={desktop()} className="aim-pane" data-ai-pane="usage" title="4 · Recent usage" subtitle="Costs, calls, tokens, failures and fallbacks by service and by model. Times and days are UTC, the same day the caps and the ceiling count."
      meta={<><span className="aim-quiet">{money(d.openrouter?.spent_today_usd)} today</span>{fails && fails.failures > 0 && <span className="cf-chip tone-danger" data-ai-failures-chip>{fmtNumber(fails.failures)} failed call{fails.failures === 1 ? '' : 's'}, 24 h</span>}</>}>
    <div className="aim-usage-picks">{pick(unit, setUnit, [['hour', 'Last 24 hours, by hour'], ['day', 'Last 14 days, by day']], 'Period')}{pick(by, setBy, [['service', 'By service'], ['model', 'By model']], 'Group by')}</div>
    {!groups ? <p className="aim-note" data-ai-usage-none>{NOT_MEASURED}: no usage figures were returned for this period.</p> : <>
      <p className="aim-line" data-ai-usage-total><strong>{money(total)}</strong> spent · <strong>{count(calls)}</strong> calls {unit === 'hour' ? 'in the last 24 hours' : 'in the last 14 days'}</p>
      <ol className="aim-strip" data-ai-usage-strip={unit} aria-label={unit === 'hour' ? 'Spend in each of the last 24 hours' : 'Spend on each of the last 14 days'}>
        {buckets.map(b => <li key={b.t} title={`${when(b)}: ${b.recorded ? `${money(b.usd)}, ${count(b.calls)} calls` : 'nothing recorded'}`}>
          <span className="aim-bar" aria-hidden><span style={{ height: `${b.usd != null && peak > 0 ? Math.max(4, Math.round(100 * b.usd / peak)) : 0}%` }}/></span>
          <span className="aim-strip-label">{when(b)}</span><span className="aim-hide">{b.recorded ? `${money(b.usd)}, ${count(b.calls)} calls` : 'nothing recorded'}</span></li>)}
      </ol>
      {!groups.length ? <p className="aim-note" data-ai-usage-empty>Nothing was recorded in this period.</p> : <div className="cf-table-wrap aim-wrap"><table className="cf-table aim-table" data-no-resize data-ai-usage={`${unit}-${by}`}>
        <thead><tr><th>{by === 'service' ? 'Service' : 'Model'}</th><th className="num">Calls</th><th className="num">Tokens</th><th className="num">Failures</th><th className="num">Fallbacks</th><th className="num">Spend</th><th>Share of the largest</th></tr></thead>
        <tbody>{groups.map(g => <tr key={g.key} data-ai-usage-row={g.key}>
          <td data-label={by === 'service' ? 'Service' : 'Model'}><strong>{g.label}</strong>{g.sub && <small className="aim-sub"><code className="aim-code">{g.sub}</code></small>}{by === 'model' && g.key === '(none)' && <small className="aim-sub">Spend recorded before models were recorded per call.</small>}{g.evidence && <small className="aim-sub"><a className="cf-link" href={g.evidence} data-ai-usage-evidence>Evidence</a></small>}</td>
          <td data-label="Calls" className="num"><span>{count(g.calls)}</span></td>
          <td data-label="Tokens" className="num"><span>{count(g.tokens)}</span></td>
          <td data-label="Failures" className="num"><span>{count(g.failures)}</span></td>
          <td data-label="Fallbacks" className="num"><span>{count(g.fallbacks)}</span></td>
          <td data-label="Spend" className="num"><span>{money(g.usd)}</span></td>
          <td data-label="Share"><span className="aim-hbar" aria-hidden><span style={{ width: `${g.usd != null && top > 0 ? Math.max(2, Math.round(100 * g.usd / top)) : 0}%` }}/></span></td>
        </tr>)}</tbody>
      </table></div>}
      {unit !== 'calls' && <p className="aim-quiet">Spend and calls here come from the spend ledger, which does not record tokens, failures or fallbacks; those are in the per-call record below.</p>}
    </>}
    <div className="aim-block" data-ai-calls-24h>
      <h4>Calls in the last 24 hours, from the per-call record</h4>
      {fails && fails.attempts > 0 && <p className={`aim-state tone-${fails.failures ? 'danger' : 'success'}`} role="status" data-ai-failures-summary={fails.failures}>
        <span className={`cf-chip tone-${fails.failures ? 'danger' : 'success'}`}>{fails.failures ? `${fmtNumber(fails.failures)} failed` : 'No failures'}</span>
        <span>{fails.failures ? `${fmtNumber(fails.failures)} of ${fmtNumber(fails.attempts)} attempts failed (${Math.round(100 * fails.failures / fails.attempts)}%)` : `All ${fmtNumber(fails.attempts)} attempts answered`}{fails.fallbacks ? `; ${fmtNumber(fails.fallbacks)} answered on a later model of the cascade` : ''}.
          {fails.kinds.length > 0 && <> By kind, of the {fmtNumber(fails.listed)} most recent failed attempts: {fails.kinds.map(([k, v]) => `${callErrorWords(k === 'not_recorded' ? null : k) || 'not recorded'} ${fmtNumber(v)}`).join(', ')}.</>} What failed attempts cost is included in Spend.</span></p>}
      {!Array.isArray(per) ? <p className="aim-note">{NOT_MEASURED}: no per-call record was returned.</p>
        : !per.length ? <p className="aim-note" data-ai-calls-empty>No call is on record yet. Rows appear once the worker that records each call is deployed.</p>
        : <div className="cf-table-wrap aim-wrap"><table className="cf-table aim-table" data-no-resize data-ai-calls>
          <thead><tr><th>Service</th><th>Model</th><th className="num">Attempts</th><th className="num">Answered</th><th className="num">Failures</th><th className="num">Fallbacks</th><th className="num">Tokens in / out</th><th className="num">Spend</th></tr></thead>
          <tbody>{per.map((r, i) => <tr key={i} data-ai-calls-row={`${r.service_code}:${r.model || ''}`}>
            <td data-label="Service"><strong>{sLabel[r.service_code] || r.service_code || 'Service not recorded'}</strong>{r.evidence_href && <small className="aim-sub"><a className="cf-link" href={r.evidence_href} data-ai-usage-evidence>Evidence</a></small>}</td>
            <td data-label="Model"><span>{r.model ? (mLabel[r.model] || r.model) : 'Model not recorded'}</span></td>
            <td data-label="Attempts" className="num"><span>{count(r.attempts)}</span></td>
            <td data-label="Answered" className="num"><span>{count(r.answered)}</span></td>
            <td data-label="Failures" className="num" data-ai-calls-failures={Number(r.failures) > 0 ? 'some' : 'none'}>{Number(r.failures) > 0 ? <span className="cf-chip tone-danger">{count(r.failures)}</span> : <span>{count(r.failures)}</span>}</td>
            <td data-label="Fallbacks" className="num"><span>{count(r.fallbacks)}</span></td>
            <td data-label="Tokens in / out" className="num"><span>{r.tokens_in == null && r.tokens_out == null ? NOT_MEASURED : `${count(r.tokens_in)} / ${count(r.tokens_out)}`}</span></td>
            <td data-label="Spend" className="num"><span>{money(r.usd)}</span></td>
          </tr>)}</tbody></table></div>}
      {Array.isArray(d.usage?.fallbacks_24h) && d.usage.fallbacks_24h.length > 0 && <details className="aim-more" data-ai-fallbacks open><summary>Failed attempts in the last 24 hours ({fmtNumber(d.usage.fallbacks_24h.length)})</summary>
        <ul className="aim-events">{d.usage.fallbacks_24h.map((e, i) => <li key={i}><small>{fmtDateTime(e.at)}</small> <strong>{sLabel[e.service_code] || e.service_code}</strong> {mLabel[e.model] || e.model || 'model not recorded'} · attempt {e.attempt_no ?? 'not recorded'} · {callErrorWords(e.failure_kind) || 'kind not recorded'}</li>)}</ul></details>}
    </div>
  </Card>
}

// ---- the page -----------------------------------------------------------------------------------------------------------------------------
export default function AiModelsServices({ onError, focusService = '' }) {
  const viewerRank = useViewerRank()
  const [d, setD] = useState(null), [failed, setFailed] = useState('')
  const load = async () => { setFailed(''); try { const { data, error } = await supabase.rpc('admin_ai_overview_v1'); if (error) throw error; if (!data || Array.isArray(data) || !data.openrouter) throw new Error('The AI overview is not available yet.'); setD(data) } catch (e) { setFailed(say(e)) } }
  useEffect(() => { load() }, [])
  if (focusService) rememberOpen(PANES.services) // a link to one service opens the Services card
  // Both writes answer with the whole overview, so the page shows exactly what was saved
  const act = async (fn, args) => { const { data, error } = await supabase.rpc(fn, args); if (error) throw error; if (data && data.openrouter) setD(data); else await load() }
  const saveSetting = async (s, value, reason) => { const { error } = await supabase.rpc('admin_toolsets_write', { p_action: 'setting', p_args: { toolset: s.toolset, key: s.key, value, reason } }); if (error) throw error; await load() }
  if (failed && !d) return <section className="m-panel" data-ai-page="failed"><Empty text={`Models and services could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if (!d) return <section className="m-panel" data-ai-page="loading"><Loading label="Loading models and services…"/></section>
  // the overview says who may do what (rank, can_control from 5, can_admin at 6); the signed-in rank is the fallback
  const rank = Number(d.rank ?? viewerRank), admin = d.can_admin ?? rank >= PLATFORM_ADMIN_RANK
  const can = Boolean(d.can_control) && rank >= 5 // routes, caps and switches: PIM Admin; the model list, qualification, ceiling and key: Platform Admin
  return <div className="m-page-stack aim" data-ai-page="ready">
    <ModeBanner d={d}/>
    <OpenRouterPane d={d} admin={admin} saveSetting={saveSetting} reload={load} onError={onError}/>
    <ModelsPane d={d} can={admin} act={act}/>
    <ServicesPane d={d} can={can} admin={admin} act={act} saveSetting={saveSetting} focus={focusService} onError={onError}/>
    <UsagePane d={d}/>
  </div>
}
