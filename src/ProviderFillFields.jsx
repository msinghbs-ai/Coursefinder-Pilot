// CF-247 provider description on demand (Platform Admin directives 9-10 Nov 2026, and 10 Nov 19:47: ONE primary outcome action, "Extract / refresh description now"), inside the existing Provider Catalogue and Provider Detail screens.
// It is a small panel over the existing Provider description Run & Validate service (public.admin_provider_description_run_v1): the same preview, the same fixed cohort (prepare), the same Run Now (run), the same saved/verify.
// One click performs preview -> fixed cohort -> run for the providers that can be read, choosing "fill a missing description" or "upgrade a basic registry description" from each provider's own status. It keeps the one required
// audit reason the server asks for (never made up here) and bypasses no check. The preview-only, mode choice and publication read-back are kept under Details. Everything shown is read from the server, so closing the browser
// loses nothing: opening the panel again reads each provider's stages and the task that last included it. It adds no second pipeline and no dashboard.
import React, { useEffect, useRef, useState } from 'react'
import { Button, Empty, Loading, StatusChip, humanLabel } from './ui-kit'
import { Overlay } from './Overlay'
import { fmtDateTime, fmtNumber } from './lib/format.js'
import { plainError } from './lib/errors'
import { providerDescriptionRunApi } from './provider-description-run-api'
import { providerDescriptionFillApi } from './provider-description-run-api' // CF-247 F-PDESC (11 Nov 2026): Fill description
import { fieldWords, qualityOf } from './catalogue-columns.js'
import { DISPATCH, SELECTION, classify, fieldOutcome, fillModeOf, isPermission, nextAction, selectionWords, stagesOf } from './provider-fill-stages.js'
import './provider-fill-fields.css'

const list = v => (Array.isArray(v) ? v : [])
const stamp = v => (v ? fmtDateTime(v) : 'Not recorded')
export const FILL_MODES = [
  { id: 'missing', label: 'Fill missing description', help: 'Reads the provider\'s official About page and proposes a description. A person decides in Layer 4 where the rules say so.' },
  { id: 'upgrade_basic', label: 'Refresh a basic registry description', help: 'For a provider whose description was written from register facts only. The same reader is asked for a fuller, evidenced description. This is a Platform Admin policy switch: while it is off, or if the rules do not allow it, the exact reason is shown and nothing is queued.' },
  { id: 'preview_only', label: 'Preview only', help: 'Shows what the reader would use and why each provider is or is not eligible. A preview records a short-lived preview that expires, but it changes no description and queues no read.' },
  { id: 'verify_publication', label: 'Verify publication', help: 'Reads the catalogue, the Website and Zoho as they are now and says whether each holds the description. Nothing is changed.' },
]
const TASK_DONE = new Set(['done', 'failed', 'cancelled', 'succeeded'])
const TONE = { missing: 'warning', queued: 'info', processing: 'info', waiting_decision: 'violet', held: 'warning', basic_registry: 'neutral', unrecorded: 'warning', enriched_admitted: 'success', consumer_pending: 'info', verified_published: 'success' }
const STAGE_TONE = { done: 'success', pending: 'info', blocked: 'warning', none: 'neutral' }
const STAGE_WORD = { done: 'Done', pending: 'In progress', blocked: 'Stopped', none: 'Not yet' }
const PUBLICATION = { verified: ['Matched', 'success'], pending: ['Pending', 'info'], not_applicable: ['Not applicable', 'neutral'], mismatch: ['Differs', 'warning'], not_served: ['Not served (not applicable)', 'neutral'], error: ['Could not be read', 'danger'], awaiting_description: ['No description yet', 'neutral'] }
const FEED_WORDS = { verified: 'matched', pending: 'pending', not_applicable: 'not applicable' }
const OUTCOME_TONE = { started: 'success', parked: 'info', permission: 'danger', allowlist: 'warning', paused: 'warning', cap: 'warning', policy: 'warning', source: 'warning', up_to_date: 'success', in_progress: 'info', none: 'neutral', error: 'danger', person: 'warning', wait: 'info', locked: 'neutral' }
const OUTCOME_TITLE = {
  started: 'Started: the governed reader has the task', parked: 'Saved: the task is kept and the scheduled reader will take it', permission: 'Permission denied', allowlist: 'Run Now is not switched on for this reader', paused: 'The reader is paused',
  cap: 'A spending limit is reached', policy: 'Policy or a reviewer is required', source: 'Official source unavailable', up_to_date: 'Already up to date', in_progress: 'Already in progress', none: 'No eligible work', error: 'The request failed', person: 'A person must decide in Layer 4', wait: 'The reader is waiting before trying again', locked: 'Locked by a person',
}
const REASON_FALLBACK = { in_progress: 'in_progress', wait: 'wait', source: 'source', policy: 'policy', up_to_date: 'up_to_date', locked: 'locked', none: 'none' }

