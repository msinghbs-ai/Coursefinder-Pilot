// Guards: Provider Description autonomy mandate §8–11: real PostgreSQL governed workflow and negative authority boundaries.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { performance } from 'node:perf_hooks'
import { sql, quote } from './db.mjs'
import { processNext, recordLease, decideProvider } from './worker.mjs'
const fixtureRoot='tests/fixtures/provider-description-autonomy/'
const results=[],timings=[]
const pid=n=>'10000000-0000-0000-0000-'+String(n).padStart(12,'0')
const db=(s)=>sql(s,{role:'postgres'})
const json=(s)=>sql(s,{role:'postgres',json:true})
function ok(check,label){assert.ok(check,label);results.push(label);console.log('PASS '+label)}
function rpc(action,args={},rank=6){return sql(`select public.admin_provider_description_run_v1(${quote(action)},${quote(JSON.stringify(args))}::jsonb);`,{rank,json:true})}
function timed(label,fn){const start=performance.now();const result=fn();timings.push({stage:label,elapsed_ms:Math.round((performance.now()-start)*100)/100});return result}
function refuses(statement,label,{rank=6,role='authenticated',contains}={}){let failed=false;try{sql(statement,{rank,role})}catch(e){failed=true;if(contains)assert.match(String(e.stderr||e.message),contains)}ok(failed,label)}
function rollbackRefusal(prefix,statement,label,code='22023'){
 db(`begin;${prefix}select fixture.refuses(${quote(statement)},${quote(code)},${quote(label)});rollback;`);ok(true,label)
}
function cohortFor(n){const preview=rpc('preview',{provider_id:pid(n),country:n===11?'NZ':n===12?'CA':'AU',provider_type:'university',size:1,mode:'stored'});assert.equal(preview.eligible,1,JSON.stringify(preview));return rpc('prepare',{preview_token:preview.preview_token,reason:'Isolated governed provider-description cohort acceptance'})}
const allKeys=json("select value from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='pdesc.provider_keys';")
ok(rpc('capabilities',{},3).can_run===false,'real stored curator rank can inspect but cannot Run Now')
refuses("select public.admin_provider_description_run_v1('capabilities','{}');",'real Viewer role refused description workspace',{rank:2,contains:/curator role/})
refuses("select public.admin_provider_description_run_v1('prepare','{}');",'real Curator role refused cohort prepare',{rank:3,contains:/cannot prepare/})
refuses("select public.admin_provider_description_run_v1('verify','{}');",'real Curator role refused Verify and its prepared-projection repair',{rank:3,contains:/role|verify/i})
refuses("select public.svc_provider_description_next(1);",'authenticated operator cannot invoke service reader directly',{contains:/permission denied/})
refuses("select security.layer4_provider_description_apply_impl(null,null,null,'invalid');",'authenticated operator cannot bypass existing Layer 4 authority',{contains:/permission denied/})
for(const [n,reason]of[[14,'no_verified_stored_source'],[17,'manual_lock']]){const p=rpc('preview',{provider_id:pid(n),size:1,mode:'stored',filter:'all'});ok(p.providers[0].eligibility_reason===reason,reason+' is visible with exact identity and evidence')}
// Explicit isolated policy fixture: ten fictional providers only, with approved stored official evidence.
db(`update pipeline.platform_toolset_settings set value=${quote(JSON.stringify(Array.from({length:10},(_,i)=>'fixture:provider:'+(i+1))))}::jsonb where toolset_key='pipeline' and key='pdesc.provider_keys';`)
const preview=timed('ten_provider_preview',()=>rpc('preview',{country:'AU',provider_type:'university',size:10,mode:'stored'}))
ok(preview.eligible===10&&preview.providers.length===10,'bounded selector finds all ten approved fictional providers despite dominant 7000-course institution')
refuses(`select public.admin_provider_description_run_v1('prepare',${quote(JSON.stringify({preview_token:preview.preview_token,reason:'Other administrator ownership check'}))}::jsonb);`,'another actual administrator cannot fix someone else’s preview',{rank:5,contains:/unknown owned preview/})
const prepared=rpc('prepare',{preview_token:preview.preview_token,reason:'Isolated acceptance ten source-backed provider descriptions'})
ok(prepared.totals.selected===10,'server persists exact ten provider identities and pinned evidence')
const otherOwner=rpc('saved',{cohort_id:prepared.cohort_id},5)
ok(otherOwner.providers.length===0&&otherOwner.runs.length===0,'another administrator cannot read private saved cohort or run evidence')
refuses('select * from pipeline.provider_description_cohorts;','authenticated clients cannot bypass saved-cohort RLS through direct table reads',{contains:/permission denied/})
refuses(`select public.admin_provider_description_run_v1('run',${quote(JSON.stringify({cohort_id:prepared.cohort_id}))}::jsonb);`,'curator cannot execute prepared cohort',{rank:3,contains:/cannot start/})
const run=timed('governed_run_dispatch',()=>rpc('run',{cohort_id:prepared.cohort_id}))
ok(run.runs.length===1&&run.totals.admitted===0,'governed Run Now persists one registered outcome without claiming admission')
const repeat=rpc('run',{cohort_id:prepared.cohort_id})
ok(repeat.runs.length===1&&repeat.runs[0].run_id===run.runs[0].run_id,'interrupted-response recovery reuses one persisted task and immutable cohort')
const initialDispatch=json(`select body from fixture.worker_dispatches where body->>'cohort_id'=${quote(prepared.cohort_id)} order by created_at desc limit 1;`)
ok(initialDispatch?.mode==='provider_description'&&initialDispatch.cohort_id===prepared.cohort_id,'actual existing scheduler persists the fixed cohort worker dispatch body')
const processing=timed('ten_actual_worker_checks_model_transport_record',()=>{const batches=[],results=[];for(let i=0;i<10&&results.length<10;i++){
 if(i>0){
  // Simulate the next existing governed schedule window, without changing frequency or spending settings.
  db(`update pipeline.edge_request_log set created_at=now()-make_interval(mins=>security.pipeline_num_v1('pdesc.every_minutes',60)::int+1) where mode='provider_description';`)
  const nextTick=json('select security.provider_description_fire_v1();');assert.equal(nextTick.sent,1,'next governed schedule dispatches remaining saved cohort')
 }
 const batch=processNext(10,prepared.cohort_id);batches.push(batch);results.push(...batch.results);if(!batch.results.length)break
 }return {batches,results}})
