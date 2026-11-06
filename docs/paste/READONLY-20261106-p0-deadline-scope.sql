-- Exact three-course reconciliation; no mutation/helper execution beyond pure/date
-- and existing read-only consumer paths. Required before any authorised correction.
begin read only;
set local statement_timeout='8s';
select clock_timestamp() observed_at_utc,c.id,c.course_code,i.id intake_id,i.application_deadline,i.evidence_id,
       f.id field_item,f.state,f.evidence_id reading_evidence,f.quote,f.value->'deadlines' readings,
       (select jsonb_agg(jsonb_build_object('field',m.field,'mode',m.mode)) from pipeline.manual_locks m where m.entity='course' and m.entity_id=c.id) locks,
       public.website_v2_course(c.course_code)->'item'->'intakes' website_intakes,
       public.zoho_edge_course_lookup_v1(c.course_code)->'item'->'intakes' zoho_intakes,
       md5(pg_get_functiondef('security.course_deadline_in_quote_v1(date,text)'::regprocedure)) guard_md5
from catalogue.courses c join catalogue.course_intakes i on i.course_id=c.id
join pipeline.field_enrich_items f on f.course_id=c.id and f.id in (273361,273381,273383)
where i.id in ('0bae1bde-3d71-4ae8-86ff-118049910790','8dcd0a7e-c634-4f9d-92ba-2832413f3583','8e7d1957-58ce-4a2d-9583-fef41ea30bdc')
order by c.id,i.id;
commit;
-- Broader assessment is separate and READ ONLY. Page by immutable item id;
-- inspect at most 100 completed deadline readings in each invocation. The result
-- is a candidate list requiring source review, never a correction predicate.
begin read only;
set local statement_timeout='8s';
with batch as materialized (
  select id,course_id,evidence_id,updated_at,value from pipeline.field_enrich_items
  where field='deadline' and state='filled' and id>=273361
  order by id limit 100
)
select b.id field_item,b.course_id,b.evidence_id,b.updated_at,d->>'date' proposed_date,d->>'quote' quote,i.id intake_id,i.application_deadline
from batch b cross join lateral jsonb_array_elements(b.value->'deadlines') d
join catalogue.course_intakes i on i.course_id=b.course_id and d->'intake_ids' @> jsonb_build_array(i.id::text)
where d->>'outcome'='kept' and i.status='active' and i.application_deadline::text=d->>'date'
  and lower(coalesce(d->>'quote','')) !~ '(application.*(clos|due|deadline)|closing[[:space:]]+date|apply[[:space:]]+(by|before)|intake.*clos)'
order by b.id,i.id;
commit;
