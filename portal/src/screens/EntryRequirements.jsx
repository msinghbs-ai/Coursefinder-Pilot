import React, { useCallback, useEffect, useState } from 'react'
import { rpc } from '../lib/api.js'
import { usePortal, useDebounced } from '../lib/portal.jsx'
import { useSaved } from '../lib/saved.js'
import { basket } from '../lib/basket.js'
import { entryLine, entryForMarket, englishLine, lengthOrBlank, primaryFeeAmount, primaryFeeNote } from '../lib/courseDetailFormat.js'
import { placeText } from '../lib/format.js'
import { PageHead, StudyInBar, Select, LoadState, ShowMore, Count, Pill, ViewToggle, RegBadge, MarketOptions, IntlBadge, ProviderLine } from '../components/ui.jsx'
import { CourseRow, ListHead } from '../components/CourseRow.jsx'
import { DetailDrawer } from '../components/DetailDrawer.jsx'
import { ExtLink } from '../components/ExtLink.jsx'
import { DetailsButton } from '../components/CourseDetails.jsx'

// Entry Requirements (AER): academic and English entry requirements by destination, study level, provider or course, and the
// student's country of education. It lists courses that hold a recorded requirement (portal_aer_list_v1, s1214; study levels from
// portal_study_levels_v1, s1215).
// A Counsellor can save a course or add it to a proposal from here; a Viewer reads only. A value the platform does not hold is "Not recorded".
const FN = 'portal_aer_list_v1'
const HAS = [{ value: '', label: 'Academic or English' }, { value: 'both', label: 'Both academic and English' }, { value: 'academic', label: 'Academic only' }, { value: 'english', label: 'English only' }]

// s1222: a concise card: only what is held is shown; "Not recorded" stays inside Course details (the right-hand drawer), where the
// provider's table for the student's country is read in full.
function SaveButtons({ c, canSave, saved, busy, onToggle }) {
  const [inBasket, setInBasket] = useState(() => basket.has(c.course_id))
  if (!canSave) return null
  return (
    <>
      <button type="button" className={`btn${saved ? ' on' : ''}`} aria-pressed={saved} disabled={busy} onClick={() => onToggle(c.course_id, !saved)}>{saved ? '♥ Saved' : '♡ Save'}</button>
      <button type="button" className={`btn${inBasket ? ' on' : ''}`} aria-pressed={inBasket} onClick={() => { if (inBasket) basket.remove(c.course_id); else basket.add({ ...c, level: c.level_name, course_url: c.official_url }); setInBasket(!inBasket) }}>{inBasket ? '✓ In proposal' : '+ Add to proposal'}</button>
    </>
  )
}

const facts = c => ({ place: placeText(c, ', ', true), length: lengthOrBlank(c.duration_value, c.duration_unit), fee: primaryFeeAmount(c.annual_tuition_fee) })

function EntryCard({ c, market, marketName, onOpen, openId, ...save }) {
  const entry = entryForMarket(c.entry_requirements, market).map(entryLine), english = (c.english_requirements || []).map(englishLine)
  const f = facts(c)
  return (
    <article className="card course">
      <header className="course-head">
        <div>
          <div className="title-row"><h3>{c.title}</h3><RegBadge r={c.regulator} /></div>
          <ProviderLine name={c.provider_name} />
        </div>
      </header>
      <div className="tags">{c.country_code && <Pill>{c.country_code}</Pill>}{c.level_name && <Pill>{c.level_name}</Pill>}{f.place && <Pill>{f.place}</Pill>}{f.length && <Pill>{f.length}</Pill>}<IntlBadge c={c} /></div>
      {f.fee && <p className="fee-line"><strong>{f.fee}</strong> <span className="muted small">{primaryFeeNote(c.annual_tuition_fee)}</span></p>}
      {(entry.length > 0 || english.length > 0) && (
        <div className="er-grid">
          {entry.length > 0 && (
            <div className="er-col"><h4>Academic entry</h4>
              <ul className="d-list">{entry.map((e, n) => <li key={n}><span className="d-k">{e.kind}{e.countryName ? ` · ${e.countryName}` : ''}</span><div>{e.main || e.kind}{e.grade && <> <Pill tone="teal">{e.grade}</Pill></>}</div></li>)}</ul>
            </div>
          )}
          {english.length > 0 && (
            <div className="er-col"><h4>English</h4>
              <ul className="d-list">{english.map((e, n) => <li key={n}><strong>{e.test}</strong>{e.overall && <> <Pill tone="teal">{e.overall}</Pill></>}{e.parts && <div className="muted small">{e.parts}</div>}</li>)}</ul>
            </div>
          )}
        </div>
      )}
      {market && entry.length === 0 && <p className="muted small">Open Course details for the provider’s requirements for {marketName || 'this country'}.</p>}
      <div className="actions">
        <DetailsButton open={openId === c.course_id} id={`drawer-${c.course_id}`} onClick={() => onOpen(c)} />
        <ExtLink className="btn" href={c.official_url}>Course page ↗</ExtLink>
        <SaveButtons c={c} {...save} />
      </div>
    </article>
  )
}

