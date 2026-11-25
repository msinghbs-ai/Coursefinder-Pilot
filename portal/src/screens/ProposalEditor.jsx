import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { usePortal } from '../lib/portal.jsx'
import { useSaved } from '../lib/saved.js'
import { getProposal, saveProposal, refreshProposal } from '../lib/proposalApi.js'
import { basket } from '../lib/basket.js'
import {
  blankProposal, addCourses, moveCourse, removeCourse, proposalPayload, isDirty, validateProposal,
  statusInfo, whenText, agoText, groupChanges, changeCount, courseFromSummary,
} from '../lib/proposals.js'
import { money, durationText, durationInYears, dateText, initials, stateShort, NOT_RECORDED } from '../lib/format.js'
import { Pill, LoadState } from '../components/ui.jsx'

// Proposal builder (Mockups 11 and 12). The database owns versions, the course snapshots and the live comparison; this screen
// only edits the choices and shows what the database says. Limits and the soft-lock window arrive with the proposal (G2).
const INTAKE_TONE = { open: 'green', limited: 'amber', closed: 'grey' }
const ENTRY_TONE = { meets: 'green', short: 'amber', unknown: 'grey' }

const normalise = p => {
  const base = blankProposal()
  return { ...base, ...p, student: { ...base.student, ...(p?.student || {}) }, courses: p?.courses || [], steps: p?.steps || [], documents: p?.documents || [] }
}

function Field({ label, hint, children, wide }) {
  return <label className={`field${wide ? ' wide' : ''}`}><span className="field-label">{label}</span>{children}{hint && <small className="muted">{hint}</small>}</label>
}

function CourseRow({ c, n, count, changes, limits, onWhy, onMove, onRemove }) {
  const s = c.snapshot || {}
  const per = s.fee && Number(s.fee.per_year) > 0 ? money(s.fee.per_year, s.fee.currency) : null
  const years = durationInYears(s.duration_value, s.duration_unit)
  const total = per && years ? money(Math.round(Number(s.fee.per_year) * years), s.fee.currency) : null
  const place = [stateShort(s.state_code), s.city].filter(Boolean).join(' · ')
  const intake = s.next_intake
  const entry = s.entry
  return (
    <article className="card prop-course">
      <header className="prop-course-head">
        <span className="logo-tile" aria-hidden="true">{initials(s.provider_name)}</span>
        <div className="prop-course-title">
          <h3>{n + 1}. {s.title || 'Course'}</h3>
          <p className="muted small">{s.provider_name}{s.course_code ? ` · ${s.course_code}` : ''}</p>
        </div>
        <div className="reorder" role="group" aria-label={`Order of ${s.title || 'course'}`}>
          <button type="button" className="btn small" disabled={n === 0} onClick={() => onMove(n, n - 1)} aria-label={`Move ${s.title || 'course'} up`}>↑</button>
          <button type="button" className="btn small" disabled={n === count - 1} onClick={() => onMove(n, n + 1)} aria-label={`Move ${s.title || 'course'} down`}>↓</button>
          <button type="button" className="btn small" onClick={() => onRemove(c.course_id)} aria-label={`Remove ${s.title || 'course'}`}>Remove</button>
        </div>
      </header>
      <div className="cells">
        <div className="cell"><span className="cell-k">Campus</span><span className="cell-v">{place || NOT_RECORDED}</span></div>
        <div className="cell"><span className="cell-k">Length</span><span className="cell-v">{durationText(s.duration_value, s.duration_unit)}</span></div>
        <div className="cell"><span className="cell-k">Tuition per year</span><span className="cell-v">{per || NOT_RECORDED}</span>{total && <small className="muted">about {total} in total</small>}</div>
        <div className="cell"><span className="cell-k">Next intake</span><span className="cell-v">{intake ? (intake.label || dateText(intake.start_date, 'day') || NOT_RECORDED) : NOT_RECORDED}</span>
          {intake?.status && <Pill tone={INTAKE_TONE[intake.status] || 'grey'}>{intake.status_label || intake.status}</Pill>}
        </div>
      </div>
      <div className="tags">
        {entry?.badge && <Pill tone={ENTRY_TONE[entry.status] || 'grey'}>{entry.badge}</Pill>}
        {s.checked_at && <Pill>Checked {dateText(s.checked_at, 'day')}</Pill>}
        {s.provisional && <Pill tone="amber" dashed>Entry and English checks appear after you save</Pill>}
        {changes.map((ch, i) => <Pill key={i} tone="amber">{ch.label}: was {ch.from_text}</Pill>)}
      </div>
      <label className="field"><span className="field-label">Why this course (shown to the student)</span>
        <textarea rows={2} maxLength={Number(limits.why_max_chars) > 0 ? Number(limits.why_max_chars) : undefined} value={c.why || ''} onChange={e => onWhy(c.course_id, e.target.value)} />
      </label>
    </article>
  )
}

