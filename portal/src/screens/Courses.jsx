import React, { useEffect, useMemo, useState } from 'react'
import { rpc } from '../lib/api.js'
import { usePortal } from '../lib/portal.jsx'
import { useSaved } from '../lib/saved.js'
import { basket } from '../lib/basket.js'
import { durationText, money, dateText, stateShort, NOT_RECORDED } from '../lib/format.js'
import { PageHead, StudyInBar, Pill } from '../components/ui.jsx'
import { ExtLink } from '../components/ExtLink.jsx'
import { CourseDetails, DetailsButton } from '../components/CourseDetails.jsx'

// Plain-English course search. The search itself is catalogue.portal_course_search_v1 (S1-Build), called through
// public.portal_course_search_v1(p_args jsonb). Until it is live this screen says so and never crashes. The response shape is
// in the portal design document ("Course search contract"). A value the function leaves out is "Not recorded", never a guess.
const FN = 'portal_course_search_v1'

const readList = (params, key, fallback) => { try { const v = JSON.parse(params.get(key) || ''); return Array.isArray(v) ? v : fallback } catch { return fallback } }
function writeHash(q, parts) {
  const u = new URLSearchParams()
  if (q) u.set('q', q)
  if (parts.provider) { u.set('provider', parts.provider); if (parts.providerName) u.set('providerName', parts.providerName) }
  if (parts.drop?.length) u.set('drop', JSON.stringify(parts.drop))
  if (parts.relax?.length) u.set('relax', JSON.stringify(parts.relax))
  location.hash = `#/courses${u.toString() ? `?${u}` : ''}`
}

function normaliseRelaxations(r) {
  if (Array.isArray(r?.relaxations)) return r.relaxations
  if (r?.relaxation) return [r.relaxation]
  return []
}

function CourseCard({ c, near, canSave, saved, busy, onToggle }) {
  const [inBasket, setInBasket] = useState(() => basket.has(c.course_id))
  const [open, setOpen] = useState(false)
  const panel = `details-${c.course_id}`
  const place = [stateShort(c.state_code), c.city].filter(Boolean).join(' · ')
  const fee = c.fee && Number(c.fee.per_year) ? money(c.fee.per_year, c.fee.currency) : null
  const intakes = Array.isArray(c.intakes) && c.intakes.length ? c.intakes : c.next_intake ? [c.next_intake] : []
  const score = Number(c.topic_score)
  return (
    <article className="card course">
      <header className="course-head">
        <div>
          <h3>{c.title}</h3>
          <p className="muted">{c.provider_name}</p>
          {place && <div className="tags"><Pill>{place}</Pill></div>}
        </div>
        <div className="badges">
          {c.topic_match && <Pill tone="teal">Topic match{Number.isFinite(score) && score > 0 ? ` ${Math.round(score <= 1 ? score * 100 : score)}%` : ''}</Pill>}
          {near && c.miss_text && <Pill tone="amber">{c.miss_text}</Pill>}
        </div>
      </header>
      {Array.isArray(c.why) && c.why.length > 0 && <p className="why"><strong>Why it matched:</strong> {c.why.join(' · ')}</p>}
      <div className="cells">
        <div className="cell"><span className="cell-k">Annual tuition{c.fee?.year ? ` ${c.fee.year}` : ''}</span><span className="cell-v">{fee || NOT_RECORDED}</span></div>
        <div className="cell"><span className="cell-k">Duration</span><span className="cell-v">{durationText(c.duration_value, c.duration_unit)}</span></div>
        <div className="cell"><span className="cell-k">Level</span><span className="cell-v">{c.level || NOT_RECORDED}</span></div>
        <div className="cell"><span className="cell-k">Next intake</span>
          <span className="cell-v">{intakes.length ? intakes.map((i, n) => <span key={n} className="intake">{i.label || dateText(i.start_date, 'day') || NOT_RECORDED}</span>) : NOT_RECORDED}</span>
        </div>
      </div>
      <div className="actions">
        {canSave && <button type="button" className={`btn${saved ? ' on' : ''}`} aria-pressed={saved} disabled={busy} onClick={() => onToggle(c.course_id, !saved)}>{saved ? '♥ Saved' : '♡ Save'}</button>}
        {canSave && <button type="button" className={`btn${inBasket ? ' on' : ''}`} aria-pressed={inBasket} onClick={() => { if (inBasket) basket.remove(c.course_id); else basket.add(c); setInBasket(!inBasket) }}>{inBasket ? '✓ In proposal' : '+ Add to proposal'}</button>}
        <DetailsButton open={open} id={panel} onClick={() => setOpen(o => !o)} />
        <ExtLink className="btn" href={c.course_url}>Open course</ExtLink>
      </div>
      {open && <CourseDetails id={panel} courseId={c.course_id} />}
    </article>
  )
}