ok(processing.results.length===10,'actual worker source extraction and controlled model-response parsing process ten sources')
const proposed=rpc('saved',{cohort_id:prepared.cohort_id})
ok(proposed.totals.proposed===10&&proposed.totals.human_decisions_required===10&&proposed.totals.admitted===0, 'ten supported proposals enter existing Layer 4 with zero admissions before human decisions')
ok(proposed.providers.every(p=>p.evidence_id&&p.source_hash&&p.prompt_version&&p.model&&p.sentences.every(s=>s.on_page)), 'all proposals retain evidence version, official URL, quotes, model and prompt lineage')
const pending=proposed.providers[0]
// Changing any admission authority or lineage while the proposal waits must invalidate approval.
const approveSQL=`select public.layer4_review_decide(${quote(pending.review_item_id)}::uuid,'approve','Isolated negative admission authority check',null)`
rollbackRefusal(`update catalogue.providers set lifecycle_status='retired' where id=${quote(pending.provider_id)}::uuid;`,approveSQL,'retired-after-proposal provider cannot be admitted')
rollbackRefusal(`insert into pipeline.manual_locks(entity,entity_id,field,mode) values('provider',${quote(pending.provider_id)}::uuid,'description','value');`,approveSQL,'manual lock added after proposal prevents admission')
rollbackRefusal(`insert into pipeline.provider_identity_findings(provider_id,check_code,reason) values(${quote(pending.provider_id)}::uuid,'identity_unconfirmed','Isolated conflicting institutional identity');`,approveSQL,'unresolved current identity finding prevents admission')
rollbackRefusal(`update pipeline.evidence_artifacts set content_hash='changed-after-proposal' where id=${quote(pending.evidence_id)}::uuid;`,approveSQL,'source content version drift prevents admission')
rollbackRefusal(`update catalogue.providers set website='https://unrelated.example.edu' where id=${quote(pending.provider_id)}::uuid;`,approveSQL,'changed official host prevents admission')
const lowReviewer='90000000-0000-0000-0000-000000000003'
rollbackRefusal(`set fx.uid=${quote(lowReviewer)};`,approveSQL,'actual rank-three curator cannot approve provider description','42501')
// Platform Admin 5 Nov 2026 20:03 §3: rank 4 approves provider descriptions; every route is refused at rank 3; other kinds and read-only roles keep their behaviour.
// Each psql call is its own session: a statement run after "begin;" without commit is rolled back when the session ends.
const ids=proposed.providers.slice(0,2).map(p=>p.review_item_id)
const implSQL=`select security.layer4_review_decide_impl(${quote(pending.review_item_id)}::uuid,'approve','Isolated negative admission authority check',null)`
rollbackRefusal(`set fx.uid=${quote(lowReviewer)};`,implSQL,'rank three is refused through the direct decision implementation too','42501')
const inboxSQL=`select public.admin_layer4_inbox('decide',${quote(JSON.stringify({kind:'provider_description',ref:pending.review_item_id,choice:'approve',reason:'Isolated rank check'}))}::jsonb)`
rollbackRefusal(`set fx.uid=${quote(lowReviewer)};`,inboxSQL,'rank three is refused through the Layer 4 Inbox','42501')
const batchSQL=`select security.layer4_batch_decide_v1_impl(array[${ids.map(i=>quote(i)+'::uuid').join(',')}],'approve','Isolated batch rank check','APPROVE 2','isolated')`
rollbackRefusal(`set fx.uid=${quote(lowReviewer)};`,batchSQL,'rank three is refused a batch decision','42501')
const batch6=json(`begin;set local fx.uid='90000000-0000-0000-0000-0000000000aa';${batchSQL};`)
ok(batch6.decided===0&&batch6.skipped_description===2,'a batch never admits provider descriptions, even at rank six (decided one at a time)')
const approvedAt=(uid,extra='')=>json(`begin;${extra}set local fx.uid=${quote(uid)};create temp table rank_result on commit drop as select security.current_role_rank() as rank,${approveSQL.replace(/^select /,'')} as result;select jsonb_build_object('rank',(select rank from rank_result),'result',(select result from rank_result),'description',(select description from catalogue.providers where id=${quote(pending.provider_id)}::uuid),'decision',(select action from pipeline.layer4_decisions where review_item_id=${quote(pending.review_item_id)}::uuid));`)
const at4=approvedAt('90000000-0000-0000-0000-000000000004')
ok(at4.rank===4&&at4.result.ok===true&&at4.decision==='approve'&&at4.description===at4.result.final_value.description,'rank four (Pipeline Operator) approves a provider description')
const productionRoles=`insert into security.roles(code,name,rank,status) values('pim_admin','PIM Admin',5,'active'),('viewer','Viewer',1,'active');
 insert into auth.users(id,email) values('90000000-0000-0000-0000-000000000015','isolated-role-15@example.invalid'),('90000000-0000-0000-0000-000000000011','isolated-role-11@example.invalid');
 insert into security.user_roles(user_id,role_code) values('90000000-0000-0000-0000-000000000015','pim_admin'),('90000000-0000-0000-0000-000000000011','viewer');`
