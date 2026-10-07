import{test,expect}from'@playwright/test'
import fs from'node:fs'
const source=()=>fs.readFileSync('src/ComparisonWorkspace.jsx','utf8')
// 7 Oct 2026: rewritten to the current Compare screen (one dataset control per ranking with its own Edition selector).
test('independent ranking edition selectors include multi-year',()=>{const s=source();expect(s).toContain('selectorLabel="Edition" value={rankingSelection.qs}');expect(s).toContain('selectorLabel="Edition" value={rankingSelection.the}');expect((s.match(/\{value:'multi',label:'Multi-year'\}/g)||[]).length).toBe(2);expect(s).toContain("rankingSelection.qs==='multi'");expect(s).toContain("rankingSelection.the==='multi'")})
test('shared snapshot trend controls are removed',()=>{const s=source();expect(s).not.toContain('Current snapshot');expect(s).not.toContain('Multi-year trend');expect(s).not.toContain('setViewMode');expect(s).toContain('selectorLabel=\"Year\" value={year}')})
test('provider identity headers are explicitly sticky',()=>{const s=source();expect(s).toContain('cf-university-sticky');expect(s).toContain("style={{position:'sticky',top:0,zIndex:8,background:'var(--cf-white)'}}")})
