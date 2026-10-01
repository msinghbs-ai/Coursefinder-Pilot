import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 complete coverage: every active Australian course has one state per attribute, rebuilt hourly and kept daily.
test('coverage model, schedule and governed read', () => {
  const m = fs.readFileSync('supabase/migrations/20260929100000_cf247_course_coverage_statistics.sql', 'utf8')
  for (const s of ["'admitted'", "'in_review'", "'awaiting_l3'", "'not_on_page'", "'blocked'", "'page_found'", "'site_known'", "'no_website'", "'missing_l1'"]) expect(m).toContain(s)
  for (const a of ["'official_url'", "'provider_tuition'", "'english'", "'intakes'", "'registered_tuition'", "'duration'", "'campus'"]) expect(m).toContain(a)
  expect(m).toContain("cron.schedule('course-coverage-build','47 * * * *'")
  expect(m).toContain("security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required'")
  expect(m).toContain("if p_operation in ('course_coverage','course_coverage_courses') then return security.admin_course_coverage_read(p_operation,p_args); end if;")
})

test('Course coverage is reachable from Coverage & completeness and uses the validated ordinal ramp', () => {
  const v = fs.readFileSync('src/course-coverage.jsx', 'utf8')
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  // v2.15.107: Course coverage is the first tab of Coverage & completeness, inside the app shell; the old address still opens it.
  expect(nav).toContain("{ key: 'courses', label: 'Courses', min: 1 }")
  expect(nav).toContain("{ key: 'attributes', label: 'Attributes', min: 1 }")
  expect(nav).toContain("'course-coverage': { page: 'coverage', tab: 'courses' }")
  expect(main).toContain("case'coverage':return tab==='attributes'?<CoverageAttributes rank={rank}/>:<div className=\"m-page-stack\"><CoverageView view=\"courses\"/><LinkRefresh/></div>")
  // Decision 217: the attributes view, By area and Fee schedules share the Coverage country and university
  expect(main).toContain('<CoverageView view="attributes" onScope={setScope}/><details className="m-admin-advanced cov-by-area"><summary>By area: providers, courses, campuses and scholarships</summary><DomainReadiness rank={rank}/></details>{rank>=4&&<FeeSchedules country={scope.country} provider={scope.provider}/>}')
  expect(v).toContain("adminRead('course_coverage'")
  expect(v).toContain("adminRead('course_coverage_courses'")
  expect(v).toContain("states:['candidate','in_review','awaiting_l3']")
  for (const c of ['#0d366b', '#1c5cab', '#2a78d6', '#5598e7', '#86b6ef']) expect(v).toContain(c)
})
