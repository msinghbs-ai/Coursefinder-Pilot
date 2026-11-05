// Guards: Provider Description autonomy mandate §4/7–11: refusals, automatic continuation and truthful publication.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { sql, quote } from './db.mjs'
import { processNext, recordLease, decideProvider } from './worker.mjs'
import { descriptionSourceIdentity, descriptionPageText } from '../../../supabase/functions/coverage-sweep/description.ts'
const results=[];const pid=n=>'10000000-0000-0000-0000-'+String(n).padStart(12,'0')
const db=s=>sql(s,{role:'postgres'}), j=s=>sql(s,{role:'postgres',json:true})
const rpc=(a,p={})=>sql(`select public.admin_provider_description_run_v1(${quote(a)},${quote(JSON.stringify(p))}::jsonb);`,{json:true})
const ok=(v,label)=>{assert.ok(v,label);results.push(label);console.log('PASS '+label)}
const scalar=s=>Number(db(s))
const keys=j("select value from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='pdesc.provider_keys';")
function scope(ns){db(`update pipeline.platform_toolset_settings set value=${quote(JSON.stringify(ns.map(n=>'fixture:provider:'+n)))}::jsonb where toolset_key='pipeline' and key='pdesc.provider_keys';`)}
function prepare(n){const p=rpc('preview',{country:n===11?'NZ':n===12?'CA':'AU',provider_id:pid(n),provider_type:'university',size:1,mode:'stored'});assert.equal(p.eligible,1,JSON.stringify(p));return rpc('prepare',{preview_token:p.preview_token,reason:'Isolated negative and automatic-continuation acceptance'})}
const staleAllowed=j(`begin;update pipeline.provider_description_reads set last_verified_at=now()-interval '181 days',updated_at=now()-interval '181 days' where provider_id=${quote(pid(1))}::uuid and state='admitted';select security.provider_description_selection_v1(jsonb_build_object('provider_id',${quote(pid(1))},'size',1,'filter','stale','mode','stored'));rollback;`)
ok(staleAllowed.eligible===1,'stale reader-owned descriptions become eligible through governed recheck age without modifying a manual value')
const invalidStored=j(`begin;update pipeline.provider_description_reads set proposal=jsonb_set(proposal,'{sentences,0,text}','"Incomplete institutional description fragment"') where provider_id=${quote(pid(1))}::uuid and state='admitted';select security.provider_description_selection_v1(jsonb_build_object('provider_id',${quote(pid(1))},'size',1,'filter','stale','mode','stored'));rollback;`)
ok(invalidStored.eligible===0&&invalidStored.providers[0].eligibility_reason==='invalid_description_unchanged_evidence','invalid retained claim evidence is detected and unchanged unsuitable evidence is parked')
scope([11,12])
const nz=prepare(11),ca=prepare(12)
rpc('run',{cohort_id:ca.cohort_id});rpc('run',{cohort_id:nz.cohort_id})
const caRow=rpc('saved',{cohort_id:ca.cohort_id}).providers[0]
const docs=j(`select to_jsonb(d) from fixture.documents d where provider_id=${quote(pid(12))}::uuid;`)
// Real source version drift between Run Now and lease must not produce a replacement source read.
const changed=j(`begin;update pipeline.evidence_artifacts set content_hash='changed-before-lease' where id=${quote(docs.evidence_id)}::uuid;select public.svc_provider_description_cohort_next(1,${quote(ca.cohort_id)}::uuid);rollback;`)
ok(changed.items.length===0,'pinned source hash drift between saved Run Now and lease refuses changed evidence')
// Validation 5 Nov 2026: a worker from before this release leases with svc_provider_description_next directly and never reserves.
// It must receive no item, so it cannot make an unreserved paid AI call against the new database.
const readingBefore=j(`select count(*) from pipeline.provider_description_reads where state='reading';`)
const oldWorker=sql(`select public.svc_provider_description_next(5);`,{role:'service_role',json:true})
const noProtocol=sql(`select public.svc_provider_description_lease_v1(5,null,'provider-description-v0');`,{role:'service_role',json:true})
ok(oldWorker.reason==='worker_protocol_required'&&oldWorker.items.length===0&&noProtocol.reason==='worker_protocol_required'&&noProtocol.items.length===0&&j(`select count(*) from pipeline.provider_description_reads where state='reading';`)===readingBefore,'a pre-release worker (no reservation protocol) is leased nothing, so it cannot make a paid AI call')
// A completely exhausted existing budget blocks work; it is never reset or raised.
const exhausted=j(`begin;insert into pipeline.ai_spend_ledger(lane,source,source_id,cost_usd) values('provider_description','fixture-budget','isolated',1);select public.svc_provider_description_cohort_next(1,${quote(ca.cohort_id)}::uuid);rollback;`)
ok(exhausted.items.length===0&&['ai_refused','ai_ceiling'].includes(exhausted.reason),'lifetime or daily AI budget exhausted refuses reader lease')
db("update pipeline.platform_toolset_settings set value='1'::jsonb where toolset_key='pipeline' and key='pdesc.pending_max';")
const caLease=sql(`select public.svc_provider_description_cohort_next(1,${quote(ca.cohort_id)}::uuid);`,{role:'service_role',json:true})
ok(caLease.items.length===1&&caLease.items[0].provider_id===pid(12)&&!caLease.acquire_direct&&!caLease.acquire_firecrawl,'CA uses the same existing engine with exact cohort and stored-evidence-only flags')
const nzBlocked=sql(`select public.svc_provider_description_cohort_next(1,${quote(nz.cohort_id)}::uuid);`,{role:'service_role',json:true})
ok(nzBlocked.items.length===0&&nzBlocked.reason==='review_full','in-flight reading counts towards pending cap across independent cohorts')
const readId=caLease.items[0].item_id
const validAnswer=structuredClone(docs.model_answer);for(const sentence of validAnswer.sentences)sentence.on_page=true
const receipt=descriptionSourceIdentity(docs.html,descriptionPageText(docs.html,caLease.page_chars),caLease.items[0].identity_names)
const missingReceipt=j(`begin;select public.svc_provider_description_record(${quote(JSON.stringify([{item_id:readId,stored_evidence_id:docs.evidence_id,answer:validAnswer,cost:0,cost_known:true}]))}::jsonb);select jsonb_build_object('state',state,'rule',rule,'review_item_id',review_item_id) from pipeline.provider_description_reads where id=${quote(readId)}::uuid;rollback;`)
ok(missingReceipt.state==='held'&&missingReceipt.rule==='source_identity_proof_missing'&&!missingReceipt.review_item_id,'otherwise supported payload without a current worker identity receipt cannot create a proposal')
const humanEdited=j(`begin;update catalogue.providers set description='A curator entered this manual description while the worker was reading.' where id=${quote(pid(12))}::uuid;
 select public.svc_provider_description_record(${quote(JSON.stringify([{item_id:readId,stored_evidence_id:docs.evidence_id,answer:validAnswer,cost:0,cost_known:true,identity_check:receipt}]))}::jsonb);
 select jsonb_build_object('state',r.state,'rule',r.rule,'description',p.description) from pipeline.provider_description_reads r join catalogue.providers p on p.id=r.provider_id where r.id=${quote(readId)}::uuid;rollback;`)