export default function EntryRequirements({ access }) {
  const { studyIn, market, setMarket, markets, priority, view, setView } = usePortal()
  const [openCourse, setOpenCourse] = useState(null)
  const canSave = access.kind === 'counsellor'
  const saved = useSaved(canSave)
  const [level, setLevel] = useState('')
  const [has, setHas] = useState('')
  const [text, setText] = useState('')
  const q = useDebounced(text)
  const [levels, setLevels] = useState([])
  const [s, setS] = useState({ items: [], total: 0, page: 0, loading: true, more: false, error: '', unavailable: false })
  const [reload, setReload] = useState(0)

  useEffect(() => { let live = true; rpc('portal_study_levels_v1').then(l => { if (live && Array.isArray(l)) setLevels(l) }).catch(() => {}); return () => { live = false } }, [])

  const args = { country: studyIn || undefined, level: level || undefined, source_country: market || undefined, q: q.trim() || undefined, has: has || undefined }
  const key = JSON.stringify(args)

  const load = useCallback((page, replace, live) => rpc(FN, { p_args: { ...args, page } })
    .then(r => {
      if (!live()) return
      setS(o => ({ items: replace ? r.items : [...o.items, ...r.items], total: r.total, page: r.page, loading: false, more: false, error: '', unavailable: false }))
    })
    .catch(e => { if (live()) setS(o => ({ ...o, loading: false, more: false, error: e.message, unavailable: e.kind === 'missing' })) }),
  // eslint-disable-next-line react-hooks/exhaustive-deps
  [key])

  useEffect(() => {
    let live = true
    setS(o => ({ ...o, items: [], loading: true, error: '' }))
    load(1, true, () => live)
    return () => { live = false }
  }, [load, reload])

  const marketName = markets.find(m => m.code === market)?.name
  const saveFor = c => ({ canSave, saved: saved.ids.has(c.course_id), busy: saved.busy === c.course_id, onToggle: saved.toggle })
  const showMore = () => { setS(o => ({ ...o, more: true })); load(s.page + 1, false, () => true) }

  return (
    <div className="stack-lg">
      <PageHead title="Entry Requirements" sub="Find the academic and English entry requirements for a destination, study level, provider or course." />
      <StudyInBar />
      <section className="card filters" aria-label="Filters">
        <div className="selects">
          <Select label="Student’s country of education" value={market} onChange={setMarket}>
            <option value="">Not chosen</option>
            <MarketOptions markets={markets} priority={priority} />
          </Select>
          <Select label="Study level" value={level} onChange={setLevel}>
            <option value="">All levels</option>
            {levels.map(l => <option key={l.code} value={l.code}>{l.name}</option>)}
          </Select>
          <Select label="Requirement" value={has} onChange={setHas}>
            {HAS.map(h => <option key={h.value} value={h.value}>{h.label}</option>)}
          </Select>
          <label className="field"><span className="field-label">Provider or course</span><input aria-label="Provider or course" placeholder="Part of a provider or course name" value={text} onChange={e => setText(e.target.value)} /></label>
        </div>
        {!market && <p className="muted small">Choose the student’s country of education to see the provider’s requirement for that country. Without it, only requirements that apply to every country are shown.</p>}
      </section>
      <LoadState loading={s.loading && !s.items.length} error={s.error} unavailable={s.unavailable} onRetry={() => setReload(n => n + 1)} what="entry requirements" />
      {saved.message && <div className="notice bad" role="alert">{saved.message} <button type="button" className="link-inline" onClick={saved.clearMessage}>Dismiss</button></div>}
      {!s.loading && !s.error && (
        <>
          <div className="count-row"><Count n={s.total}>{s.total === 1 ? 'course' : 'courses'} with a recorded requirement</Count>{s.total > 0 && <ViewToggle value={view} onChange={setView} />}</div>
          {s.total === 0 && <div className="empty"><strong>No courses match.</strong><p className="muted">Clear a filter or change the destination to see more.</p></div>}
          {view === 'list' ? (
            <div className="list" role="list">
              <ListHead />
              {s.items.map(c => { const f = facts(c); return (
                <CourseRow key={c.course_id} c={c} level={c.level_name} place={f.place} length={f.length} fee={f.fee || ''} lead={<IntlBadge c={c} />}>
                  <DetailsButton open={openCourse?.course_id === c.course_id} id={`drawer-${c.course_id}`} onClick={() => setOpenCourse(c)} />
                  <ExtLink className="btn" href={c.official_url}>Course page ↗</ExtLink>
                  <SaveButtons c={c} {...saveFor(c)} />
                </CourseRow>
              ) })}
            </div>
          ) : (
            <div className="card-grid">{s.items.map(c => <EntryCard key={c.course_id} c={c} market={market} marketName={marketName} onOpen={setOpenCourse} openId={openCourse?.course_id} {...saveFor(c)} />)}</div>
          )}
          <ShowMore shown={s.items.length} total={s.total} loading={s.more} onClick={showMore} noun="courses" />
        </>
      )}
      <DetailDrawer course={openCourse ? { ...openCourse, course_url: openCourse.course_url || openCourse.official_url, level: openCourse.level_name } : null} onClose={() => setOpenCourse(null)} />
    </div>
  )
}
