// v1.1 Counsellor UI, Guide (screen 4c). Words only: no figure, version or coverage count is typed here (the screens show the live numbers).
const STEPS = [
  ['Find courses', 'Open Courses, search by course, code or provider, and narrow by country and study level. Each row shows where the course runs (state and campus names), its level, delivery, duration and tuition, and how many of ten key facts are held.'],
  ['Save and compare', 'Select ♡ on a course to save it. Open Saved, pick up to four saved courses and choose Compare selected. The comparison shows tuition, duration, state and campus, intakes with exact start dates, entry requirements, English scores and scholarships side by side. Saved courses stay in this browser until you remove them.'],
  ['Read the location', 'Locations are shown as the state, then the campus or city names, for example "VIC · Bundoora, City". If a course has more campuses than fit, the rest are counted as "+N more" and listed when you hover.'],
  ['Study Square status', 'Each provider shows whether Study Square represents it: Represented, Direct, Not Represented or Not recorded. Not recorded means Study Square has not entered a status yet; it does not mean Not Represented. A market note, such as "Only IN, NP", means the status applies only to students from those countries.'],
  ['Provider contacts', 'The Contacts tab lists Study Square partner contacts. If it says none are recorded, none are held for that provider. University staff contacts are never collected from websites.'],
  ['Scholarships', 'Open Scholarships to see published scholarships. Open, Closed and Opens later are worked out on the Melbourne date, so they match what a student sees today. Dates not published means the provider has not given them.'],
  ['When something looks wrong', 'Use the details on the screen (the course or provider name and what you expected) when you tell the data team. Please do not rely on a blank field to mean a course does not offer something: it can mean the provider has not published it.'],
]
export default function GuideView() {
  return <>
    <div className="ui-page-head"><h1 className="ui-page-title">Guide</h1><span className="ui-page-sub">How to use StudySearch as a counsellor.</span></div>
    <section className="ui-card"><ol className="ui-list">{STEPS.map(([t, b]) => <li key={t}><strong>{t}</strong><p className="ui-note">{b}</p></li>)}</ol></section>
  </>
}
