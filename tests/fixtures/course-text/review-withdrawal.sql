-- Guards: Admin #382 P0 deadline semantics and exact correction approval, 6 Nov 2026.
-- Extends the EXISTING isolated course-text fixture. These are SYNTHETIC rows
-- with the three public incident IDs/quotes, NOT a production data copy.
-- The exact review DO body is loaded by run.sh; only its in-memory/test-file
-- approval variables use a labelled synthetic actor and decision. The source
-- proposal stays v_approved=false, v_actor=null, v_decision=null.
-- Consumer functions below are explicitly LIMITED STAND-INS. They reproduce the
-- real JSON keys and a persisted refresh boundary, not the live API/grants/cache.
create schema if not exists api;
create table search.course_documents (course_id uuid primary key, intake_options jsonb);
create temporary table review_expected(course_id uuid primary key, code text, intake_id uuid, label text, wrong_date date, item_id bigint, quote text, item_evidence uuid, intake_evidence uuid);
insert into review_expected values
 ('2b19936a-69ad-49b8-9a33-56644609ccfc','095229D','0bae1bde-3d71-4ae8-86ff-118049910790','November','2026-11-02',273361,'Start date 02 Nov 2026','75891841-a6d3-4707-906f-3ad39d444d53','9b66aac4-dc0c-46dc-893b-b233291984f1'),
 ('2bad6b65-cd92-4a35-9efc-a69d4bb43d99','094185G','8dcd0a7e-c634-4f9d-92ba-2832413f3583','February','2027-02-15',273381,'Intakes 15 February 2027','1458055d-c99a-458c-9d6a-62af342a36ab','1458055d-c99a-458c-9d6a-62af342a36ab'),
 ('2bb7f6ea-be1f-44e2-a51c-72a277045475','106137B','8e7d1957-58ce-4a2d-9583-fef41ea30bdc','October','2026-10-12',273383,'Start Dates 12 October 2026','05e4b193-3ffc-461a-b6bc-16e6e225dd3a','05e4b193-3ffc-461a-b6bc-16e6e225dd3a');
insert into auth.users(id,email) values ('f0000000-0000-4000-8000-000000000001','isolated-fixture-only@example.invalid');
insert into catalogue.courses(id,provider_id,course_code,canonical_title,lifecycle_status)
select course_id,'10000000-0000-0000-0000-000000000001',code,'SYNTHETIC exact-ID deadline fixture '||code,'active' from review_expected;
insert into catalogue.course_intakes(id,course_id,intake_label,intake_year,start_date,application_deadline,status,evidence_id,source_id,source_intake_key)
select intake_id,course_id,label,2029,'2029-03-01',wrong_date,'active',intake_evidence,'10000000-0000-0000-0000-000000000001','synthetic:'||code from review_expected;
-- An unaffected intake of a targeted course must retain its legitimate deadline.
insert into catalogue.course_intakes(id,course_id,intake_label,intake_year,start_date,application_deadline,status)
values ('f0000000-0000-4000-8000-000000000002','2b19936a-69ad-49b8-9a33-56644609ccfc','Other legitimate intake',2029,'2029-04-01','2029-02-01','active');
insert into pipeline.field_enrich_items(id,job_id,provider_id,course_id,field,state,source,evidence_id,quote,value)
select item_id,'50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',course_id,'deadline','filled','ai_stored',item_evidence,quote,
       jsonb_build_object('applied',1,'deadlines',jsonb_build_array(jsonb_build_object('date',wrong_date::text,'quote',quote,'on_page',true,'outcome','kept','intake_ids',jsonb_build_array(intake_id::text))))
from review_expected;

