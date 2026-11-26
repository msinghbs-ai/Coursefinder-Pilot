import React, { useEffect, useState } from 'react'
import { useSaved } from '../lib/saved.js'
import { basket } from '../lib/basket.js'
import { durationText, durationInYears, money, dateText, initials, placeText, NOT_RECORDED } from '../lib/format.js'
import { PageHead, StudyInBar, LoadState, Pill, ViewToggle, RegBadge, ProviderLine } from '../components/ui.jsx'
import { usePortal } from '../lib/portal.jsx'
import { lengthOrBlank, primaryFeeAmount, primaryFeeNote } from '../lib/courseDetailFormat.js'
import { CourseRow, ListHead } from '../components/CourseRow.jsx'
import { DetailDrawer } from '../components/DetailDrawer.jsx'
import { ExtLink } from '../components/ExtLink.jsx'
import { DetailsButton } from '../components/CourseDetails.jsx'

const DELIVERY = { on_campus: 'On campus', online: 'Online', blended: 'Blended', on_campus_and_online: 'On campus and online' }

// s1222: the one annual tuition fee (portal.primary_fee_v1) where the list returns it, otherwise the stored fee.
const feeOf = c => (c.primary_fee && Number(c.primary_fee.per_year) ? c.primary_fee : c.fee)

function feeCells(c) {
  const f = feeOf(c)
  if (!f || !Number(f.per_year)) return { year: [NOT_RECORDED, 'Ask the provider'], total: [NOT_RECORDED, null] }
  const per = money(f.per_year, f.currency)
  const years = durationInYears(c.duration_value, c.duration_unit)
  const total = years ? money(Math.round(Number(f.per_year) * years), f.currency) : null
  return {
    year: [per, f.year ? `per year · ${f.year} fee` : 'per year'],
    total: total ? [`about ${total}`, `${durationText(c.duration_value, c.duration_unit)} at ${per}`] : [NOT_RECORDED, 'Duration not recorded'],
  }
}