ok(humanEdited.state==='held'&&humanEdited.rule==='description_changed_after_lease'&&humanEdited.description.includes('curator entered'),'a manual description entered during an in-flight read is preserved before proposal')
const reservations=j(`begin;select public.svc_provider_description_reserve_v1(${quote(readId)}::uuid,'fixture/pinned-model',0.0002,${quote(caLease.items[0].stored.content_hash)});select jsonb_build_object('duplicate',public.svc_provider_description_reserve_v1(${quote(readId)}::uuid,'fixture/pinned-model',0.0002,${quote(caLease.items[0].stored.content_hash)}),'wrong_model',public.svc_provider_description_reserve_v1(${quote(readId)}::uuid,'unapproved/model',0.0002,${quote(caLease.items[0].stored.content_hash)}));rollback;`)
ok(!reservations.duplicate.ok&&reservations.duplicate.reason==='existing_cost_reservation_uncertain'&&!reservations.wrong_model.ok,'duplicate or unapproved model reservations cannot create paid duplicate work')
const tooCostly=j(`select public.svc_provider_description_reserve_v1(${quote(readId)}::uuid,'fixture/pinned-model',1,${quote(caLease.items[0].stored.content_hash)});`)
ok(!tooCostly.ok&&tooCostly.reason==='ai_ceiling','quoted per-call cost exceeding remaining lifetime ceiling is refused before model call')
const uncertain=j(`begin;select public.svc_provider_description_reserve_v1(${quote(readId)}::uuid,'fixture/pinned-model',0.0002,${quote(caLease.items[0].stored.content_hash)});select public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id',${quote(readId)},'retry',true,'error','Controlled model transport interrupted after dispatch','cost',0,'cost_known',false,'ai_call_started',true)));select jsonb_build_object('reserved',(select reserved_usd from pipeline.provider_description_reads where id=${quote(readId)}::uuid),'retry_reservation',public.svc_provider_description_reserve_v1(${quote(readId)}::uuid,'fixture/pinned-model',0.0002,${quote(caLease.items[0].stored.content_hash)}));rollback;`)
ok(uncertain.reserved>0&&!uncertain.retry_reservation.ok,'interrupted unknown model charges retain reservation and cannot be assumed free')
const badAnswer=structuredClone(docs.model_answer);badAnswer.sentences[0].text+=' The institution has 999 science laboratories.'
for(const s of badAnswer.sentences)s.on_page=true
const validation=j(`select security.provider_description_validate_v1(${quote(pid(12))}::uuid,'https://p12.example.edu/about',now(),${quote(JSON.stringify(badAnswer))}::jsonb);`)
ok(!validation.ok&&validation.outcome!=='propose','unsupported factual numeric claim is refused by actual database validation')
// Review-cap race: a different producer fills the one free review slot after this worker leases.
const race=j(`insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,proposed_value,status) values('provider',${quote(pid(1))}::uuid,'provider_description',(select evidence_id from fixture.documents where provider_id=${quote(pid(1))}::uuid),'{}','pending') returning jsonb_build_object('id',id);`)
const processed=recordLease(caLease)
const parked=rpc('saved',{cohort_id:ca.cohort_id})
ok(parked.providers[0].state==='held'&&parked.providers[0].rule==='review_full'&&parked.totals.layer4_created===0,'capacity race parks validated proposal without creating an uncontrolled Layer 4 item')
const spent=scalar("select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description';")
const duplicated=sql(`select public.svc_provider_description_record(${quote(JSON.stringify(processed.results))}::jsonb);`,{role:'service_role',json:true})
ok(duplicated.stale===1&&scalar("select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description';")===spent,'duplicate worker completion neither charges cost twice nor duplicates Layer 4 work')
const explanation=rpc('diagnose',{cohort_id:ca.cohort_id,provider_id:pid(12),reason:'Explain the held source-backed description evidence'})
ok(explanation.ai_used===false&&rpc('saved',{cohort_id:ca.cohort_id}).providers[0].diagnosis,'stored evidence explanation is permission checked, audited and survives refresh without unapproved AI spend')
// Existing authorised AI advice route must reuse a recorded issue and exact evidence; it cannot authorise admission.
const diagnosisArgs={cohort_id:ca.cohort_id,provider_id:pid(12),reason:'Explain official source validation through existing approved Operations model'}
const aiAdvice=j(`begin;
 insert into pipeline.platform_toolset_settings(toolset_key,key,kind,value) values('pipeline','ops.ai_diagnosis_on','number','1'),('pipeline','ops.ai_diagnosis_model','text','"fixture/approved-ops-model"') on conflict(toolset_key,key) do update set value=excluded.value;
 insert into pipeline.integration_issues(fingerprint,title,layer,failure,expected,detection_source,severity,workstream,provider_ids,evidence)
 values('fixture-provider-evidence-explanation','Controlled provider evidence validation','Layer 3','The proposal is held for review capacity','Explain evidence without admission','isolated acceptance','P2','A4',array[${quote(pid(12))}::uuid],jsonb_build_object('evidence_id',${quote(docs.evidence_id)}));
 select public.admin_provider_description_run_v1('diagnose',${quote(JSON.stringify(diagnosisArgs))}::jsonb);
 select jsonb_build_object('repeat',public.admin_provider_description_run_v1('diagnose',${quote(JSON.stringify(diagnosisArgs))}::jsonb),'queued',(select count(*) from pipeline.ops_ai_diagnosis_requests),'admitted',(select count(*) from pipeline.provider_description_reads where provider_id=${quote(pid(12))}::uuid and state='admitted'),'ceiling',security.pipeline_num_v1('pdesc.ai_usd_max',1));
 rollback;`)