export default function Courses({ params, access }) {
  const { studyIn } = usePortal()
  const q = params.get('q') || ''
  const provider = params.get('provider') || ''
  const providerName = params.get('providerName') || ''
  const drop = useMemo(() => readList(params, 'drop', []), [params])
  const relax = useMemo(() => readList(params, 'relax', []), [params])
  const [text, setText] = useState(q)
  const [state, setState] = useState({ loading: false, error: '', unavailable: false, data: null })
  const canSave = access.kind === 'counsellor'
  const saved = useSaved(canSave)
  useEffect(() => setText(q), [q])

  const ready = Boolean(q.trim() || provider)
  useEffect(() => {
    if (!ready) { setState({ loading: false, error: '', unavailable: false, data: null }); return undefined }
    let live = true
    setState(s => ({ ...s, loading: true, error: '' }))
    rpc(FN, { p_args: { q, countries: studyIn ? [studyIn] : [], provider_id: provider || null, removed: drop, relax } })
      .then(data => { if (live) setState({ loading: false, error: '', unavailable: false, data }) })
      .catch(e => { if (live) setState({ loading: false, error: e.message, unavailable: e.kind === 'missing', data: null }) })
    return () => { live = false }
  }, [ready, q, provider, studyIn, drop, relax])

  const d = state.data
  const chips = Array.isArray(d?.understood) ? d.understood : []
  const exact = Array.isArray(d?.exact) ? d.exact : []
  const near = Array.isArray(d?.near_misses) ? d.near_misses : []
  const relaxations = normaliseRelaxations(d)
  const submit = e => { e.preventDefault(); writeHash(text.trim(), { provider, providerName, drop: [], relax: [] }) }
  const removeChip = key => writeHash(q, { provider, providerName, drop: [...new Set([...drop, key])], relax })
  const clearAll = () => writeHash(q, { provider, providerName, drop: chips.filter(c => c.removable).map(c => c.key), relax })
  const applyRelax = r => writeHash(q, { provider, providerName, drop, relax: [...relax.filter(x => x.key !== r.key), { key: r.key, to: r.to }] })
  const clearProvider = () => writeHash(q, { drop, relax })

  return (
    <div className="stack-lg">
      <PageHead title="Courses" sub="Search in plain English, then adjust the filters it found." />
      <StudyInBar />
      <section className="hero" aria-labelledby="find-h">
        <h2 id="find-h">Find a course</h2>
        <p className="hero-sub">Filters come from your words and you can remove any of them. Topic words only change the order.</p>
        <form className="searchbar" onSubmit={submit}>
          <input aria-label="Describe the course you want" placeholder="For example: Bachelor of Nursing in Melbourne under $40,000 per year" value={text} onChange={e => setText(e.target.value)} />
          <button className="btn accent">Search</button>
        </form>
        {(provider || chips.length > 0) && (
          <div className="understood">
            <span className="understood-k">Understood as</span>
            {provider && <span className="chip-x">Provider: {providerName || 'chosen provider'}<button type="button" aria-label="Remove the provider filter" onClick={clearProvider}>×</button></span>}
            {chips.map(c => (
              <span key={c.key} className={`chip-x${c.kind === 'topic' ? ' topic' : ''}`}>
                {c.label}
                {c.removable !== false && <button type="button" aria-label={`Remove ${c.label}`} onClick={() => removeChip(c.key)}>×</button>}
              </span>
            ))}
            {chips.some(c => c.removable !== false) && <button type="button" className="btn small" onClick={clearAll}>Clear all</button>}
          </div>
        )}
      </section>

      {!ready && <div className="empty"><strong>Describe the course you want.</strong><p className="muted">Name a level, a place, a budget or a topic, for example “Master of Data Science in Sydney”.</p></div>}
      {ready && state.loading && <p className="muted" role="status">Searching…</p>}
      {ready && state.unavailable && (
        <div className="notice" role="status">
          <strong>Course search is not switched on yet.</strong>
          <p>The search function is still being finished by the platform team, so nothing has been searched. Your words are kept{q ? <>: “{q}”</> : ''}. You can browse <a href="#/providers">Universities &amp; Providers</a> and <a href="#/scholarships">Scholarships</a> in the meantime.</p>
        </div>
      )}
      {ready && state.error && !state.unavailable && <div className="notice bad" role="alert">{state.error}</div>}
      {saved.message && <div className="notice bad" role="alert">{saved.message} <button type="button" className="link-inline" onClick={saved.clearMessage}>Dismiss</button></div>}
      {canSave && basket.count() > 0 && <div className="notice" role="status"><strong>{basket.count()} {basket.count() === 1 ? 'course' : 'courses'} picked for a proposal.</strong> <a href="#/proposals/new">Start the proposal</a></div>}

      {d && !state.loading && (
        <>
          {exact.length === 0 && (
            <div className="relax" role="region" aria-label="No exact matches">
              <h2>0 courses match every filter</h2>
              <p>{d.relax_text || 'Nothing matches all of the filters above. Here is what you can change, and what each change would show.'}</p>
              {relaxations.length > 0 && <div className="actions">{relaxations.map((r, n) => <button type="button" key={`${r.key}-${r.to}`} className={n === 0 ? 'btn primary' : 'btn'} onClick={() => applyRelax(r)}>{r.label}{Number.isFinite(Number(r.would_return)) ? ` · shows ${r.would_return} ${Number(r.would_return) === 1 ? 'course' : 'courses'}` : ''}</button>)}</div>}
              {relaxations.some(r => r.note) && <p className="small">{relaxations.find(r => r.note).note} Nothing changes until you choose.</p>}
            </div>
          )}
          {exact.length > 0 && <p className="count"><strong>{exact.length.toLocaleString('en-AU')}</strong>{Number(d.total) > exact.length ? ` of ${Number(d.total).toLocaleString('en-AU')}` : ''} {exact.length === 1 ? 'course' : 'courses'} ranked by meaning</p>}
          {Number(d.total) > exact.length && exact.length > 0 && <p className="muted small">Showing the best {exact.length}. Add a filter to narrow the rest.</p>}
          <div className="stack">{exact.map(c => <CourseCard key={c.course_id} c={c} canSave={canSave} saved={saved.ids.has(c.course_id)} busy={saved.busy === c.course_id} onToggle={saved.toggle} />)}</div>
          {near.length > 0 && (
            <>
              <div className="count-row"><p className="count"><strong>{near.length}</strong> near {near.length === 1 ? 'miss' : 'misses'}</p><Pill tone="amber">Not exact matches</Pill></div>
              <div className="stack">{near.map(n => { const c = n.course || n; return <CourseCard key={c.course_id} c={{ ...c, miss_text: n.miss_text || c.miss_text || (n.misses ? `Misses: ${(chips.find(x => x.key === n.misses) || {}).label || n.misses}` : '') }} near canSave={canSave} saved={saved.ids.has(c.course_id)} busy={saved.busy === c.course_id} onToggle={saved.toggle} /> })}</div>
            </>
          )}
          {exact.length === 0 && near.length === 0 && relaxations.length === 0 && <div className="empty"><strong>No courses found.</strong><p className="muted">Try fewer words, or remove a filter above.</p></div>}
        </>
      )}
    </div>
  )
}
