import{test,expect}from'@playwright/test'
import fs from'node:fs'

const worker=fs.readFileSync('supabase/functions/layer2-scope-discover-scheduled/index.ts','utf8')

test('CF-093 keeps UQ discovery qualification profile-scoped and preserves CRICOS detail verification',()=>{
 expect(worker).toContain('layer2-scope-discover-scheduled-v1.3.7')
 expect(worker).toContain('d.query_field')
 expect(worker).toContain('field==="course_code"')
 expect(worker).toContain('field==="canonical_title"')
 expect(worker).toContain('field==="canonical_title_normalized"')
 expect(worker).toContain('else raw=clean(`${course.course_code||""} ${course.canonical_title||course.display_title||""}`)')
 expect(worker).toContain('candidate_title_strip_prefixes')
 expect(worker).toContain('candidate_exact_title_preference')
 expect(worker).toContain('preferExact?.85:1')
 expect(worker).toContain('title_exact:x.title_exact')
 expect(worker).toContain('detail_cricos_verified')
 expect(worker).toContain('String(acquired.html||"").toUpperCase().includes(expectedCode)')
})
