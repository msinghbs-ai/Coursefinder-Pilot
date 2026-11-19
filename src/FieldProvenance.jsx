// CF-247 s812: the lock pills for the detail drawers. Curator and above read the record's locks once when the drawer opens.
import React, { useEffect, useState } from 'react'
import { fieldProvenanceApi } from './field-provenance-api'
import { COURSE_TRACKED_FIELDS, COURSE_FIELD_WORDS, COURSE_LOCK_COLUMNS, lockFor, otherLocked, lockWord, lockTitle } from './field-provenance'
import './completeness-bar.css'

export function useFieldLocks(entity, id, enabled) {
  const [state, setState] = useState({ locks: null, error: '' })
  useEffect(() => {
    if (!enabled || !id) { setState({ locks: null, error: '' }); return undefined }
    let live = true
    fieldProvenanceApi.read(entity, id).then(r => live && setState({ locks: r.locks || {}, error: '' })).catch(e => live && setState({ locks: null, error: e?.message || 'The locks could not be read.' }))
    return () => { live = false }
  }, [entity, id, enabled])
  return state
}

export function LockPill({ lock }) {
  if (!lock) return null
  return <span className="cprov cprov-locked" data-provenance="locked" title={lockTitle(lock)}>{lockWord(lock)}</span>
}

// Courses: one row per tracked field, Human Locked where a person has locked it
export default function FieldProvenancePanel({ entity = 'course', id, rank = 0 }) {
  const { locks, error } = useFieldLocks(entity, id, Number(rank) >= 3)
  if (Number(rank) < 3 || !id) return null
  if (error) return <section className="cprov-panel" data-field-locks-panel><h4>Locks by hand</h4><p className="cprov-note">The locks could not be read: {error}</p></section>
  if (!locks) return null
  const others = otherLocked(locks, COURSE_LOCK_COLUMNS)
  return <section className="cprov-panel" data-field-locks-panel aria-label="Fields of this course locked by hand">
    <h4>Locks by hand</h4>
    <ul className="cprov-list">
      {COURSE_TRACKED_FIELDS.map(f => { const l = lockFor(locks, COURSE_LOCK_COLUMNS[f])
        return <li key={f} data-prov-field={f}><span>{COURSE_FIELD_WORDS[f]}</span>{l ? <LockPill lock={l} /> : <span className="cprov-held">Not locked</span>}</li> })}
    </ul>
    {others.length > 0 && <p className="cprov-note" data-other-locks>Also locked by hand: {others.join(', ')}.</p>}
    <p className="cprov-note">A locked field is not changed by automation. The source of each course field is not recorded per field yet; only the description tells where it came from (Register, AI verified or Human input).</p>
  </section>
}
