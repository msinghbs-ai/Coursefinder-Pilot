// Guards: CF-210 Provider Contacts is the managed manual-record reference pattern
import{test}from'@playwright/test'  // 26 Oct 2026 (test governance): was node:test, which Playwright loaded but never counted or failed on
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

test('CF-210 core catalogue remains source-authoritative rather than a generic manual database editor',async()=>{
 const src=await read('src/mature-main.jsx')
 assert.match(src,/provider:\{operation:'providers_page',detail:'provider_detail'/)
 assert.match(src,/course:\{operation:'courses_page',detail:'course_detail'/)
 assert.match(src,/campus:\{operation:'campuses_page',detail:'campus_detail'/)
 assert.match(src,/scholarship:\{operation:'scholarships_page',detail:'scholarship_detail'/)
 assert.doesNotMatch(src,/Add Provider|Add Course|Add Campus|Create canonical Provider|Create canonical Course|Create canonical Campus/)
})
