import React from 'react'

// Release 1, step 1: the screen exists so the Dashboard search has somewhere to land. The plain-English search itself is wired to
// catalogue.portal_course_search_v1 (S1-Build) in the next step; until that function is live this screen says so instead of guessing.
export default function Courses({ params }) {
  const q = params.get('q') || ''
  return (
    <div className="stack-lg">
      <h1>Courses</h1>
      {q && <p>You searched for: <strong>{q}</strong></p>}
      <p className="notice">Course search opens in the next release of the portal. Nothing is searched yet.</p>
    </div>
  )
}
