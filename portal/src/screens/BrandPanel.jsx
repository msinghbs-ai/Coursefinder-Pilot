import React from 'react'

// The left-hand panel of the sign-in and set-password screens. Wording only: no provider, course or fee figure is quoted here,
// so it cannot go stale against the catalogue.
const POINTS = [
  { title: 'Describe the course in plain words', text: 'Type what the student wants. The portal reads it back to you as chips you can remove.' },
  { title: 'Only what we can stand behind', text: 'Providers and scholarships appear once they are published, and a missing detail says "Not recorded".' },
  { title: 'Keep a shortlist and compare', text: 'Save courses for a student and compare them side by side.' },
]

export default function BrandPanel() {
  return (
    <aside className="brand-panel" aria-label="About StudySearch Portal">
      <div className="brand-top">
        <strong className="brand-word">StudySearch</strong>
        <span className="brand-sub">StudySearch Portal</span>
      </div>
      <div className="brand-body">
        <h2>Find the right course for every student.</h2>
        <ul>
          {POINTS.map(p => (
            <li key={p.title}>
              <span className="tick" aria-hidden="true">✓</span>
              <span><strong>{p.title}</strong><br />{p.text}</span>
            </li>
          ))}
        </ul>
      </div>
      <p className="brand-foot">For Study Square counsellors and viewers. Your role comes from Users and Roles in the Admin app.</p>
    </aside>
  )
}