export default function ProviderFillFields({ providerIds = [], rank = 0, onClose, onChanged, client = providerDescriptionRunApi, fillClient = providerDescriptionFillApi, open = true }) {
  const ids = [...new Set(providerIds)].filter(Boolean)
  const [caps, setCaps] = useState(null), [status, setStatus] = useState(null), [mode, setMode] = useState(''), [preview, setPreview] = useState(null)
  const [saved, setSaved] = useState(null), [reason, setReason] = useState(''), [busy, setBusy] = useState('load'), [error, setError] = useState(''), [note, setNote] = useState('')
  const [pub, setPub] = useState(null), [unknown, setUnknown] = useState(false), [outcome, setOutcome] = useState(null), alive = useRef(true), inflight = useRef(false), key = ids.join(',')
  const [promptOn, setPromptOn] = useState(false) // F-PDESC: the prompt from Settings is in use (the server says so); then the primary action is Fill description
  const fail = e => setError(plainError(e))
  const call = (action, args = {}) => client.call(action, args)
  const canPreview = Number(rank) >= 3
  const canRun = caps?.can_run === true && Number(rank) >= Number(caps?.control_rank ?? 6)
  const cap = Number(caps?.max_size ?? 0)
  const tooMany = caps && ids.length > cap
  const minReason = Number(caps?.reason_min_chars ?? 5)

  // The status read: feeds = true on the first read (the level of an enriched provider depends on the Website and Zoho feeds); the repeat reads skip the feed scan.
  async function readStatus(feeds = false) {
    const s = await call('provider_status', { provider_ids: ids, feeds })
    if (!alive.current) return null
    // a read without the feeds cannot say whether the Website and Zoho hold the text, so the earlier answer for those facts is kept
    setStatus(prev => {
      const before = Object.fromEntries(list(prev?.providers).map(q => [q.provider_id, q]))
      return feeds ? s : { ...s, providers: list(s.providers).map(p => { const o = before[p.provider_id]; return o ? { ...p, website_publication: p.website_publication ?? o.website_publication, zoho_publication: p.zoho_publication ?? o.zoho_publication, quality_class: p.quality_class ?? o.quality_class } : p }) }
    })
    return s
  }
  useEffect(() => {
    alive.current = true
    if (!open || !ids.length) return undefined
    ;(async () => {
      setBusy('load'); setError(''); setNote(''); setPreview(null); setSaved(null); setPub(null); setUnknown(false); setOutcome(null)
      try {
        // the caps first: one status read and one task name the same number of providers at most (the cohort cap), so a longer selection is explained and not read
        const c = await call('fill_caps')
        if (!alive.current) return
        setCaps(c)
        fillClient.promptOn().then(on => { if (alive.current) setPromptOn(on === true) }).catch(() => { if (alive.current) setPromptOn(false) }) // F-PDESC: the server says whether the prompt is in use
        if (ids.length > Number(c.max_size || 0)) { setStatus(null); return }
        const s = await call('provider_status', { provider_ids: ids, feeds: true })
        if (!alive.current) return
        setStatus(s)
        const providers = list(s.providers)
        setMode(m => m || (providers.length && providers.every(p => p.quality_class === 'basic_registry') ? 'upgrade_basic' : 'missing'))
        // a task this person already saved for these providers is picked up again, so the panel shows its live status after a reload
        const mine = providers.map(p => p.latest_task).filter(t => t?.requested_by_me && t.cohort_id).sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0]
        if (mine) { try { const r = await call('saved', { cohort_id: mine.cohort_id }); if (alive.current && r?.cohort_id) setSaved(r) } catch { /* the status rows still show the task */ } }
      } catch (e) { if (alive.current) fail(e) } finally { if (alive.current) setBusy('') }
    })()
    return () => { alive.current = false }
  }, [key, open])

  // While a task has not finished, the status is read again after the governed number of seconds. Closing the panel stops the reading, never the task.
  const working = list(status?.providers).some(p => ['queued', 'reading'].includes(p.reader?.state)) || (saved?.cohort_id && saved.state === 'started' && !list(saved.runs).some(r => TASK_DONE.has(r.state)))
  useEffect(() => {
    if (!open || !caps || !working || !(Number(caps.poll_seconds) > 0)) return undefined
    const t = setInterval(() => { readStatus(false).catch(() => {}); if (saved?.cohort_id) call('saved', { cohort_id: saved.cohort_id }).then(r => alive.current && r?.cohort_id && setSaved(r)).catch(() => {}) }, Number(caps.poll_seconds) * 1000) // the server says how often (a quarter of the reader's own window); a task is never read faster than that
    return () => clearInterval(t)
  }, [open, caps, working, saved?.cohort_id, key])

  const operate = async (name, fn) => { setBusy(name); setError(''); setNote(''); try { await fn() } catch (e) { fail(e) } finally { if (alive.current) setBusy('') } }

  // ---- the one primary action: Extract / refresh description now ----------------------------------------------------------------------------------------
  // The status is read again first (the server's state, not the screen's), each provider is sorted by what the server says it is, and only the providers that can be read are previewed, fixed into a cohort and run.
  // A duplicate click does nothing: the button is off while a request is in flight, a provider whose reading is already queued, in progress or waiting is never queued again, and `run` on a started cohort returns that cohort.
  const providers = list(status?.providers)
  const classes = providers.map(p => ({ p, cls: classify(p) }))
  const readable = classes.filter(c => c.cls === 'extractable')
  const resumable = saved?.cohort_id && saved.state === 'prepared' && !list(saved.runs).length
  // ---- F-PDESC (Platform Admin 11 Nov 2026 14:57): Fill description, one click, no reason to type. Each provider is queued on demand and a read starts at once:
  // not held by the lane AI and Firecrawl limits; a description written by hand, one already written by AI, one in progress or one waiting for a person is skipped.
  const fillable = classes.filter(c => !['locked', 'up_to_date', 'in_progress', 'person'].includes(c.cls))
  const FILL_WORD = { queued: 'queued: the read starts now', manual: 'written by hand, never replaced', has_description: 'already has a description', in_progress: 'already being read', not_live: 'not active and published', identity: 'its official page does not prove its name yet', not_found: 'not found' }
  const doFill = async () => {
    if (inflight.current) return
    inflight.current = true
    try {
      await operate('fill', async () => {
        setOutcome(null)
        const data = await fillClient.fill(fillable.map(c => c.p.provider_id))
        const rows = list(data?.providers)
        if (alive.current) setOutcome({ category: Number(data?.queued) > 0 ? 'started' : 'none', lines: rows.map(r => `${r.name || r.provider_id}: ${FILL_WORD[r.outcome] || humanLabel(r.outcome)}`) })
        await readStatus(false)
        onChanged?.()
      })
    } finally { inflight.current = false }
  }
  const doExtract = async () => {
    if (inflight.current) return
    inflight.current = true
    try {
      await operate('extract', async () => {
        setOutcome(null); setPreview(null); setPub(null)
        let result
        try { result = await extractNow() } catch (e) {
          if (isPermission(e)) { result = { category: 'permission', lines: ['Your role is not allowed to start this task. Nothing was queued.'] } } else throw e
        }
        if (alive.current) setOutcome(result)
      })
    } finally { inflight.current = false }
  }
  async function extractNow() {
    const fresh = await readStatus(true)
    if (!fresh || !alive.current) return null
    const now = list(fresh.providers).map(p => ({ p, cls: classify(p) }))
    const lines = []
    const skipped = now.filter(c => c.cls !== 'extractable')
    const nameOf = c => c.p.name || c.p.provider_id
    // a task saved and not yet run (the browser was closed between the two steps) is run, not saved again
    let cohortId = null, run = null, selected = 0, parked = null
    if (resumable) { cohortId = saved.cohort_id; run = await call('run', { cohort_id: cohortId }); selected = Number(saved.totals?.selected ?? 1) }
    else {
      const groups = {}
      now.filter(c => c.cls === 'extractable').forEach(c => { (groups[fillModeOf(c.p)] ||= []).push(c.p.provider_id) })
      if (Object.keys(groups).length && reason.trim().length < minReason) return { category: 'error', lines: [`The platform now says a description can be read, but no reason is typed. Type a reason (${minReason} characters or more) and click again; nothing was queued.`] }
      const rowsNot = []
      for (const [fm, pids] of Object.entries(groups)) {
        const pv = await call('preview', { provider_ids: pids, fill_mode: fm, size: pids.length })
        const rows = list(pv.providers)
        rows.filter(r => !r.eligible).forEach(r => rowsNot.push(r))
        if (!(Number(pv.selected ?? 0) > 0)) continue
        const prep = await call('prepare', { preview_token: pv.token || pv.preview_token, reason: reason.trim() })
        setSaved(prep); cohortId = prep.cohort_id; selected += Number(pv.selected)
        try { run = await call('run', { cohort_id: prep.cohort_id }) } catch (e) { if (isPermission(e)) throw e; setUnknown(true); throw e }
      }
      rowsNot.forEach(r => lines.push(`${r.provider || r.name || 'A provider'}: ${selectionWords(r.eligibility_reason)}`))
      if (!cohortId) {
        // nothing could be read: say which of the seven reasons it is
        const kinds = new Set([...rowsNot.map(r => SELECTION[r.eligibility_reason]?.kind || 'none'), ...skipped.map(c => ({ locked: 'locked', up_to_date: 'up_to_date', in_progress: 'in_progress', recovering: 'in_progress', person: 'person', held: 'source' }[c.cls] || 'none'))])
        skipped.forEach(c => lines.push(`${nameOf(c)}: ${nextAction(c.p, caps)}`))
        const order = ['in_progress', 'person', 'policy', 'source', 'wait', 'locked', 'up_to_date', 'none']
        const kind = order.find(k => kinds.has(k)) || 'none'
        const only = kinds.size === 1 ? kind : (kinds.size === 0 ? 'none' : kind)
        return { category: only === 'none' ? 'none' : only, lines: lines.length ? lines : ['Nothing is eligible to be read now.'] }
      }
    }
    const dispatch = run?.dispatch || {}
    const s = await call('saved', { cohort_id: cohortId }); if (alive.current && s?.cohort_id) setSaved(s)
    await readStatus(true); onChanged?.()
    skipped.forEach(c => lines.push(`${nameOf(c)}: ${nextAction(c.p, caps)}`))
    const runIds = [run?.run_id, ...list(s?.runs).map(r => r.run_id)].filter(Boolean)
    if (dispatch.parked) {
      parked = DISPATCH[dispatch.reason] || { kind: 'error', words: `The task was saved and not started (${humanLabel(dispatch.reason) || 'no reason given'}).` }
      return { category: parked.kind === 'none' ? 'parked' : parked.kind, parked: true, lines: [parked.words, ...lines], runIds, cohortId, selected }
    }
    return { category: 'started', lines: [`${fmtNumber(selected)} provider${selected === 1 ? '' : 's'} sent to the governed reader.`, ...lines], runIds, cohortId, selected }
  }

  // ---- Details: the older preview-first route, the mode choice and the publication read-back --------------------------------------------------------------
  const fillModeFor = () => (mode === 'upgrade_basic' ? 'upgrade_basic' : mode === 'preview_only' && providers.every(p => p.description_present) ? 'upgrade_basic' : 'missing')
  const doPreview = () => operate('preview', async () => {
    setSaved(null); setUnknown(false)
    const r = await call('preview', { provider_ids: ids, fill_mode: fillModeFor(), size: ids.length })
    setPreview(r)
  })
  const doQueue = () => operate('queue', async () => {
    const p = await call('prepare', { preview_token: preview.token || preview.preview_token, reason: reason.trim() })
    setPreview(null); setSaved(p)
    try {
      const r = await call('run', { cohort_id: p.cohort_id })
      setUnknown(false)
      setNote([humanLabel(r.state), r.reason, r.dispatch?.reason ? humanLabel(r.dispatch.reason) : ''].filter(Boolean).join(' · ') || 'Queued with the governed reader.')
    } catch (e) { setUnknown(true); fail(e) }
    const s = await call('saved', { cohort_id: p.cohort_id }); if (s?.cohort_id) setSaved(s)
    await readStatus(false); onChanged?.()
  })
  const doRefresh = () => operate('refresh', async () => { await readStatus(true); if (saved?.cohort_id) { const s = await call('saved', { cohort_id: saved.cohort_id }); if (s?.cohort_id) setSaved(s) }; setUnknown(false); setNote('Status read again.') })
  const doVerify = () => operate('verify', async () => {
    const r = await call('provider_publication', { provider_ids: ids }); setPub(r)
    if (saved?.cohort_id && saved.state !== 'preview') { try { await call('verify', { cohort_id: saved.cohort_id }) } catch { /* the read-back above stands */ } }
    await readStatus(true); setNote('Read back from the catalogue, the Website and Zoho just now.')
  })

  const rows = list(preview?.providers)
  const modeInfo = FILL_MODES.find(m => m.id === mode)
  const runnable = (mode === 'missing' || mode === 'upgrade_basic')
  const title = ids.length === 1 ? (providers[0]?.name || (promptOn ? 'Fill description' : 'Extract description')) : `${promptOn ? 'Fill description' : 'Extract / refresh description now'}: ${ids.length} providers`
  const readerState = !caps ? null : !caps.enabled ? ['paused', 'The reader is switched off. A request is saved and resumes when it is switched on.'] : !caps.job_active ? ['paused', 'The reader is paused. A request is saved and resumes when it is switched on.'] : !caps.run_now_allowed ? ['warning', 'Run Now is not switched on for this reader (the allowlist is off). A request is saved and the scheduled reader picks it up.'] : null
  const needReason = (readable.length > 0 && !resumable) || (Boolean(preview) && Number(preview.selected ?? 0) > 0 && (mode === 'missing' || mode === 'upgrade_basic'))
  const reasonShort = needReason && reason.trim().length < minReason
  return <Overlay open={open} onClose={onClose} title={title} eyebrow="Provider descriptions" closeLabel="Close description panel" className="pff-overlay" data-fill-fields>
    <div className="pff" data-fill-fields-panel>
      {error && <p role="alert" className="pff-message pff-error">{error}</p>}
      {note && <p role="status" className="pff-message">{note}</p>}
      {busy && busy !== 'load' && <div role="status"><Loading compact label={busy === 'extract' ? 'Reading the provider\'s state, then saving the task and starting the governed reader…' : busy === 'queue' ? 'Saving the fixed cohort and queueing it with the governed reader…' : busy === 'verify' ? 'Reading the catalogue, the Website and Zoho…' : busy === 'preview' ? 'Reading what the reader would use…' : 'Reading status…'}/></div>}
      {busy === 'load' ? <Loading label="Reading each provider\'s description and task status…"/> : !ids.length ? <Empty text="No provider is selected."/> : <>
        <p className="pff-lead">One click reads the provider&apos;s official About page (stored evidence is reused), checks it against the automatic rules and queues it with the governed reader. A person decides in Layer 4 only where the rules say so. Closing this panel does not stop a task; open it again to see where it is.</p>
        {caps && <p className="pff-policy" data-fill-caps><StatusChip value={readerState ? readerState[0] : 'enabled'} label={readerState ? (readerState[0] === 'warning' ? 'Run Now not switched on' : 'Reader paused') : 'Reader on'}/><span>{readerState ? readerState[1] : `Up to ${fmtNumber(cap)} providers in one task`}</span></p>}
        {tooMany && <p role="alert" className="pff-message pff-error">{ids.length} providers are selected; one task can take {cap}. Select fewer providers (the limit is set in Settings › Pipeline settings).</p>}

        <section aria-label="Selected providers" className="pff-providers">
          {providers.map(p => <ProviderState key={p.provider_id} p={p} caps={caps}/>)}
        </section>
        <p className="pff-note" data-other-fields-note>The reader produces the <strong>description</strong> only. Other missing fields shown above (website, phone and so on) are for information: nothing reads them yet, and this panel does not change them.</p>

        {promptOn ? <section className="pff-primary" aria-label="Fill the description" data-primary data-fill-mode="prompt">
          <Button variant="primary" data-fill-now disabled={Boolean(busy) || fillable.length === 0} onClick={doFill}>Fill description</Button>
          <p className="pff-note">The AI reads the official About page and writes the description with the prompt on Models &amp; services › AI &amp; OpenRouter. It starts now and is not held by the regular scan&apos;s spending limits. A description written by hand is never replaced.</p>
          {fillable.length === 0 && providers.length > 0 && <p className="pff-note" data-nothing-to-extract>Nothing here needs filling now; each provider says why.</p>}
        </section> :
        <section className="pff-primary" aria-label="Extract or refresh the description" data-primary>
          {needReason && <label className="pff-reason">Reason (kept in the audit log)<input type="text" aria-label="Extract audit reason" value={reason} onChange={e => setReason(e.target.value)} disabled={Boolean(busy) || !canRun} placeholder="Why this description is being read now" maxLength={300}/></label>}
          <Button variant="primary" data-extract-now disabled={Boolean(busy) || !canRun || tooMany || reasonShort} onClick={doExtract} title={!canRun ? 'An authorised operator is required.' : undefined}>Extract / refresh description now</Button>
          {!canRun && <p className="pff-note" data-permission-note>Permission denied: your role can read each provider&apos;s state. An authorised operator must start an extraction.</p>}
          {canRun && reasonShort && <p className="pff-note">Type a short reason ({minReason} characters or more); it is recorded with the task.</p>}
          {canRun && readable.length === 0 && providers.length > 0 && !resumable && <p className="pff-note" data-nothing-to-extract>Nothing here needs extracting now; each provider says why and what happens next.</p>}
        </section>}
        {outcome && <section aria-label="Result" role="status" className={`pff-card pff-outcome tone-${OUTCOME_TONE[outcome.category] || 'neutral'}`} data-extract-outcome={outcome.category}>
          <h4>{OUTCOME_TITLE[outcome.category] || humanLabel(outcome.category)}</h4>
          {list(outcome.lines).map((l, i) => <p key={i}>{l}</p>)}
          {list(outcome.runIds).length > 0 && <p className="pff-note">Run <code>{outcome.runIds[0]}</code>{outcome.cohortId ? <> · task <code>{outcome.cohortId}</code></> : null}</p>}
        </section>}
        {saved?.cohort_id && <section aria-label="Task status" className="pff-card" data-fill-task>
          <h4>Task</h4>
          <p>Cohort <code>{saved.cohort_id}</code> · {humanLabel(saved.state)}{saved.created_at ? ` · saved ${stamp(saved.created_at)}` : ''}</p>
          {saved.reason && <p className="pff-note">Audit reason: {saved.reason}</p>}
          {list(saved.runs).map((r, i) => <p key={r.run_id || i}>Run <code>{r.run_id}</code> · {humanLabel(r.state)}{r.outcome ? ` · ${humanLabel(r.outcome)}` : ''}{r.finished_at ? ` · finished ${stamp(r.finished_at)}` : ''}</p>)}
          {saved.totals && <p className="pff-totals">{[['selected', 'selected'], ['evidence_read', 'evidence read'], ['proposed', 'proposed'], ['validation_failed', 'held'], ['human_decisions_required', 'awaiting a person'], ['admitted', 'admitted'], ['website_verified', 'on Website'], ['zoho_verified', 'in Zoho']].map(([k, w]) => <span key={k}><strong>{fmtNumber(saved.totals[k] ?? 0)}</strong> {w}</span>)}</p>}
          {unknown && <p role="status" className="pff-message">The outcome of the last step is not known. The saved cohort is kept; use Refresh status.</p>}
        </section>}

        <details className="pff-details" data-fill-details>
          <summary>Details: preview only, choose what to do, verify publication</summary>
          <div className="pff-details-body">
            <fieldset className="pff-modes" disabled={Boolean(busy)}>
              <legend>What to do</legend>
              {FILL_MODES.map(m => <label key={m.id} className="pff-mode"><input type="radio" name="pff-mode" value={m.id} checked={mode === m.id} onChange={() => { setMode(m.id); setPreview(null); setError(''); setNote('') }}/><span><strong>{m.label}{m.id === 'upgrade_basic' && caps?.upgrade_basic_on === false ? ' (switched off)' : ''}</strong><small>{m.help}</small></span></label>)}
            </fieldset>
            <div className="pff-actions">
              {mode !== 'verify_publication'
                ? <Button disabled={Boolean(busy) || !canPreview || tooMany} onClick={doPreview}>Preview what the reader would use</Button>
                : <Button disabled={Boolean(busy) || !canRun || tooMany} onClick={doVerify} title={!canRun ? 'An authorised operator is required to verify publication.' : undefined}>Verify publication now</Button>}
              <Button compact disabled={Boolean(busy)} onClick={doRefresh}>Refresh status</Button>
            </div>
            {mode === 'verify_publication' && !canRun && <p className="pff-note">Your role can read each provider&apos;s status. An authorised operator must run the publication read-back.</p>}
            {modeInfo && <p className="pff-note">{modeInfo.help}</p>}

            {pub && <section aria-label="Publication read-back" className="pff-card" data-publication-readback>
              <h4>Publication read-back</h4><p className="pff-note">As at {stamp(pub.as_at)}. This is what each consumer returns right now. Not served (not applicable) means that consumer does not serve the provider; it is not a failure. The Catalogue&apos;s own Website and Zoho state is shown beside it as the feed&apos;s expectation, and the two can differ (a consumer can return a provider the Catalogue marks Not applicable).</p>
              {list(pub.providers).map(p => <div key={p.provider_id} className="pff-readback"><strong>{p.name}</strong>
                <span>Catalogue: {p.catalogue?.status === 'present' ? 'description held' : 'no description'}</span>
                <span>Website: <Pub value={p.website?.status}/>{p.website?.feed && <small className="pff-feed"> Catalogue: {FEED_WORDS[p.website.feed] || p.website.feed}</small>}</span><span>Zoho: <Pub value={p.zoho?.status}/>{p.zoho?.feed && <small className="pff-feed"> Catalogue: {FEED_WORDS[p.zoho.feed] || p.zoho.feed}</small>}</span></div>)}
            </section>}

            {preview && <section aria-label="Preview" className="pff-card" data-fill-preview>
              <h4>{fmtNumber(preview.selected ?? 0)} of {fmtNumber(rows.length)} can be read</h4>
              <p className="pff-note">As at {stamp(preview.as_at)}. {preview.expires_at && `The preview expires ${stamp(preview.expires_at)}.`} Nothing has been queued and no description has changed.</p>
              {rows.map(r => <article key={r.provider_id} className="pff-preview-row" data-preview-provider={r.provider_id} data-eligible={r.eligible ? 'yes' : 'no'}>
                <div className="pff-head"><strong>{r.provider || r.name || 'Unknown provider'}</strong><StatusChip tone={r.eligible ? 'success' : 'warning'} label={r.eligible ? 'Can be read' : 'Not offered'}/></div>
                <p>{r.eligible ? 'The reader has approved official evidence for this provider.' : <>{SELECTION[r.eligibility_reason] ? `${SELECTION[r.eligibility_reason].words} ` : ''}<span className="pff-code">Reason from the platform: <code>{r.eligibility_reason || 'not recorded'}</code></span></>}</p>
                {r.source_url && <p className="pff-note">Official source: <a href={r.source_url} target="_blank" rel="noreferrer">{r.source_url}</a></p>}
                {r.evidence_id && <p className="pff-note">Stored evidence: <code>{r.evidence_id}</code></p>}
              </article>)}
              {runnable && (preview.selected ?? 0) > 0 && <div className="pff-audit">
                <p className="pff-note">{reasonShort ? `Type the reason above (${minReason} characters or more), then save.` : 'The reason above is recorded with the task.'}</p>
                <Button disabled={Boolean(busy) || !canRun || reasonShort} onClick={doQueue}>Save and queue with the reader</Button>
                {!canRun && <p className="pff-note">Your role can preview. An authorised operator must save and run a task.</p>}
              </div>}
            </section>}
          </div>
        </details>
      </>}
    </div>
  </Overlay>
}