function RefreshBanner({ result, busy, dirty, onAccept, onKeep }) {
  const n = changeCount(result.changes)
  if (n === 0) return <div className="notice ok" role="status"><strong>Up to date.</strong> Details are as at {whenText(result.checked_at) || 'now'}. The PDF will say so.</div>
  return (
    <section className="refresh-found" aria-label="Changes found">
      <h2>Refreshed from live data: {n} {n === 1 ? 'change' : 'changes'}{result.built_at ? ` since you built this on ${dateText(result.built_at, 'day')}` : ''}</h2>
      <ul className="diff">
        {result.changes.map((c, i) => (
          <li key={i}>
            <span className="diff-k">{c.label}</span>
            <span className="diff-c">{c.course_title}{c.provider_name ? <small> {c.provider_name}</small> : null}</span>
            <span className="diff-v"><s>{c.from_text}</s> → <strong>{c.to_text}</strong></span>
          </li>
        ))}
      </ul>
      <div className="actions">
        <button type="button" className="btn primary" disabled={busy || dirty} onClick={onAccept}>Accept all changes</button>
        <button type="button" className="btn" disabled={busy} onClick={onKeep}>Keep my version</button>
        <span className="muted small">Nothing changes in the PDF until you choose.{dirty ? ' Save your edits first.' : ''}</span>
      </div>
    </section>
  )
}

