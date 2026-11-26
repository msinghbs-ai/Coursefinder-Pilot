import React, { useEffect, useRef } from 'react'
import { CourseDetails } from './CourseDetails.jsx'
import { ExtLink } from './ExtLink.jsx'
import { RegBadge } from './ui.jsx'

// s1222: Course details open in a right-hand drawer (a full-height sheet on a phone), so the list keeps its place. Escape, the close
// button or the shaded area closes it; focus moves into the drawer and back to the button that opened it.
const FOCUSABLE = 'a[href], button:not([disabled]), select:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])'

export function DetailDrawer({ course, onClose }) {
  const box = useRef(null), closer = useRef(null)
  useEffect(() => {
    if (!course) return undefined
    const opener = document.activeElement
    const overflow = document.body.style.overflow
    const y = window.scrollY  // the list keeps its place: restored when the drawer closes (a phone can reset it under the lock)
    document.body.style.overflow = 'hidden'
    closer.current?.focus({ preventScroll: true })
    const onKey = e => {
      if (e.key === 'Escape') { e.preventDefault(); onClose() }
      if (e.key === 'Tab' && box.current) {
        const f = [...box.current.querySelectorAll(FOCUSABLE)].filter(el => el.offsetParent !== null)
        if (!f.length) return
        if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f[f.length - 1].focus() }
        else if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); f[0].focus() }
      }
    }
    document.addEventListener('keydown', onKey)
    return () => { document.removeEventListener('keydown', onKey); document.body.style.overflow = overflow; window.scrollTo(0, y); if (opener && opener.focus) opener.focus({ preventScroll: true }) }
  }, [course?.course_id]) // eslint-disable-line react-hooks/exhaustive-deps
  if (!course) return null
  const titleId = `drawer-title-${course.course_id}`
  return (
    <div className="drawer-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) onClose() }}>
      <aside className="drawer" role="dialog" aria-modal="true" aria-labelledby={titleId} ref={box}>
        <header className="drawer-head">
          <div className="drawer-top">
            <div className="title-row"><h2 id={titleId}>{course.title}</h2><RegBadge r={course.regulator} /></div>
            <button type="button" className="btn drawer-close" ref={closer} onClick={onClose} aria-label="Close course details">×</button>
          </div>
          {course.provider_name && <p className="muted">{course.provider_name}</p>}
          <div className="actions"><ExtLink className="btn" href={course.course_url}>Course page ↗</ExtLink></div>
        </header>
        <div className="drawer-body">
          <CourseDetails id={`drawer-${course.course_id}`} courseId={course.course_id} />
        </div>
      </aside>
    </div>
  )
}
