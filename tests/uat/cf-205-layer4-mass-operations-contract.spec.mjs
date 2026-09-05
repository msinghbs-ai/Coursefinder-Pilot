import test from'node:test'
import assert from'node:assert/strict'
import{readFile}from'node:fs/promises'

const read=p=>readFile(new URL(`../../${p}`,import.meta.url),'utf8')

test('CF-205 Layer 4 mass operations is loaded and release current',async()=>{
 const[index,entry,release]=await Promise.all([read('index.html'),read('src/layer4-mass-operations-entry.jsx'),read('src/release-currentness-entry.js')])
 assert.match(index,/layer4-mass-operations-entry\.jsx/)
 assert.match(index,/v2\.15\.65/)
 assert.match(release,/VERSION='2\.15\.65'/)
 assert.match(entry,/Layer 4 mass operations/)
 assert.match(entry,/Scholarship scope/)
 assert.match(entry,/Errors & improvements/)
 assert.match(entry,/Mass audit/)
 assert.match(entry,/layer4_scholarship_scope_preview/)
 assert.match(entry,/layer4_scholarship_scope_bulk_decide/)
 assert.match(entry,/layer4_review_bulk_decide/)
 assert.match(entry,/Pipeline Operator role is required for mass mutation/)
 assert.match(entry,/Publication remains separate/)
})

test('CF-205 replay migration keeps private tables and guarded bulk RPCs',async()=>{
 const sql=await read('supabase/migrations/20260905031200_cf_205_layer4_mass_operations_quality_workflow.sql')
 for(const token of['pipeline.layer4_mass_operations','pipeline.layer4_quality_findings','enable row level security','layer4_mass_summary','layer4_scholarship_scope_groups','layer4_scholarship_scope_preview','layer4_scholarship_scope_bulk_decide','layer4_review_groups','layer4_review_bulk_decide','layer4_quality_diagnostics','layer4_quality_finding_upsert','layer4_quality_finding_resolve','layer4_mass_operations_history'])assert.match(sql,new RegExp(token.replaceAll('.','\\.')))
 assert.match(sql,/pipeline_operator role required for mass decisions/)
 assert.match(sql,/confirmation must exactly match/)
 assert.match(sql,/structural blockers prevent bulk accept/)
 assert.match(sql,/publication_changed',false/)
 assert.match(sql,/revoke all on pipeline\.layer4_mass_operations from public, anon, authenticated/)
 assert.match(sql,/revoke all on pipeline\.layer4_quality_findings from public, anon, authenticated/)
})