function Pub({ value }) { const [label, tone] = PUBLICATION[value] || [humanLabel(value) || 'Unknown', 'neutral']; return <StatusChip tone={tone} label={label}/> }

function ProviderState({ p, caps }) {
  const q = qualityOf(p.quality_class)
  const t = p.latest_task
  const stages = stagesOf(p)
  const cls = classify(p)
  const fo = fieldOutcome(p)
  const otherFields = fieldWords(list(p.missing_fields).filter(f => f !== 'description'))
  return <article className="pff-provider" data-fill-provider={p.provider_id} data-quality={p.quality_class || 'unknown'} data-class={cls}>
    <div className="pff-head"><strong>{p.name}</strong><span><StatusChip tone={p.description_present ? 'success' : 'warning'} label={p.description_present ? 'Description held' : 'Description missing'}/> <StatusChip tone={TONE[p.quality_class] || 'neutral'} label={q.label}/>{p.locked && <StatusChip tone="warning" label="Locked"/>}</span></div>
    <ol className="pff-stages" aria-label="Where this description stands">
      {stages.map(s => <li key={s.key} data-stage={s.key} data-stage-state={s.state}>
        <span className="pff-stage-head"><strong>{s.label}</strong> <StatusChip tone={STAGE_TONE[s.state]} label={STAGE_WORD[s.state]}/></span>
        <span className="pff-stage-text">{s.text}{s.url && <> <a href={s.url} target="_blank" rel="noreferrer">{s.url}</a></>}{s.at ? ` · page captured ${stamp(s.at)}` : ''}{s.code && <span className="pff-code">Rule code: <code>{s.code}</code></span>}</span>
      </li>)}
      <li data-stage="publication" data-stage-state={p.description_present ? 'done' : 'none'}>
        <span className="pff-stage-head"><strong>Website and Zoho</strong></span>
        <span className="pff-stage-text pff-pub">{p.description_present ? <><span>Website: {p.website_publication ? <Pub value={p.website_publication}/> : 'Not worked out'}</span><span>Zoho: {p.zoho_publication ? <Pub value={p.zoho_publication}/> : 'Not worked out'}</span></> : 'Nothing to publish until a description is held'}</span>
      </li>
    </ol>
    <section className="pff-fields" data-field-outcomes aria-label="Result by field"><p data-field-outcome={fo.kind}><strong>Description:</strong> {fo.title}. <span className="pff-stage-text">{fo.text}</span></p>{otherFields.length > 0 && <p className="pff-note" data-field-outcome="not_read"><strong>{otherFields.join(', ')}:</strong> not read. No reader produces these fields yet, so nothing was tried.</p>}</section>
    <dl className="pff-facts">
      {p.next_retry_at && <><dt>Next retry</dt><dd>{stamp(p.next_retry_at)}</dd></>}
      {p.last_read_ok_at && <><dt>Last page read</dt><dd>{stamp(p.last_read_ok_at)}</dd></>}
      {p.admitted_at && <><dt>Admitted</dt><dd>{stamp(p.admitted_at)}{p.admitted_by ? ` · ${p.admitted_by === 'machine' ? 'by the machine rule' : 'by a Layer 4 decision'}` : ''}</dd></>}
      <dt>Run</dt><dd data-run-line>{t ? <>{t.run_id ? <code>{t.run_id}</code> : 'Saved, not started'} · {humanLabel(t.run_state || t.state)}{t.run_outcome ? ` · ${humanLabel(t.run_outcome)}` : ''}{t.requested_by_me ? ' · yours' : ''}</> : 'None yet'}</dd>
      <dt>Last run</dt><dd>{t ? stamp(t.run_finished_at || t.created_at) : 'None yet'}</dd>
    </dl>
    <p className="pff-next" data-next-action><strong>Next:</strong> {nextAction(p, caps)}</p>
    {list(p.missing_fields).length > 0 && <p className="pff-note" data-missing-fields>Other fields with no value (information only): {fieldWords(list(p.missing_fields).filter(f => f !== 'description')).join(', ') || 'none'}.</p>}
  </article>
}
