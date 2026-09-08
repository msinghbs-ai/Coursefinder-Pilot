import{test,expect}from'@playwright/test'
import fs from'node:fs'
const source=()=>fs.readFileSync('src/ComparisonWorkspace.jsx','utf8')
test('independent ranking edition selectors include multi-year',()=>{const s=source();expect(s).toContain('aria-label=\"QS ranking edition\"');expect(s).toContain('aria-label=\"THE ranking edition\"');expect((s.match(/<option value=\"multi\">Multi-year<\/option>/g)||[]).length).toBe(2);expect(s).toContain("rankingSelection.qs==='multi'");expect(s).toContain("rankingSelection.the==='multi'")})
test('shared snapshot trend controls are removed',()=>{const s=source();expect(s).not.toContain('Current snapshot');expect(s).not.toContain('Multi-year trend');expect(s).not.toContain('setViewMode');expect(s).toContain('aria-label=\"QILT comparison year\"')})
test('provider identity headers are explicitly sticky',()=>{const s=source();expect(s).toContain('cf-university-sticky');expect(s).toContain("style={{position:'sticky',top:0,zIndex:8,background:'#fff'}}")})
