// Guards: Provider Description mandate §3/9. Real worker parsing/identity/quote checks and real SQL recording, controlled model transport only.
import { sql, quote } from './db.mjs'
import { descriptionPageText, descriptionSourceIdentity, descriptionClaimCheck, descriptionCostQuote, descriptionRequest, descriptionAnswer, descriptionSentences, DESCRIPTION_PROMPT_VERSION } from '../../../supabase/functions/coverage-sweep/description.ts'
export function processNext(limit = 10, cohortId = null) {
  const lease = sql(`select ${cohortId?`public.svc_provider_description_cohort_next(${Number(limit)},${quote(cohortId)}::uuid)`:`public.svc_provider_description_next(${Number(limit)})`};`, { role:'service_role', json:true })
  const processed=recordLease(lease)
  // Complete the controlled HTTP transport only after actual worker/record SQL has completed.
  if(cohortId)sql(`insert into net._http_response(id) select request_id from fixture.worker_dispatches where body->>'cohort_id'=${quote(cohortId)} and completed_at is null on conflict do nothing;update fixture.worker_dispatches set completed_at=now() where body->>'cohort_id'=${quote(cohortId)} and completed_at is null;`,{role:'postgres'})
  return processed
}
export function recordLease(lease) {
  const maxTokens=Number(sql("select value #>> '{}' from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='reading.answer_tokens.provider_description';",{role:'postgres'}))
  if(!Number.isInteger(maxTokens)||maxTokens<1)throw new Error('The actual governed provider-description answer limit is missing')
  const results=[]
  for(const item of lease.items || []) {
    const doc = sql(`select to_jsonb(d) from fixture.documents d where provider_id=${quote(item.provider_id)}::uuid;`,{role:'postgres',json:true})
    if(!doc)throw new Error('The controlled stored-evidence fixture is missing')
    const page=descriptionPageText(doc.html,lease.page_chars)
    const identity=descriptionSourceIdentity(doc.html,page,item.identity_names || [item.provider])
    const base={item_id:item.item_id,stored_evidence_id:doc.evidence_id,model:lease.model,prompt_version:DESCRIPTION_PROMPT_VERSION,worker:'isolated-controlled-model-transport',cost:0,fc_reads:0,identity_check:identity}
    if(!identity.ok){results.push({...base,quality_hold:{rule:identity.rule,reason:'Current institutional identity is not proved'},rule:identity.rule,reason:'Current institutional identity is not proved by the stored page.'});continue}
    const request=descriptionRequest(lease.model,item.provider,item.stored.url,page,maxTokens,lease.length)
    // Controlled catalogue metadata has the exact same shape and units as /api/v1/models.
    const pricing={data:[{id:lease.model,pricing:{prompt:'0.00000002',completion:'0.00000002',request:'0'}}]}
    const costQuote=descriptionCostQuote(request,pricing)
    if(!costQuote.ok)throw new Error(costQuote.reason)
    request.provider={...request.provider,max_price:costQuote.provider_max_price}
    const reservation=sql(`select public.svc_provider_description_reserve_v1(${quote(item.item_id)}::uuid,${quote(lease.model)},${costQuote.max_cost_usd},${quote(doc.content_hash || item.stored.content_hash)});`,{role:'service_role',json:true})
    if(!reservation.ok){results.push({...base,rule:reservation.reason,reason:'Approved model cost reservation refused'});continue}
    base.ai_reservation={...costQuote,reservation,quote_source:'controlled fixture model catalogue'}
    if(!request.messages[1].content.includes(page))throw new Error('Actual worker request lost its source text')
    // Recorded deterministic model response is the ONLY simulated boundary. No external API or paid model is called.
    const response={choices:[{finish_reason:'stop',message:{content:JSON.stringify(doc.model_answer)}}],usage:{cost:0.0001,completion_tokens:150}}
    const parsed=descriptionAnswer(response,maxTokens)
    if(!parsed.ok)throw new Error(parsed.error)
    if(parsed.cost>costQuote.max_cost_usd)throw new Error('Controlled model response exceeds its reserved price bound')
    const answer=descriptionSentences(parsed.a,page,lease.min_quote_chars)
    const claims=descriptionClaimCheck(answer,Number(lease.verbatim_span_max_chars))
    results.push({...base,cost:parsed.cost,cost_known:true,ai_call_started:true,answer,...(!claims.ok?{quality_hold:{rule:claims.rule,reason:claims.reason}}:{})})
  }
  const outcome=results.length?sql(`select public.svc_provider_description_record(${quote(JSON.stringify(results))}::jsonb);`,{role:'service_role',json:true}):{idle:true,reason:lease.reason}
  if(results.length)sql(`insert into net._http_response(id) select distinct d.request_id from fixture.worker_dispatches d join pipeline.provider_description_cohort_members m on m.cohort_id::text=d.body->>'cohort_id' where m.read_id=any(array[${results.map(r=>quote(r.item_id)+'::uuid').join(',')}]) and d.completed_at is null on conflict do nothing;update fixture.worker_dispatches d set completed_at=now() where exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id::text=d.body->>'cohort_id' and m.read_id=any(array[${results.map(r=>quote(r.item_id)+'::uuid').join(',')}])) and d.completed_at is null;`,{role:'postgres'})
  return {lease,results,outcome}
}
export function decideProvider(providerId, action='approve') {
  const item=sql(`select jsonb_build_object('id',id) from pipeline.layer4_review_items where entity_id=${quote(providerId)}::uuid and field_code='provider_description' and status='pending' order by created_at limit 1;`,{role:'postgres',json:true})
  if(!item)throw new Error('No pending provider-description decision')
  return sql(`select public.layer4_review_decide(${quote(item.id)}::uuid,${quote(action)},'Isolated authorised reviewer acceptance evidence',null);`,{role:'authenticated',rank:6,json:true})
}
