// CF-247 Fill fields (Platform Admin directive 9-10 Nov 2026, P0): provider on-demand field enrichment inside the existing Provider Catalogue and Provider Detail screens.
// It is a small panel over the existing Provider description Run & Validate service (public.admin_provider_description_run_v1): the same preview, the same fixed cohort (prepare), the same
// Run Now (run), the same saved/verify. It adds no second pipeline and no dashboard. Everything it shows is read from the server, so closing the browser loses nothing: opening the panel
// again reads each provider's status and the task that last included it.
import React, { useEffect, useRef, useState } from 'react'
import { Button, Empty, Loading, StatusChip, humanLabel } from './ui-kit'
import { Overlay } from './Overlay'
import { fmtDateTime, fmtNumber } from './lib/format.js'
import { plainError } from './lib/errors'
import { providerDescriptionRunApi } from './provider-description-run-api'
import { fieldWords, qualityOf } from './catalogue-columns.js'
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
const PUBLICATION = { verified: ['Matched', 'success'], pending: ['Pending', 'info'], not_applicable: ['Not applicable', 'neutral'], mismatch: ['Differs', 'warning'], not_served: ['Not served (not applicable)', 'neutral'], error: ['Could not be read', 'danger'], awaiting_description: ['No description yet', 'neutral'] }
const REASONS = {
  description_already_present: 'A description is already held. Use "Refresh a basic registry description" for a registry-only description.',
  not_a_basic_registry_profile: 'This is not a basic registry description, so the refresh mode does not apply.',
  not_selected_by_governed_policy: 'The governed selection did not offer this provider (scope, publication or type policy).',
  manual_lock: 'Locked: a person has locked this provider\'s description. It is never overwritten.',
  upgrade_switched_off: 'Upgrade is switched off: a Platform Admin policy decision. Nothing is queued until a Platform Admin switches it on.',
  description_current: 'The description is current under the platform\'s recheck window.',
  unknown_provider: 'This provider was not found.',
}
const FEED_WORDS = { verified: 'matched', pending: 'pending', not_applicable: 'not applicable' }
const reasonText = code => (REASONS[code] ? `${REASONS[code]} ` : '')

