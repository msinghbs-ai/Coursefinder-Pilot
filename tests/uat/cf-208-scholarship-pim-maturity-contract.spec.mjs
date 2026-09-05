import test from'node:test'
import assert from'node:assert/strict'
import{readFile}from'node:fs/promises'

const read=p=>readFile(new URL(`../../${p}`,import.meta.url),'utf8')

test('CF-208 Scholarship PIM catalogue is wired through the mature governed shell',async()=>{
 const[index,main,api]=await Promise.all([read('index.html'),read('src/mature-main.jsx'),read('src/lib/supabase.js')])
 assert.match(index,/src\/mature-main\.jsx/)
 assert.match(main,/item\('Scholarships',Sparkles,1\)/)
 assert.match(main,/if\(page==='Scholarships'\)return <ScholarshipWorkspace/)
 assert.match(main,/function ScholarshipWorkspace/)
 assert.match(main,/<Catalogue type="scholarship"/)
 assert.match(main,/scholarship:\{operation:'scholarships_page',detail:'scholarship_detail',sort:'scholarship'/)
 assert.match(api,/scholarshipPage:\s*args\s*=>\s*entityPage\('scholarships_page',args\)/)
 assert.match(api,/scholarshipDetail:\s*scholarshipId\s*=>\s*adminRead\('scholarship_detail'/)
})

test('CF-208 Scholarship PIM catalogue keeps operator search filter sort pagination and detail controls',async()=>{
 const main=await read('src/mature-main.jsx')
 assert.match(main,/if\(type==='scholarship'\)return <div className="m-filter-bar">/)
 assert.match(main,/FilterSelect label="Country"/)
 assert.match(main,/FilterSelect label="Lifecycle"/)
 assert.match(main,/FilterSelect label="Publication"/)
 assert.match(main,/query:query\|\|null,sort,direction/)
 assert.match(main,/if\(filters\.country\)a\.country_code=filters\.country/)
 assert.match(main,/if\(filters\.lifecycle\)a\.lifecycle_status=filters\.lifecycle/)
 assert.match(main,/if\(filters\.publication\)a\.publication_status=filters\.publication/)
 assert.match(main,/<DataTable rows=\{rows\}/)
 assert.match(main,/<Pager offset=\{offset\} limit=\{PAGE_SIZE\} total=\{total\}/)
 assert.match(main,/<DetailDrawer type=\{type\}/)
 assert.match(main,/localStorage\.setItem\(screenStateKey/)
})

test('CF-208 Scholarship PIM keeps publication and eligibility semantics separate',async()=>{
 const main=await read('src/mature-main.jsx')
 assert.match(main,/Structural candidate scoring only\. Student eligibility remains unresolved unless separately verified\./)
 assert.match(main,/Provider ownership alone is review-only\./)
 assert.match(main,/No Scholarship eligibility is manufactured\./)
})
