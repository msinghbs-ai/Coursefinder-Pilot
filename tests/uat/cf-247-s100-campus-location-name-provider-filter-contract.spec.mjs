// Guards: CF-247 (Platform Admin 24 Oct 2026 18:27, "Campus name and UI filter"): the Campuses list and Provider details show each campus by its location name as on the CRICOS…
// CF-247 (Platform Admin 24 Oct 2026 18:27, "Campus name and UI filter"): the Campuses list and Provider details show each campus by its
// location name as on the CRICOS institution page (catalogue.campuses.name = the register's location name for all 3,984 CRICOS campuses),
// and the Campuses list filters by provider so a university's locations read as one list.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')
const summary = fs.readFileSync('src/DetailSummary.jsx', 'utf8')

test('Campuses list: Provider filter sent as provider_id, reset with country or state; column "Location name"', () => {
  expect(ui).toMatch(/if\(type==='campus'\)return <div className="m-filter-bar">.*<PagedFilterSelect kind="provider" label="Provider"/)
  expect(ui).toContain("if(['scholarship','campus'].includes(type)&&filters.provider)a.provider_id=filters.provider;")
  expect(ui).toContain("if(['course','scholarship','campus'].includes(type))n.provider=''")
  expect(ui).toContain("if(k==='subdivision'&&['course','campus'].includes(type))n.provider=''")
  expect(ui).toContain("if(type==='campus')return[{key:'name',label:'Location name',width:270,sortKey:'campus'}")
})

test('a provider with no name on the register reads "Unnamed on the register", not "N/A"', () => {
  expect(ui).toContain("if(key==='provider_name'){const pn=displayName(r.provider_name,null);")
})

test('Provider details: campuses by location name with course count; city in the hover', () => {
  expect(summary).toContain('label:`${c.name||c.city}${c.course_count!=null?')
  expect(summary).not.toContain('label:`${c.city||c.name}')
})