-- LIMITED refresh stand-in: persisted projected rows, with explicit injected
-- errors/staleness for proving the real review statement rolls back on readback.
create function search.refresh_course_enrichment_scoped_v1(p_ids uuid[],p_force boolean) returns void language plpgsql as $fixture$
begin
  if current_setting('fx.deadline_review_failure',true)='refresh_error' then raise exception 'INJECTED refresh failure'; end if;
  if current_setting('fx.deadline_review_failure',true)='refresh_stale' then return; end if;
  insert into search.course_documents(course_id,intake_options)
  select i.course_id,jsonb_agg(jsonb_build_object('label',i.intake_label,'year',i.intake_year,'start_date',i.start_date,'application_deadline',i.application_deadline) order by i.id)
    from catalogue.course_intakes i where i.course_id=any(p_ids) and i.status='active' group by i.course_id
  on conflict(course_id) do update set intake_options=excluded.intake_options;
end $fixture$;
create function api.website_v2_course_item(p_course uuid) returns jsonb language sql stable as $fixture$
  select case when current_setting('fx.deadline_review_failure',true)='website_missing' then null::jsonb
              else jsonb_build_object('intakes',d.intake_options) end from search.course_documents d where d.course_id=p_course
$fixture$;
create function public.zoho_edge_course_lookup_v1(p_code text) returns jsonb language sql stable as $fixture$
  select jsonb_build_object('item',jsonb_build_object('intakes',case
    when current_setting('fx.deadline_review_failure',true)='zoho_v1_stale' then
      (select jsonb_agg(case when i->>'label'=e.label then jsonb_set(i,'{application_deadline}',to_jsonb(e.wrong_date::text)) else i end)
         from jsonb_array_elements(d.intake_options) i)
    else d.intake_options end))
  from search.course_documents d join pg_temp.review_expected e on e.course_id=d.course_id where e.code=p_code
$fixture$;
create function public.zoho_v2_course(p_code text) returns jsonb language sql stable as $fixture$
  select case when current_setting('fx.deadline_review_failure',true)='zoho_v2_missing' then jsonb_build_object('item',null::jsonb)
              else public.zoho_edge_course_lookup_v1(p_code) end
$fixture$;
select set_config('fx.deadline_review_failure','none',false);
select search.refresh_course_enrichment_scoped_v1(array(select course_id from review_expected),true);

create function pg_temp.review_snapshot() returns jsonb language sql stable as $fixture$
  select jsonb_build_object(
    'intakes',(select jsonb_agg(to_jsonb(i) order by i.id) from catalogue.course_intakes i),
    'items',(select jsonb_agg(to_jsonb(i) order by i.id) from pipeline.field_enrich_items i),
    'locks',(select jsonb_agg(to_jsonb(i) order by i.entity,i.entity_id,i.field) from pipeline.manual_locks i),
    'audit',(select jsonb_agg(to_jsonb(i) order by i.id) from pipeline.admin_control_events i),
    'projection',(select jsonb_agg(to_jsonb(i) order by i.course_id) from search.course_documents i))
$fixture$;
create function pg_temp.review_refuses(p_label text,p_expected text,p_setup text default null) returns void language plpgsql as $fixture$
declare v_before jsonb:=pg_temp.review_snapshot(); v_error text;
begin
  begin
    if p_setup is not null then execute p_setup; end if;
    perform pg_temp.review_apply();
    raise exception 'REVIEW TEST FAILED: enabled review unexpectedly succeeded';
  exception when others then v_error:=sqlerrm;
    if position(p_expected in v_error)=0 then raise exception 'REVIEW TEST wrong refusal for %: %',p_label,v_error; end if;
  end;
  perform pg_temp.ok(p_label,pg_temp.review_snapshot()=v_before,'a value, item, lock, audit row or projection escaped rollback');
end $fixture$;

select pg_temp.review_refuses('9a count mismatch rolls back all values and audit','only 2 of 3 exact admission/value guards match',
 $$update catalogue.course_intakes set status='inactive' where id='0bae1bde-3d71-4ae8-86ff-118049910790'$$);
select pg_temp.review_refuses('9b changed current date refuses the whole correction','only 2 of 3 exact admission/value guards match',
 $$update catalogue.course_intakes set application_deadline='2030-01-01' where id='0bae1bde-3d71-4ae8-86ff-118049910790'$$);
select pg_temp.review_refuses('9c human lock refuses without changing the lock','affected human lock exists',
 $$insert into pipeline.manual_locks(entity,entity_id,field) values ('course','2b19936a-69ad-49b8-9a33-56644609ccfc','deadline')$$);