export default function ProviderFillFields({ providerIds = [], rank = 0, onClose, onChanged, client = providerDescriptionRunApi, open = true }) {
  const ids = [...new Set(providerIds)].filter(Boolean)
  const [caps, setCaps] = useState(null), [status, setStatus] = useState(null), [mode, setMode] = useState(''), [preview, setPreview] = useState(null)
  const [saved, setSaved] = useState(null), [reason, setReason] = useState(''), [busy, setBusy] = useState('load'), [error, setError] = useState(''), [note, setNote] = useState('')
  const [pub, setPub] = useState(null), [unknown, setUnknown] = useState(false), alive = useRef(true), key = ids.join(',')
  const fail = e => setError(plainError(e))
  const call = (action, args = {}) => client.call(action, args)
  const canPreview = Number(rank) >= 3
  const canRun = caps?.can_run === true && Number(rank) >= Number(caps?.control_rank ?? 6)
  const cap = Number(caps?.max_size ?? 0)
  const tooMany = caps && ids.length > cap

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
      setBusy('load'); setError(''); setNote(''); setPreview(null); setSaved(null); setPub(null); setUnknown(false)
      try {
        // the caps first: one status read and one task name the same number of providers at most (the cohort cap), so a longer selection is explained and not read
        const c = await call('fill_caps')
        if (!alive.current) return
        setCaps(c)
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
  const fillModeFor = () => (mode === 'upgrade_basic' ? 'upgrade_basic' : mode === 'preview_only' && list(status?.providers).every(p => p.description_present) ? 'upgrade_basic' : 'missing')
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

  const providers = list(status?.providers)
  const rows = list(preview?.providers)
  const modeInfo = FILL_MODES.find(m => m.id === mode)
  const runnable = (mode === 'missing' || mode === 'upgrade_basic')
  const title = ids.length === 1 ? (providers[0]?.name || 'Fill fields') : `Fill fields for ${ids.length} providers`
  return <Overlay open={open} onClose={onClose} title={title} eyebrow="Provider descriptions" closeLabel="Close Fill fields" className="pff-overlay" data-fill-fields>
    <div className="pff" data-fill-fields-panel>
      {error && <p role="alert" className="pff-message pff-error">{error}</p>}
      {note && <p role="status" className="pff-message">{note}</p>}
      {busy && busy !== 'load' && <div role="status"><Loading compact label={busy === 'queue' ? 'Saving the fixed cohort and queueing it with the governed reader…' : busy === 'verify' ? 'Reading the catalogue, the Website and Zoho…' : busy === 'preview' ? 'Reading what the reader would use…' : 'Reading status…'}/></div>}
      {busy === 'load' ? <Loading label="Reading each provider\'s description and task status…"/> : !ids.length ? <Empty text="No provider is selected."/> : <>
        <p className="pff-lead">This uses the existing Provider description Run &amp; Validate: the same governed reader, the same fixed cohort and Run Now, and the same Layer 4 decisions. Closing this panel does not stop a task; open it again to see where it is.</p>
        {caps && <p className="pff-policy" data-fill-caps><StatusChip value={caps.enabled && caps.job_active && caps.run_now_allowed ? 'enabled' : 'paused'} label={caps.enabled && caps.job_active && caps.run_now_allowed ? 'Reader on' : 'Reader paused or not allowed for Run Now'}/><span>Up to {fmtNumber(cap)} providers in one task</span></p>}
        {tooMany && <p role="alert" className="pff-message pff-error">{ids.length} providers are selected; one task can take {cap}. Select fewer providers (the limit is set in Settings › Pipeline settings).</p>}

        <section aria-label="Selected providers" className="pff-providers">
          {providers.map(p => <ProviderState key={p.provider_id} p={p}/>)}
        </section>
        <p className="pff-note" data-other-fields-note>The reader produces the <strong>description</strong> only. Other missing fields shown above (website, phone and so on) are for information: nothing reads them yet, and this panel does not change them.</p>

        <fieldset className="pff-modes" disabled={Boolean(busy)}>
          <legend>What to do</legend>
          {FILL_MODES.map(m => <label key={m.id} className="pff-mode"><input type="radio" name="pff-mode" value={m.id} checked={mode === m.id} onChange={() => { setMode(m.id); setPreview(null); setError(''); setNote('') }}/><span><strong>{m.label}{m.id === 'upgrade_basic' && caps?.upgrade_basic_on === false ? ' (switched off)' : ''}</strong><small>{m.help}</small></span></label>)}
        </fieldset>

        <div className="pff-actions">
          {mode !== 'verify_publication'
            ? <Button variant="primary" disabled={Boolean(busy) || !canPreview || tooMany} onClick={doPreview}>Preview what the reader would use</Button>
            : <Button variant="primary" disabled={Boolean(busy) || !canRun || tooMany} onClick={doVerify} title={!canRun ? 'An authorised operator is required to verify publication.' : undefined}>Verify publication now</Button>}
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
            <p>{r.eligible ? 'The reader has approved official evidence for this provider.' : <>{reasonText(r.eligibility_reason)}<span className="pff-code">Reason from the platform: <code>{r.eligibility_reason || 'not recorded'}</code></span></>}</p>
            {r.source_url && <p className="pff-note">Official source: <a href={r.source_url} target="_blank" rel="noreferrer">{r.source_url}</a></p>}
            {r.evidence_id && <p className="pff-note">Stored evidence: <code>{r.evidence_id}</code></p>}
          </article>)}
          {runnable && (preview.selected ?? 0) > 0 && <div className="pff-audit">
            <label>Audit reason<textarea aria-label="Fill fields audit reason" value={reason} onChange={e => setReason(e.target.value)} disabled={Boolean(busy)} placeholder="Why these providers are being read now"/></label>
            <Button variant="primary" disabled={Boolean(busy) || !canRun || reason.trim().length < Number(caps?.reason_min_chars ?? 5)} onClick={doQueue}>Save and queue with the reader</Button>
            {!canRun && <p className="pff-note">Your role can preview. An authorised operator must save and run a task.</p>}
          </div>}
        </section>}

        {saved?.cohort_id && <section aria-label="Task status" className="pff-card" data-fill-task>
          <h4>Task</h4>
          <p>Cohort <code>{saved.cohort_id}</code> · {humanLabel(saved.state)}{saved.created_at ? ` · saved ${stamp(saved.created_at)}` : ''}</p>
          {saved.reason && <p className="pff-note">Audit reason: {saved.reason}</p>}
          {list(saved.runs).map((r, i) => <p key={r.run_id || i}>Run <code>{r.run_id}</code> · {humanLabel(r.state)}{r.outcome ? ` · ${humanLabel(r.outcome)}` : ''}{r.finished_at ? ` · finished ${stamp(r.finished_at)}` : ''}</p>)}
          {saved.totals && <p className="pff-totals">{[['selected', 'selected'], ['evidence_read', 'evidence read'], ['proposed', 'proposed'], ['validation_failed', 'held'], ['human_decisions_required', 'awaiting a person'], ['admitted', 'admitted'], ['website_verified', 'on Website'], ['zoho_verified', 'in Zoho']].map(([k, w]) => <span key={k}><strong>{fmtNumber(saved.totals[k] ?? 0)}</strong> {w}</span>)}</p>}
          {unknown && <p role="status" className="pff-message">The outcome of the last step is not known. The saved cohort is kept; use Refresh status.</p>}
        </section>}
      </>}
    </div>
  </Overlay>
}

