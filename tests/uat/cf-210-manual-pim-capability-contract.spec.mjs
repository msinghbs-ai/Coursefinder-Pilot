import test from'node:test'
import assert from'node:assert/strict'
import{readFile}from'node:fs/promises'

const read=p=>readFile(new URL(`../../${p}`,import.meta.url),'utf8')

test('CF-210 Provider Contacts is the managed manual-record reference pattern',async()=>{
 const src=await read('src/ProviderContactsWorkspace.jsx')
 assert.match(src,/rank>=5/)
 assert.match(src,/Add contact/)
 assert.match(src,/providerContactManage\(isNew\?'create':'update'/)
 assert.match(src,/Official source URL/)
 assert.match(src,/Change reason \*/)
 assert.match(src,/Version/)
 assert.match(src,/audit/)
 assert.match(src,/Restore/)
 assert.match(src,/Delete/)
})

test('CF-210 governed operational reference records retain sourced manual registration',async()=>{
 const src=await read('src/m2-3-intelligence-entry.jsx')
 assert.match(src,/Register governed link/)
 assert.match(src,/important_link_upsert/)
 assert.match(src,/Register sourced event/)
 assert.match(src,/important_date_upsert_v2/)
 assert.match(src,/Vague wording is retained as vague/)
})

test('CF-210 core catalogue remains source-authoritative rather than a generic manual database editor',async()=>{
 const src=await read('src/mature-main.jsx')
 assert.match(src,/provider:\{operation:'providers_page',detail:'provider_detail'/)
 assert.match(src,/course:\{operation:'courses_page',detail:'course_detail'/)
 assert.match(src,/campus:\{operation:'campuses_page',detail:'campus_detail'/)
 assert.match(src,/scholarship:\{operation:'scholarships_page',detail:'scholarship_detail'/)
 assert.doesNotMatch(src,/Add Provider|Add Course|Add Campus|Create canonical Provider|Create canonical Course|Create canonical Campus/)
})