ok(aiAdvice.repeat.request_id&&aiAdvice.queued===1&&aiAdvice.admitted===0&&aiAdvice.ceiling===1,'authorised AI explanation queues one evidence-bound existing Operations request without approval or setting changes')
sql(`select public.layer4_review_decide(${quote(race.id)}::uuid,'reject','Isolated reviewer rejects the capacity-race placeholder',null);`,{json:true})
const resumed=j('select security.provider_description_fire_v1();')
const afterResume=rpc('saved',{cohort_id:ca.cohort_id})
ok(afterResume.providers[0].state==='proposed'&&scalar("select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description';")===spent,'existing scheduler resumes parked validated proposal after human review frees capacity without another AI call')
decideProvider(pid(12),'reject')
const rejected=rpc('saved',{cohort_id:ca.cohort_id})
ok(rejected.providers[0].state==='rejected'&&rejected.totals.admitted===0,'explicit human rejection is persisted and never admitted')
db(`update pipeline.provider_description_reads set updated_at=now()-interval '400 days' where id=${quote(readId)}::uuid;`)
const unchanged=rpc('preview',{country:'CA',provider_id:pid(12),size:1,mode:'stored',filter:'failed'})
ok(unchanged.providers[0].eligibility_reason==='unchanged_unsuitable_evidence','unchanged rejected evidence remains excluded even after ordinary retry age expires')
db(`update pipeline.edge_request_log set created_at=now()-make_interval(mins=>security.pipeline_num_v1('pdesc.every_minutes',60)::int+1) where mode='provider_description';`)
const nzDispatch=j('select security.provider_description_fire_v1();')
const nzBody=j(`select body from fixture.worker_dispatches order by request_id desc limit 1;`)
ok(nzDispatch.sent===1&&nzBody.cohort_id===nz.cohort_id,'next existing governed schedule advances the next eligible cohort after rejection')
const nzProcessed=processNext(1,nz.cohort_id)
ok(nzProcessed.results.length===1&&nzProcessed.results[0].item_id!==readId,'rejected provider does not stop next eligible NZ cohort processing')
decideProvider(pid(11))
const nzVerified=rpc('verify',{cohort_id:nz.cohort_id})
ok(nzVerified.totals.admitted===1&&nzVerified.totals.website_verified===1,'NZ country configuration uses identical engine and actual authorised Website read-back')
const wrongIdentity=j(`begin;update pipeline.website_sync_items set item=jsonb_set(item,'{provider_id}','"fixture:provider:unrelated"') where entity='provider' and item_key='fixture:provider:11';select security.provider_description_run_result_v1(${quote(nz.cohort_id)}::uuid);rollback;`)
ok(wrongIdentity.providers[0].zoho.status==='mismatch','matching description text under an unrelated consumer provider identity is refused publication verification')
const validationTicks=Math.max(1,Math.ceil(scalar("select count(*) from pipeline.provider_description_reads where state in ('admitted','verified');")/scalar("select security.pipeline_num_v1('pdesc.queue_per_run',10);")))
const scheduledChecks=Array.from({length:validationTicks},()=>"select security.provider_description_publication_check_v1();").join('')
const zohoRecovered=j(`begin;update pipeline.website_sync_items set item=jsonb_set(item,'{description}','"Stale prepared Zoho description"'),hash=md5((jsonb_set(item,'{description}','"Stale prepared Zoho description"')-'generated_at'-'freshness')::text) where entity='provider' and item_key='fixture:provider:11';${scheduledChecks}select public.zoho_v2_provider('fixture:provider:11');rollback;`)
ok(zohoRecovered.item.description===nzVerified.providers[0].proposed_description,'existing scheduled verifier repairs stale prepared Zoho descriptions and confirms actual read-back')
// Actual consumer mismatch, followed by the same scheduled publication verifier recovery.
const nzRead=nzVerified.providers[0].read_id
const mismatch=j(`begin;update catalogue.providers set publication_status='unpublished' where id=${quote(pid(11))}::uuid;update pipeline.provider_description_reads set published_at=null where id=${quote(nzRead)}::uuid;select jsonb_build_object('check',security.provider_description_publication_check_v1(),'published',(select published_at from pipeline.provider_description_reads where id=${quote(nzRead)}::uuid),'body',public.website_v2_provider('fixture:provider:11'));rollback;`)
ok(mismatch.published===null&&mismatch.body.error,'consumer mismatch stays unverified rather than relabelling admission as publication')
const recovered=j(`begin;update pipeline.provider_description_reads set published_at=null where id=${quote(nzRead)}::uuid;${scheduledChecks}select jsonb_build_object('published',(select published_at from pipeline.provider_description_reads where id=${quote(nzRead)}::uuid));rollback;`)
ok(recovered.published,'existing scheduled publication verifier resumes read-back after projection recovers')
scope([15])
db("update pipeline.platform_toolset_settings set value='10'::jsonb where toolset_key='pipeline' and key='pdesc.pending_max';")
const conflict=prepare(15);rpc('run',{cohort_id:conflict.cohort_id});const conflictResult=processNext(1,conflict.cohort_id)
const conflictSaved=rpc('saved',{cohort_id:conflict.cohort_id})
ok(conflictResult.results.length===1&&conflictSaved.providers[0].state==='held'&&conflictSaved.providers[0].rule==='provider_name_conflict'&&conflictSaved.totals.cost_usd===0,'university versus similarly named college About page is held before any model call')
ok(scalar("select count(*) from pipeline.ops_remedy_outcomes where knowledge_code like 'provider_description%';")>0,'existing recovery knowledge base records actual reader/admission outcomes')
db(`update pipeline.platform_toolset_settings set value=${quote(JSON.stringify(keys))}::jsonb where toolset_key='pipeline' and key='pdesc.provider_keys';`)
ok(rpc('preview',{provider_id:pid(13),size:1,mode:'stored'}).eligible===1,'browser residual provider remains independently eligible after blocked-provider tests')
fs.writeFileSync('docs/ui-evidence/provider-description-negative-results.json',JSON.stringify({passed:results.length,results,actual_vendor_calls:0,model_boundary:'Controlled recorded model transport only'},null,2)+'\n')
console.log(JSON.stringify({passed:results.length}))
