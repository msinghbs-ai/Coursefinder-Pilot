import test from'node:test'
import assert from'node:assert/strict'
import{readFile}from'node:fs/promises'

const read=p=>readFile(new URL(`../../${p}`,import.meta.url),'utf8')

test('CF-211 H5 source-backed candidates cannot directly write canonical or publish',async()=>{
 const sql=await read('supabase/migrations/20260905073000_cf_211_h5_h6_candidate_publication_controls.sql')
 assert.match(sql,/pipeline\.pim_source_candidates/)
 assert.match(sql,/PIM Operator role required/)
 assert.match(sql,/source URL or Evidence required/)
 assert.match(sql,/target Provider required/)
 assert.match(sql,/canonical_written',false/)
 assert.match(sql,/published',false/)
 assert.doesNotMatch(sql,/insert into catalogue\.(providers|courses|campuses|scholarships)/i)
})

test('CF-211 H5 operator workspace states candidate boundary clearly and resolves operator context',async()=>{
 const src=await read('src/ManualPimCandidateWorkspace.jsx')
 assert.match(src,/Add source-backed candidate/)
 assert.match(src,/never writes canonical catalogue tables or publishes records/)
 assert.match(src,/manual_pim_candidate_register/)
 assert.match(src,/manual_pim_candidate_decide/)
 assert.match(src,/Ready for acquisition/)
 assert.match(src,/api\.context\(\)/)
 assert.match(src,/initialProviderId/)
})

test('CF-211 H5 is exposed from the existing canonical Layer 4 detail surface',async()=>{
 const src=await read('src/Layer4Intervention.jsx')
 assert.match(src,/ManualPimCandidateWorkspace/)
 assert.match(src,/Source-backed PIM candidate workflow/)
 assert.match(src,/Open candidate workspace/)
 assert.match(src,/initialEntityType=\{type\}/)
 assert.match(src,/initialProviderId=\{providerContext\}/)
 assert.doesNotMatch(src,/floating|launcher/i)
})

test('CF-211 public browser RPCs are invoker wrappers over private implementations',async()=>{
 const sql=await read('supabase/migrations/20260905074000_cf_211_h5_h6_private_impl_wrappers.sql')
 assert.match(sql,/create schema if not exists pim_api/)
 assert.match(sql,/set schema pim_api/)
 assert.match(sql,/set schema l4_api/)
 assert.match(sql,/language sql security invoker/g)
 assert.match(sql,/revoke all on function public\.manual_pim_candidate_register[\s\S]*from public,anon/)
 assert.match(sql,/revoke all on function public\.publication_control_execute[\s\S]*from public,anon/)
})

test('CF-211 H5 Evidence FK has a covering review index',async()=>{
 const sql=await read('supabase/migrations/20260905075000_cf_211_h5_candidate_evidence_index.sql')
 assert.match(sql,/pim_source_candidates_evidence_idx/)
 assert.match(sql,/pim_source_candidates\(evidence_id\)/)
})

test('CF-211 H6 publication requires preview token and remains non-cutover',async()=>{
 const sql=await read('supabase/migrations/20260905073000_cf_211_h5_h6_candidate_publication_controls.sql')
 assert.match(sql,/publication_control_preview/)
 assert.match(sql,/publication_control_execute/)
 assert.match(sql,/preview confirmation token mismatch/)
 assert.match(sql,/publication cohort exceeds 100 records/)
 assert.match(sql,/auto_publication_enabled boolean not null default false/)
 assert.match(sql,/consumer_cutover_authorised',false/)
})

test('CF-211 detail publication control uses target-scoped preview execute rollback',async()=>{
 const src=await read('src/Layer4Intervention.jsx')
 assert.match(src,/publication_control_preview/)
 assert.match(src,/publication_control_execute/)
 assert.match(src,/Search \/ API/)
 assert.match(src,/Website/)
 assert.match(src,/Zoho/)
 assert.match(src,/Preview & rollback/)
 assert.match(src,/Automatic publication is disabled/)
})