export default function ProposalEditor({ id, params }) {
  const isNew = id === 'new'
  const { destinations, markets, studyIn } = usePortal()
  const [load, setLoad] = useState({ loading: true, error: '', unavailable: false })
  const [meta, setMeta] = useState({ limits: {}, others: [], counsellor: null })
  const [saved, setSaved] = useState(null)
  const [draft, setDraft] = useState(null)
  const [conflict, setConflict] = useState(null)
  const [refresh, setRefresh] = useState({ busy: false, result: null, error: '' })
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState(null)
  const [versions, setVersions] = useState(false)
  const [picker, setPicker] = useState(false)
  const [archiving, setArchiving] = useState(false)
  const savedCourses = useSaved(picker)

  const limits = meta.limits
  const dirty = Boolean(saved && draft && isDirty(saved, draft))
  const basketCount = basket.count()

  const apply = useCallback(p => { const n = normalise(p); setSaved(n); setDraft(n); setConflict(null) }, [])

  useEffect(() => {
    let live = true
    getProposal({ id: isNew ? null : id })
      .then(r => {
        if (!live) return
        setMeta({ limits: r.limits || {}, others: Array.isArray(r.others_recent) ? r.others_recent : [], counsellor: r.counsellor || null })
        if (isNew) {
          const blank = blankProposal(r.defaults || {})
          if (studyIn && !blank.student.destination) blank.student.destination = studyIn
          setSaved(blank)
          const picked = addCourses([], basket.list(), r.limits?.courses_max)
          setDraft({ ...blank, courses: picked.courses })
        } else apply(r.proposal)
        setLoad({ loading: false, error: '', unavailable: false })
      })
      .catch(e => { if (live) setLoad({ loading: false, error: e.message, unavailable: e.kind === 'missing' }) })
    return () => { live = false }
  }, [id]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!dirty) return undefined
    const warn = e => { e.preventDefault(); e.returnValue = '' }
    addEventListener('beforeunload', warn)
    return () => removeEventListener('beforeunload', warn)
  }, [dirty])

  const set = patch => setDraft(d => ({ ...d, ...patch }))
  const setStudent = patch => setDraft(d => ({ ...d, student: { ...d.student, ...patch } }))
  const setStep = (i, patch) => setDraft(d => ({ ...d, steps: d.steps.map((s, n) => (n === i ? { ...s, ...patch } : s)) }))

  const save = async ({ force = false, status } = {}) => {
    const problems = validateProposal(draft, limits)
    if (problems.length) { setNote({ tone: 'bad', text: problems.join(' ') }); return }
    setBusy(true); setNote(null)
    try {
      const next = status ? { ...draft, status } : draft
      const r = await saveProposal({ id: draft.id, base_version: force && conflict ? conflict.current_version : saved.version, force, proposal: proposalPayload(next) })
      if (r.status === 'saved_after_other_edit') { setConflict(r); return }
      if (isNew) basket.clear()
      apply(r.proposal)
      setNote({ tone: 'ok', text: `Saved as version ${r.proposal?.version ?? r.version}.` })
      if (isNew && r.proposal?.id) location.replace(`#/proposals/${r.proposal.id}`)
    } catch (e) { setNote({ tone: 'bad', text: e.message }) } finally { setBusy(false) }
  }

  const runRefresh = useCallback(async decision => {
    setRefresh(r => ({ ...r, busy: true, error: '' }))
    try {
      const r = await refreshProposal({ id: saved.id, base_version: saved.version, ...(decision ? { decision } : {}) })
      if (decision === 'accept') {
        if (r.status === 'saved_after_other_edit') { setConflict(r); setRefresh({ busy: false, result: null, error: '' }); return }
        apply(r.proposal)
        setNote({ tone: 'ok', text: `Accepted the changes. Saved as version ${r.proposal?.version}.` })
        setRefresh({ busy: false, result: null, error: '' })
      } else if (decision === 'keep') {
        setSaved(s => ({ ...s, needs_refresh: false, details_checked_at: r.checked_at || s.details_checked_at }))
        setNote({ tone: 'ok', text: 'Kept your version. Nothing changed in the PDF.' })
        setRefresh({ busy: false, result: null, error: '' })
      } else {
        setRefresh({ busy: false, result: r, error: '' })
        setSaved(s => ({ ...s, details_checked_at: r.checked_at || s.details_checked_at }))
      }
    } catch (e) { setRefresh({ busy: false, result: null, error: e.message }) }
  }, [saved, apply])

  const autoRefresh = params?.get('refresh') === '1'
  const [auto, setAuto] = useState(false)
  useEffect(() => { if (autoRefresh && !auto && saved?.id && !isNew) { setAuto(true); runRefresh() } }, [autoRefresh, auto, saved, isNew, runRefresh])

  const addFromList = items => {
    const r = addCourses(draft.courses, items.map(courseFromSummary), limits.courses_max)
    set({ courses: r.courses })
    const bits = []
    if (r.added) bits.push(`Added ${r.added} ${r.added === 1 ? 'course' : 'courses'}.`)
    if (r.duplicates) bits.push('Some were already in this proposal.')
    if (r.overLimit) bits.push(`A proposal holds up to ${limits.courses_max} courses.`)
    if (bits.length) setNote({ tone: r.overLimit ? 'bad' : 'ok', text: bits.join(' ') })
  }

  const changesBy = useMemo(() => groupChanges(refresh.result?.changes), [refresh.result])
  const unusedSaved = savedCourses.items.filter(i => !draft?.courses.some(c => c.course_id === i.course_id))

  if (load.loading) return <p className="muted" role="status">Opening the proposal…</p>
  if (load.unavailable) return <div className="stack-lg"><a className="backlink" href="#/proposals">← Proposals</a><div className="notice" role="status"><strong>Proposals are not switched on yet.</strong><p>The proposal functions are still being finished by the platform team, so nothing can be saved here yet. Your saved courses are safe on <a href="#/saved">Saved courses</a>.</p></div></div>
  if (load.error) return <div className="stack-lg"><a className="backlink" href="#/proposals">← Proposals</a><LoadState error={load.error} /></div>

  const info = statusInfo(saved.needs_refresh ? 'needs_refresh' : saved.status)
  const statusTone = saved.needs_refresh ? 'amber' : info.tone
  const statusLabel = saved.needs_refresh ? 'Needs refresh' : info.label
  const others = meta.others.filter(o => o.name)

  return (
    <div className="stack-lg proposal-editor">
      <div className="stack">
        <p className="small"><a className="backlink" href="#/proposals">← Proposals</a></p>
        <div className="editor-head">
          <div>
            <h1>{isNew ? 'New proposal' : (draft.title || 'Proposal')}</h1>
            <p className="muted">Build the options, check them against live data, then send a PDF to the student.</p>
            <div className="tags"><Pill tone={statusTone}>{statusLabel}</Pill>{!isNew && <Pill>Saved {whenText(saved.updated_at) || ''} · version {saved.version}</Pill>}</div>
          </div>
          <div className="actions">
            {!isNew && <button type="button" className="btn" aria-expanded={versions} onClick={() => setVersions(v => !v)}>Version history</button>}
            {!isNew && (dirty ? <button type="button" className="btn" disabled title="Save your changes first">Download PDF</button> : <a className="btn" href={`#/proposals/${saved.id}/sheet`}>Download PDF</a>)}
            {saved.status === 'draft' || isNew ? <button type="button" className="btn accent" disabled={busy} onClick={() => save({ status: 'ready' })}>Mark ready to send</button> : saved.status !== 'sent' && saved.status !== 'accepted' && <button type="button" className="btn" disabled={busy || dirty} onClick={() => save({ status: 'draft' })}>Back to draft</button>}
          </div>
        </div>
      </div>

      {others.length > 0 && (
        <div className="notice" role="status">
          {others.map(o => `${o.name} opened this proposal ${agoText(o.opened_at) || 'recently'}`).join('. ')}.
          {' '}Any counsellor can edit it. If you both save, the second person is asked to review the other’s changes first. Every save becomes a new version with the editor’s name.
        </div>
      )}
      {conflict && (
        <div className="notice bad" role="alert">
          <strong>{conflict.by_name || 'Someone'} saved version {conflict.current_version}{conflict.saved_at ? ` ${whenText(conflict.saved_at)}` : ''} after you opened this.</strong>
          {Array.isArray(conflict.changes) && conflict.changes.length > 0 && <ul className="plain">{conflict.changes.map((c, i) => <li key={i}>{c.label}</li>)}</ul>}
          <p>Review their changes first. Use their version, or keep yours and save it as the next version.</p>
          <div className="actions">
            <button type="button" className="btn" onClick={() => apply(conflict.proposal)}>Use their version</button>
            <button type="button" className="btn primary" disabled={busy} onClick={() => save({ force: true })}>Keep mine and save</button>
          </div>
        </div>
      )}
      {note && <div className={`notice ${note.tone}`} role={note.tone === 'bad' ? 'alert' : 'status'}>{note.text} <button type="button" className="link-inline" onClick={() => setNote(null)}>Dismiss</button></div>}

      {versions && !isNew && (
        <section className="card" aria-label="Version history">
          <h2>Versions</h2>
          <ul className="plain">{(saved.versions || []).map(v => <li key={v.version}><strong>v{v.version}</strong> {whenText(v.at) || ''}, {v.by_name}{v.note ? `, ${v.note}` : ''}{v.version === saved.version ? ' (this one)' : ''}</li>)}</ul>
        </section>
      )}

      {refresh.result && <RefreshBanner result={refresh.result} busy={refresh.busy} dirty={dirty} onAccept={() => runRefresh('accept')} onKeep={() => runRefresh('keep')} />}
      {refresh.error && <div className="notice bad" role="alert">{refresh.error}</div>}

      <section className="card stack" aria-labelledby="stu-h">
        <h2 id="stu-h">1 Student</h2>
        <div className="form-grid">
          <Field label="Student reference" hint="Leave blank for a new student and one is assigned when you save. Enter an existing reference to add another proposal for the same student."><input value={draft.student.ref} onChange={e => setStudent({ ref: e.target.value })} readOnly={!isNew && Boolean(saved.student?.ref)} /></Field>
          <Field label="Given name" hint="Shown on the PDF."><input value={draft.student.given_name} onChange={e => setStudent({ given_name: e.target.value })} autoComplete="off" /></Field>
          <Field label="Family name initial" hint="One letter. No full name, phone, email or passport number is stored."><input maxLength={2} value={draft.student.family_initial} onChange={e => setStudent({ family_initial: e.target.value })} autoComplete="off" /></Field>
          <Field label="Source country" hint="Where the student completed their schooling.">
            <select value={draft.student.source_country} onChange={e => setStudent({ source_country: e.target.value })}><option value="">Choose a country</option>{markets.map(m => <option key={m.code} value={m.code}>{m.name}</option>)}</select>
          </Field>
          <Field label="Qualification"><input value={draft.student.qualification} onChange={e => setStudent({ qualification: e.target.value })} /></Field>
          <Field label="Result"><input value={draft.student.result_text} onChange={e => setStudent({ result_text: e.target.value })} /></Field>
          <Field label="English"><input value={draft.student.english_text} onChange={e => setStudent({ english_text: e.target.value })} /></Field>
          <Field label="Study destination">
            <select value={draft.student.destination} onChange={e => setStudent({ destination: e.target.value })}><option value="">Choose a destination</option>{destinations.map(d => <option key={d.code} value={d.code}>{d.name}</option>)}</select>
          </Field>
          <Field label="Preferred intake"><input value={draft.student.preferred_intake} onChange={e => setStudent({ preferred_intake: e.target.value })} /></Field>
          <Field label="Budget per year"><input inputMode="numeric" value={draft.student.budget_per_year} onChange={e => setStudent({ budget_per_year: e.target.value.replace(/[^0-9.]/g, '') })} /></Field>
        </div>
        <div className="pdf-contents">
          <strong>PDF contents</strong>
          <ul className="plain ticks"><li>Side-by-side comparison</li><li>Fees and total cost</li><li>Entry and English requirements</li><li>Scholarships</li><li>Next steps and documents list</li><li>Counsellor contact details</li></ul>
          <p className="muted small">Anything not recorded prints as “Confirm with the provider”. Internal labels never appear.</p>
        </div>
      </section>

      <section className="stack" aria-labelledby="crs-h">
        <div className="count-row"><h2 id="crs-h">2 Selected courses {draft.courses.length}{Number(limits.courses_max) > 0 ? ` of up to ${limits.courses_max}` : ''}</h2>
          <button type="button" className="btn" aria-expanded={picker} onClick={() => setPicker(p => !p)}>+ Add from saved courses</button>
        </div>
        {basketCount > 0 && !isNew && <div className="notice">{basketCount} {basketCount === 1 ? 'course' : 'courses'} picked from search. <button type="button" className="link-inline" onClick={() => { addFromList(basket.list()); basket.clear() }}>Add {basketCount === 1 ? 'it' : 'them'} to this proposal</button></div>}
        {picker && (
          <div className="card stack" aria-label="Saved courses to add">
            <LoadState loading={savedCourses.loading} error={savedCourses.error} onRetry={savedCourses.refresh} what="your saved courses" />
            {!savedCourses.loading && unusedSaved.length === 0 && <p className="muted">All your saved courses are already here. Save more from <a href="#/courses">Courses</a>.</p>}
            {unusedSaved.map(c => <div key={c.course_id} className="pick-row"><div><strong>{c.title}</strong><small className="muted">{c.provider_name}</small></div><button type="button" className="btn small" onClick={() => addFromList([c])}>Add</button></div>)}
          </div>
        )}
        {draft.courses.length === 0 && <div className="empty"><strong>No courses yet.</strong><p className="muted">Add courses from your saved shortlist, or pick them from <a href="#/courses">Courses</a> and choose Add to proposal.</p></div>}
        {draft.courses.map((c, n) => (
          <CourseRow key={c.course_id} c={c} n={n} count={draft.courses.length} limits={limits} changes={changesBy.get(c.course_id) || []}
            onWhy={(cid, v) => set({ courses: draft.courses.map(x => (x.course_id === cid ? { ...x, why: v } : x)) })}
            onMove={(from, to) => set({ courses: moveCourse(draft.courses, from, to) })}
            onRemove={cid => set({ courses: removeCourse(draft.courses, cid) })} />
        ))}
      </section>

      {!isNew && (
        <section className="card keep-current" aria-labelledby="keep-h">
          <h2 id="keep-h">Keep it current</h2>
          <p className="muted">Details last checked {whenText(saved.details_checked_at) || 'not yet'}. Refresh reads the latest fees, intakes, entry and English requirements for every course here, then shows you what moved.</p>
          <div className="actions"><button type="button" className="btn primary" disabled={refresh.busy || dirty} onClick={() => runRefresh()}>{refresh.busy ? 'Refreshing…' : 'Refresh from live data'}</button>{dirty && <span className="muted small">Save your changes first, so the refresh compares the saved version.</span>}</div>
        </section>
      )}

      <section className="card stack" aria-labelledby="steps-h">
        <h2 id="steps-h">3 Next steps for the student</h2>
        <p className="muted small">Starts from the standard list and the intake you chose. Edit any line, change a date, or untick what the student does not need. Dates are targets, never promises from a provider.</p>
        {draft.steps.map((s, i) => (
          <div key={s.key || i} className="step-row">
            <label className="check"><input type="checkbox" checked={s.included !== false} onChange={e => setStep(i, { included: e.target.checked })} /><span className="sr">Include {s.title || 'this step'}</span></label>
            <div className="step-fields">
              <input aria-label="Step" value={s.title} onChange={e => setStep(i, { title: e.target.value })} />
              <textarea aria-label="Detail" rows={2} value={s.detail || ''} onChange={e => setStep(i, { detail: e.target.value })} />
            </div>
            <div className="step-meta">
              <select aria-label="Who" value={s.owner || 'counsellor'} onChange={e => setStep(i, { owner: e.target.value })}><option value="counsellor">Counsellor</option><option value="student">Student</option></select>
              <input aria-label="Date" value={s.due_label || ''} onChange={e => setStep(i, { due_label: e.target.value, due_date: null })} />
              <button type="button" className="btn small" onClick={() => set({ steps: draft.steps.filter((_, n) => n !== i) })} aria-label={`Remove step ${s.title || i + 1}`}>Remove</button>
            </div>
          </div>
        ))}
        <button type="button" className="btn" onClick={() => set({ steps: [...draft.steps, { key: null, title: '', detail: '', owner: 'student', due_label: '', due_date: null, included: true }] })}>+ Add a step</button>
        <Field label="Documents to have ready (one per line)"><textarea rows={4} value={draft.documents.join('\n')} onChange={e => set({ documents: e.target.value.split('\n') })} /></Field>
      </section>

      <section className="card stack" aria-labelledby="notes-h">
        <h2 id="notes-h">4 Notes</h2>
        <Field label="Message to the student (in the PDF)"><textarea rows={4} maxLength={Number(limits.message_max_chars) > 0 ? Number(limits.message_max_chars) : undefined} value={draft.message_to_student} onChange={e => set({ message_to_student: e.target.value })} /></Field>
        <Field label="Counsellor notes (never in the PDF)" hint="Keep personal details out: no surname, phone, email or passport number."><textarea rows={3} maxLength={Number(limits.note_max_chars) > 0 ? Number(limits.note_max_chars) : undefined} value={draft.internal_note} onChange={e => set({ internal_note: e.target.value })} /></Field>
      </section>

      {!isNew && saved.status !== 'archived' && (
        <div className="stack">
          {!archiving && <button type="button" className="link-inline" onClick={() => setArchiving(true)}>Archive this proposal</button>}
          {archiving && <div className="notice">Archive this proposal? It stays in the list under Archived and can be restored. Nothing is deleted. <div className="actions"><button type="button" className="btn small primary" disabled={busy || dirty} onClick={() => { setArchiving(false); save({ status: 'archived' }) }}>Archive</button><button type="button" className="btn small" onClick={() => setArchiving(false)}>Cancel</button></div></div>}
        </div>
      )}

      <div className="savebar" role="region" aria-label="Save">
        <span className="muted">{dirty || (isNew && draft.courses.length > 0) ? 'You have unsaved changes.' : 'All changes saved.'}</span>
        <div className="actions">
          {dirty && !isNew && <button type="button" className="btn" disabled={busy} onClick={() => setDraft(saved)}>Discard changes</button>}
          <button type="button" className="btn primary" disabled={busy || (!dirty && !isNew)} onClick={() => save()}>{busy ? 'Saving…' : isNew ? 'Create proposal' : 'Save as new version'}</button>
        </div>
      </div>
    </div>
  )
}
