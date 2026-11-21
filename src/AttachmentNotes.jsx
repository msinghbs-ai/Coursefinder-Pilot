// CF-247 s901 (Platform Admin 21 Nov 2026 07:48, chat S1-Coverage-Unlock-UI-Notes): counsellor notes on how scholarships, academic entry
// requirements (AER) and field rules attach to a course. One <details>, closed on every page load, on Course detail, Entry requirements and
// Scholarships. Words only: nothing here reads or changes data. `focus` puts that page's section first.
import React from 'react'
import './attachment-notes.css'

export const NOTES_TITLE = 'Notes · How scholarships, AER & field rules attach to courses'

const SCHOLARSHIPS = <section key="scholarships" data-notes-section="scholarships">
  <h4>Scholarships: how one reaches a course</h4>
  <ol>
    <li><strong>Named course.</strong> The scholarship page names the course (or its code), so it is linked to that course only.</li>
    <li><strong>Study level or faculty rule.</strong> The scholarship is for a study level (for example all postgraduate coursework) or a faculty or field. Every course of that university that matches is linked.</li>
    <li><strong>University-wide.</strong> The scholarship is open to students of any course at the university (for example an international merit scholarship). It is linked to every active course there.</li>
    <li><strong>Why a course can show no scholarship.</strong> A course's scholarship list shows only the links recorded for that course by rules 1 to 3. A course added after the university's last scholarship check, or whose link is waiting for review, shows none yet, even when the university offers scholarships to all students. Check the university's scholarships, or use <em>Check scholarships for this course</em>.</li>
  </ol>
</section>

const AER = <section key="aer" data-notes-section="aer">
  <h4>Entry requirements (AER): how one reaches a course</h4>
  <ul>
    <li><strong>Study destination</strong> is where the university is (Australia, New Zealand, Canada). <strong>Student's education country</strong> (Layer 4: Source country) is where the student earned their prior qualification (for example India or Nepal). Entry tables are published for each source country.</li>
    <li><strong>University-wide entry table.</strong> A row with no course applies to every course at the university for that source country, unless the course has its own requirement.</li>
    <li><strong>Which rule wins</strong>, in order: 1 a course rule; 2 a course row for the source country; 3 the course's band in the university table; 4 the university minimum; 5 otherwise, contact the university.</li>
    <li>Only <strong>active</strong> rows reach the website. A proposed row is waiting in Layer 4 Review and is not shown to students.</li>
  </ul>
</section>

const ELR = <section key="elr" data-notes-section="elr">
  <h4>English and register values: the exceptions</h4>
  <ul>
    <li><strong>English by study level.</strong> A university's central English page sets the score for each study level (for example undergraduate or postgraduate), and that score is used for its courses at that level.</li>
    <li><strong>Regulated disciplines</strong> (nursing, midwifery, medicine, allied health, teaching, law, social work) often need a higher score set by the profession. When the central page gives them higher bands, the level score is not used; a person sets the course's score in Layer 4.</li>
    <li><strong>Register values</strong> come from the official register: CRICOS in Australia, NZQA in New Zealand (for example the course code, duration and the university's identity). <strong>Page values</strong> (fees, intakes, English) are read from the university's own pages and show the page and the date they were read.</li>
    <li>A value a person has locked is never replaced by a later read.</li>
  </ul>
</section>

const ORDER = { scholarships: [SCHOLARSHIPS, AER, ELR], aer: [AER, ELR, SCHOLARSHIPS], course: [SCHOLARSHIPS, AER, ELR] }

export default function AttachmentNotes({ focus = 'course' }) {
  return <details className="an-notes" data-attachment-notes={focus}>
    <summary>{NOTES_TITLE}</summary>
    <div className="an-body">{ORDER[focus] || ORDER.course}</div>
  </details>
}