function Pub({ value }) { const [label, tone] = PUBLICATION[value] || [humanLabel(value) || 'Unknown', 'neutral']; return <StatusChip tone={tone} label={label}/> }

function ProviderState({ p }) {
  const q = qualityOf(p.quality_class)
  const t = p.latest_task
  const reader = p.reader || {}
  return <article className="pff-provider" data-fill-provider={p.provider_id} data-quality={p.quality_class || 'unknown'}>
    <div className="pff-head"><strong>{p.name}</strong><span><StatusChip tone={p.description_present ? 'success' : 'warning'} label={p.description_present ? 'Description held' : 'Description missing'}/> <StatusChip tone={TONE[p.quality_class] || 'neutral'} label={q.label}/>{p.locked && <StatusChip tone="warning" label="Locked"/>}</span></div>
    <dl className="pff-facts">
      <dt>Source</dt><dd>{p.source_tier ? humanLabel(p.source_tier.replace('registry_factual', 'registry facts')) : (p.description_present ? 'Not recorded' : '—')}</dd>
      <dt>Reader</dt><dd>{reader.state ? `${humanLabel(reader.state)}${reader.rule ? ` · ${humanLabel(reader.rule)}` : ''}${reader.tries != null ? ` · ${reader.tries} tries` : ''}` : 'Not read yet'}</dd>
      {p.hold_reason && <><dt>Held because</dt><dd>{p.hold_reason}</dd></>}
      {p.next_retry_at && <><dt>Next retry</dt><dd>{stamp(p.next_retry_at)}</dd></>}
      {p.last_read_ok_at && <><dt>Last page read</dt><dd>{stamp(p.last_read_ok_at)}</dd></>}
      {p.admitted_at && <><dt>Admitted</dt><dd>{stamp(p.admitted_at)}{p.admitted_by ? ` · ${p.admitted_by === 'machine' ? 'by the machine rule' : 'by a Layer 4 decision'}` : ''}</dd></>}
      {(p.l4_status || p.review_item_id) && <><dt>Layer 4</dt><dd>{p.l4_status === 'pending' ? 'Waiting for a person' : humanLabel(p.l4_status) || 'Linked'}</dd></>}
      {p.description_present && <><dt>Website</dt><dd>{p.website_publication ? <Pub value={p.website_publication}/> : 'Not worked out'}</dd><dt>Zoho</dt><dd>{p.zoho_publication ? <Pub value={p.zoho_publication}/> : 'Not worked out'}</dd></>}
      <dt>Task</dt><dd>{t ? `${humanLabel(t.run_state || t.state)}${t.run_outcome ? ` · ${humanLabel(t.run_outcome)}` : ''} · ${stamp(t.created_at)}${t.requested_by_me ? ' · yours' : ''}` : 'None yet'}</dd>
    </dl>
    {list(p.missing_fields).length > 0 && <p className="pff-note" data-missing-fields>Other fields with no value (information only): {fieldWords(list(p.missing_fields).filter(f => f !== 'description')).join(', ') || 'none'}.</p>}
  </article>
}