select pg_temp.review_refuses('9d changed helper hash refuses every write','forward semantic guard is not the reviewed version',
 $$create or replace function security.course_deadline_in_quote_v1(p_date date,p_quote text) returns boolean language sql immutable set search_path='' as 'select false'$$);
select pg_temp.review_refuses('9e changed reading artifact refuses every write','only 2 of 3 exact admission/value guards match',
 $$update pipeline.field_enrich_items set evidence_id='f0000000-0000-4000-8000-000000000003' where id=273361$$);
select pg_temp.review_refuses('9f refresh error rolls back updated dates and before-state audit','INJECTED refresh failure',
 $$select set_config('fx.deadline_review_failure','refresh_error',true)$$);
select pg_temp.review_refuses('9g stale projection rolls back updated dates and audit','website projection does not show the exact intake',
 $$select set_config('fx.deadline_review_failure','refresh_stale',true)$$);
select pg_temp.review_refuses('9h missing Website payload rolls back updated dates and audit','website projection does not show the exact intake',
 $$select set_config('fx.deadline_review_failure','website_missing',true)$$);
select pg_temp.review_refuses('9i stale Zoho v1 payload rolls back updated dates and audit','zoho_v1 projection does not show the exact intake',
 $$select set_config('fx.deadline_review_failure','zoho_v1_stale',true)$$);
select pg_temp.review_refuses('9j missing Zoho v2 payload rolls back updated dates and audit','zoho_v2 projection does not show the exact intake',
 $$select set_config('fx.deadline_review_failure','zoho_v2_missing',true)$$);

create temp table review_before as select pg_temp.review_snapshot() value;
create temp table review_intakes_before as select i.* from catalogue.course_intakes i;
select pg_temp.review_apply();
select pg_temp.ok('9k enabled actual review statement clears exactly the three deadlines, preserving every other intake field',
 (select count(*)=3 from catalogue.course_intakes i join review_intakes_before b using(id) where i.application_deadline is distinct from b.application_deadline)
 and not exists (select 1 from catalogue.course_intakes i join review_intakes_before b using(id) where to_jsonb(i)-'application_deadline' is distinct from to_jsonb(b)-'application_deadline')
 and (select count(*)=3 from catalogue.course_intakes i join review_expected e on e.intake_id=i.id where i.application_deadline is null)
 and (select application_deadline='2029-02-01' from catalogue.course_intakes where id='f0000000-0000-4000-8000-000000000002'));
select pg_temp.ok('9l all readings and locks are unchanged; exact three-row before-state is attributable to the synthetic actor/decision',
 (select value->'items'=pg_temp.review_snapshot()->'items' and value->'locks'=pg_temp.review_snapshot()->'locks' from review_before)
 and (select count(*)=1 and bool_and(actor='f0000000-0000-4000-8000-000000000001'::uuid and detail->>'decision'='ISOLATED FIXTURE ONLY - NOT A PRODUCTION APPROVAL' and detail->>'count'='3' and jsonb_array_length(detail->'before')=3)
      from pipeline.admin_control_events where target='P0-DEADLINE-382-20261106-THREE')
 and (select count(*)=3 from pipeline.admin_control_events a cross join lateral jsonb_array_elements(a.detail->'before') b
      join review_expected e on e.intake_id::text=b->'intake'->>'id'
      where a.target='P0-DEADLINE-382-20261106-THREE' and b->'intake'->>'application_deadline'=e.wrong_date::text and b->>'item_id'=e.item_id::text));
create temp table review_success as select pg_temp.review_snapshot() value;
select pg_temp.review_apply();
select pg_temp.ok('9m idempotent retry writes no second audit, value, reading, lock or refresh',
 (select value=pg_temp.review_snapshot() from review_success));
select pg_temp.review_refuses('9n recorded operation with a changed current value requires reconciliation, never replay','operation already recorded but current values differ',
 $$update catalogue.course_intakes set application_deadline='2030-01-01' where id='0bae1bde-3d71-4ae8-86ff-118049910790'$$);