const at5=approvedAt('90000000-0000-0000-0000-000000000015',productionRoles)
ok(at5.rank===5&&at5.result.ok===true&&at5.decision==='approve','rank five (PIM Admin) approves a provider description')
ok(json(`select count(*) from pipeline.layer4_decisions where review_item_id=${quote(pending.review_item_id)}::uuid;`)===0&&json(`select to_jsonb(status) from pipeline.layer4_review_items where id=${quote(pending.review_item_id)}::uuid;`)==='pending','refused and rolled-back checks leave the decision waiting for its real reviewer')
for(const [uid,label] of [['90000000-0000-0000-0000-000000000011','rank one (Viewer)'],['90000000-0000-0000-0000-000000000002','rank two']]){
 rollbackRefusal(`${productionRoles}set fx.uid=${quote(uid)};`,approveSQL,`${label} keeps no decision right, as before`,'42501')
 rollbackRefusal(`${productionRoles}set fx.uid=${quote(uid)};`,`select public.admin_layer4_inbox('summary','{}'::jsonb)`,`${label} keeps no Layer 4 Inbox access, as before`,'42501')
}
// Other Layer 4 kinds: the functions that set their rank are byte-identical before and after the migration (hashes taken in run.sh before it).
const before=JSON.parse(fs.readFileSync('uat-artifacts/provider-description-layer4-before.json','utf8'))
const after=json(`select jsonb_object_agg(sig,md5(pg_get_functiondef(sig::regprocedure))) from unnest(array[${Object.keys(before).map(quote).join(',')}]) sig;`)
for(const sig of Object.keys(before))assert.equal(after[sig],before[sig],'unchanged by the migration: '+sig)
ok(Object.keys(before).length>=7,`other Layer 4 kinds keep their rank rules: ${Object.keys(before).length} decision functions (decide, Inbox, batch, other kinds' apply) unchanged by the migration`)
const otherItem=`insert into pipeline.layer4_review_items(id,entity_type,entity_id,field_code,before_value,proposed_value,status) values('70000000-0000-0000-0000-000000000001','provider',${quote(pending.provider_id)}::uuid,`
rollbackRefusal(`${otherItem}'entry_matrix_first_run','{}','{}','pending');set fx.uid='90000000-0000-0000-0000-000000000004';`,`select public.layer4_review_decide('70000000-0000-0000-0000-000000000001'::uuid,'approve','Isolated AER rank check',null)`,'an AER kind still needs the Platform Admin: rank four refused, unchanged','42501')
const otherKind=json(`begin;insert into pipeline.layer4_review_items(id,entity_type,entity_id,field_code,before_value,proposed_value,status) values('70000000-0000-0000-0000-000000000001','scholarship',gen_random_uuid(),'scope_resolution','{}','{}','pending');set local fx.uid=${quote(lowReviewer)};select public.layer4_review_decide('70000000-0000-0000-0000-000000000001'::uuid,'reject','Isolated rank-three decision on another kind',null);`)
ok(otherKind?.ok===true&&otherKind.status==='rejected','rank three still decides another kind (scholarship scope_resolution) directly, unchanged')
const full=processNext(1,prepared.cohort_id)
ok(full.lease.reason==='review_full'&&full.results.length===0,'pending review cap parks further work without another AI call')
for(const p of proposed.providers)timed('authorised_layer4_decision_and_consumer_readback',()=>decideProvider(p.provider_id))
db(`insert into pipeline.website_sync_items(entity,item_key,ref_id,hash,seq,item) select 'provider',p.stable_key,p.id,md5('controlled stale provider description'),nextval('pipeline.website_sync_seq'),jsonb_build_object('provider_id',p.stable_key,'description','Controlled stale prepared provider description') from catalogue.providers p join pipeline.provider_description_reads r on r.provider_id=p.id where r.state='admitted' on conflict(entity,item_key) do update set item=excluded.item,hash=excluded.hash,seq=excluded.seq;`)
const stale=rpc('saved',{cohort_id:prepared.cohort_id})
ok(stale.totals.website_verified===10&&(stale.totals.zoho_verified??stale.zoho_verified)===0&&stale.providers.every(p=>p.zoho.status==='mismatch'),'real Zoho route exposes stale prepared descriptions separately from correct Website publication')
const admitted=rpc('verify',{cohort_id:prepared.cohort_id})
ok(admitted.totals.admitted===10&&admitted.totals.website_verified===10,'ten actual authorised Layer 4 decisions write catalogue and exact Website projection verifies all ten')
ok(admitted.totals.actual_ai_calls===10,'actual started model-call instrumentation distinguishes calls from leases and pre-AI holds')
// Integration Controller decision 5 Nov 2026 (item 3): this feature never writes pipeline.website_sync_items. Verify only reads back.
ok((admitted.totals.zoho_verified??admitted.zoho_verified)===0&&admitted.providers.every(p=>p.zoho.status==='mismatch'),'Verify reads back only: the stale prepared feed item is reported, not rewritten by this feature')
// The existing website-sync-check scan, copied live and md5-checked, is the only writer of the feed.
const wsync=JSON.parse(fs.readFileSync(fixtureRoot+'production-website-sync.json','utf8'))
for(const f of wsync.functions)assert.equal(json(`select to_jsonb(md5(pg_get_functiondef(${quote(f.signature)}::regprocedure)));`),f.md5,'live website sync function in the fixture: '+f.signature)
const seqBefore=json(`select coalesce(max(seq),0) from pipeline.website_sync_items where entity='provider';`)
db("update pipeline.website_sync_scan set done=(entity<>'provider'),after_key=null;") // one pass of the provider entity only; the other entities' builders are outside this fixture
const scan=json(`select ${wsync.job.command.replace(/^select /,'')};`)
const feed=json(`select jsonb_agg(jsonb_build_object('key',w.item_key,'description',w.item->>'description','expected',p.description,'seq',w.seq,'hash_ok',w.hash=md5((w.item-'generated_at'-'freshness')::text))) from pipeline.website_sync_items w join catalogue.providers p on p.stable_key=w.item_key join pipeline.provider_description_reads r on r.provider_id=p.id and r.state='admitted' where w.entity='provider';`)
ok(scan.provider.changed>=10&&feed.length===10&&feed.every(f=>f.description===f.expected&&f.seq>seqBefore&&f.hash_ok),'the existing website-sync-check scan (live, md5-checked) writes each approved description into the feed as a changed item')
const rescan=(db("update pipeline.website_sync_scan set done=(entity<>'provider'),after_key=null;"),json(`select ${wsync.job.command.replace(/^select /,'')};`))
ok(rescan.provider.changed===0,'a second scan finds nothing to change')
const published=rpc('verify',{cohort_id:prepared.cohort_id})
ok((published.totals.zoho_verified??published.zoho_verified)===10&&published.providers.every(p=>p.zoho.status==='verified')&&published.totals.website_verified===10,'after the existing scan, real Zoho and Website read-back verify all ten')
ok(json('select count(*) from pipeline.layer4_decisions;')===10,'every admission has a real existing Layer 4 decision record')
db(`update pipeline.platform_toolset_settings set value=${quote(JSON.stringify(allKeys))}::jsonb where toolset_key='pipeline' and key='pdesc.provider_keys';`)
// Persist results separately from later negative and browser scenarios.
fs.mkdirSync('docs/ui-evidence',{recursive:true})
fs.writeFileSync('docs/ui-evidence/provider-description-database-result.json',JSON.stringify({boundary:'PostgreSQL 17.6, actual SQL/worker checks; only model transport and auth JWT boundary controlled; no vendor calls',cohort:admitted,simulated_model_cost_usd:admitted.totals.cost_usd},null,2)+'\n')
fs.writeFileSync('docs/ui-evidence/provider-description-integration-results.json',JSON.stringify({passed:results.length,results,timings},null,2)+'\n')
console.log(JSON.stringify({passed:results.length,cohort:prepared.cohort_id,totals:admitted.totals}))