export default function Saved() {
  const saved = useSaved(true)
  const [picked, setPicked] = useState([])
  const [openCourse, setOpenCourse] = useState(null)
  const { view, setView } = usePortal()
  const max = saved.compareMax || 0
  useEffect(() => { setPicked(p => p.filter(id => saved.ids.has(id))) }, [saved.items]) // eslint-disable-line react-hooks/exhaustive-deps

  const chosen = saved.items.filter(i => picked.includes(i.course_id))
  const startProposal = () => { basket.addMany(chosen.length ? chosen : saved.items); location.hash = '#/proposals/new' }
  const flip = id => setPicked(p => p.includes(id) ? p.filter(x => x !== id) : p.length >= max ? p : [...p, id])
  const fees = chosen.map(c => Number(feeOf(c)?.per_year)).filter(n => n > 0)
  const lowest = fees.length > 1 ? Math.min(...fees) : null

  const tick = c => (
    <label className="check"><input type="checkbox" checked={picked.includes(c.course_id)} disabled={!picked.includes(c.course_id) && picked.length >= max} onChange={() => flip(c.course_id)} /><span className="sr">Compare {c.title}</span></label>
  )
  const actions = c => (
    <>
      <DetailsButton open={openCourse?.course_id === c.course_id} id={`drawer-${c.course_id}`} onClick={() => setOpenCourse(c)} />
      <ExtLink className="btn" href={c.course_url}>Course page ↗</ExtLink>
      <button type="button" className="btn" disabled={saved.busy === c.course_id} onClick={() => saved.toggle(c.course_id, false)}>Remove</button>
    </>
  )

  const rows = [
    ['Tuition per year', c => { const [a, b] = feeCells(c).year; return <><strong>{a}</strong>{lowest && Number(feeOf(c)?.per_year) === lowest && <Pill tone="green">Lowest per year</Pill>}{b && <small>{b}</small>}</> }],
    ['Total course cost', c => { const [a, b] = feeCells(c).total; return <><strong>{a}</strong>{b && <small>{b}</small>}</> }],
    ['Duration', c => <strong>{durationText(c.duration_value, c.duration_unit)}</strong>],
    ['Level', c => <strong>{c.level || NOT_RECORDED}</strong>],
    ['Delivery', c => <strong>{DELIVERY[c.delivery_mode] || NOT_RECORDED}</strong>],
    ['State and campus', c => <strong>{placeText(c) || NOT_RECORDED}</strong>],
    ['Next intake', c => c.next_intake ? <><strong>{c.next_intake.label || dateText(c.next_intake.start_date, 'day') || NOT_RECORDED}</strong>{c.next_intake.start_date && c.next_intake.label && <small>Starts {dateText(c.next_intake.start_date, 'day')}</small>}</> : <><strong>{NOT_RECORDED}</strong><small>No open intake on file</small></>],
    ['Last checked', c => <strong>{dateText(c.last_verified_at) || NOT_RECORDED}</strong>],
  ]

  return (
    <div className="stack-lg">
      <PageHead title="Saved courses" sub={max ? `Compare up to ${max} saved courses side by side.` : 'Your shortlist.'} />
      <StudyInBar />
      <LoadState loading={saved.loading} error={saved.error} onRetry={saved.refresh} what="your saved courses" />
      {saved.message && <div className="notice bad" role="alert">{saved.message} <button type="button" className="link-inline" onClick={saved.clearMessage}>Dismiss</button></div>}
      {!saved.loading && !saved.error && (
        <>
          <p className="count"><strong>{saved.items.length}</strong> saved{saved.savedMax ? ` of up to ${saved.savedMax}` : ''}</p>
          {saved.items.length === 0 && (
            <div className="empty"><strong>Nothing saved yet.</strong><p className="muted">Save a course from the Courses screen and it will be listed here, ready to compare.</p><a className="btn primary" href="#/courses">Find a course</a></div>
          )}
          {saved.items.length > 0 && <div className="count-row"><span /><ViewToggle value={view} onChange={setView} /></div>}
          {view === 'list' ? (
            <div className="list" role="list">
              <ListHead />
              {saved.items.map(c => (
                <CourseRow key={c.course_id} c={c} level={c.level} place={placeText(c)} length={lengthOrBlank(c.duration_value, c.duration_unit)}
                  fee={primaryFeeAmount(feeOf(c)) || ''} lead={tick(c)}>
                  {actions(c)}
                </CourseRow>
              ))}
            </div>
          ) : (
            <div className="card-grid">
              {saved.items.map(c => (
                <article key={c.course_id} className="card course saved-card">
                  <header className="course-head">
                    <div className="saved-row">
                      {tick(c)}
                      <span className="logo-tile" aria-hidden="true">{initials(c.provider_name)}</span>
                      <div className="saved-main">
                        <div className="title-row"><h3>{c.title}</h3><RegBadge r={c.regulator} /></div>
                        <ProviderLine name={c.provider_name} />
                      </div>
                    </div>
                  </header>
                  <div className="tags">
                    {!c.active && <Pill tone="amber">No longer offered</Pill>}
                    {c.active && !c.published && <Pill tone="amber">Not published</Pill>}
                    {c.level && <Pill>{c.level}</Pill>}
                    {placeText(c) && <Pill>{placeText(c)}</Pill>}
                    {lengthOrBlank(c.duration_value, c.duration_unit) && <Pill>{lengthOrBlank(c.duration_value, c.duration_unit)}</Pill>}
                  </div>
                  {primaryFeeAmount(feeOf(c)) && <p className="fee-line"><strong>{primaryFeeAmount(feeOf(c))}</strong> <span className="muted small">{primaryFeeNote(feeOf(c))}</span></p>}
                  <div className="actions">{actions(c)}</div>
                </article>
              ))}
            </div>
          )}
          {saved.items.length > 1 && <p className="muted small">Tick up to {max} courses to compare them.</p>}
          {saved.items.length > 0 && <div className="actions"><button type="button" className="btn primary" onClick={startProposal}>{chosen.length ? `Create a proposal from the ${chosen.length} ticked` : 'Create a proposal from my saved courses'}</button></div>}
          {chosen.length > 0 && (
            <>
              <p className="count">Comparing <strong>{chosen.length}</strong> of {max}</p>
              <div className="table-wrap">
                <table className="compare">
                  <thead><tr><th scope="col" className="corner">Compare</th>{chosen.map(c => <th scope="col" key={c.course_id}><span className="logo-tile sm" aria-hidden="true">{initials(c.provider_name)}</span><span>{c.title}<small>{c.provider_name}</small></span></th>)}</tr></thead>
                  <tbody>{rows.map(([label, cell]) => <tr key={label}><th scope="row">{label}</th>{chosen.map(c => <td key={c.course_id}>{cell(c)}</td>)}</tr>)}</tbody>
                </table>
              </div>
              <p className="muted small">“Not recorded” means we have not captured it yet. The total is the yearly fee over the course length and is marked “about”. Entry requirements, English scores and scholarships join the comparison with the student profile in the next release.</p>
            </>
          )}
        </>
      )}
      <DetailDrawer course={openCourse} onClose={() => setOpenCourse(null)} />
    </div>
  )
}
