import React from 'react'
import { RegBadge, ProviderLine } from './ui.jsx'

// s1222: the compact List view row, shared by Courses, Saved courses and Entry Requirements. Only values the platform holds are shown;
// "Not recorded" stays inside Course details.
export const ListHead = ({ extra }) => (
  <div className="list-row list-head" aria-hidden="true">
    <span>Course</span><span>Level</span><span>Location</span><span>Length</span><span>{extra || 'Tuition per year'}</span><span />
  </div>
)

export function CourseRow({ c, level, place, length, fee, children, lead }) {
  return (
    <div className="list-row" role="listitem">
      <div className="lr-main">
        {lead}
        <div>
          <div className="title-row"><strong className="lr-title">{c.title}</strong><RegBadge r={c.regulator} /></div>
          <ProviderLine name={c.provider_name} as="span" className="muted small" />
        </div>
      </div>
      <span className="lr-cell" data-k="Level">{level || ''}</span>
      <span className="lr-cell" data-k="Location">{place || ''}</span>
      <span className="lr-cell" data-k="Length">{length || ''}</span>
      <span className="lr-cell" data-k="Tuition per year">{fee || ''}</span>
      <div className="actions lr-actions">{children}</div>
    </div>
  )
}
