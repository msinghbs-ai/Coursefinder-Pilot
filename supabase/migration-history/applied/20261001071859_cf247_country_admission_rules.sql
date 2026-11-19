-- CF-247 (Platform Admin, 1 Oct 2026 16:54 AEST) approvals:
--   1 "yes": admit New Zealand values when the page is on the provider's own site and shows the NZ programme code or the
--     exact programme title, in NZD only (Decision 202);
--   2 "yes": admit Australian course links and intakes from pages on the provider's own site that match the exact
--     course title; tuition and English stay with pages that show the CRICOS code (Decision 203).
--
-- Rules per country live in pipeline.coverage_admission_countries, so a country added later is a row, not new code:
-- for each value (official_url, intakes, english, tuition) the page identities accepted, and the currency. Identity
-- 'cricos_code' is the reader's name for "the course's registered code is printed on the page" (a CRICOS code in
-- Australia, an NZQA programme code in New Zealand); 'exact_title' is "the page title is the course title".
-- NZ tuition is not switched on here: the Layer 3 tuition steps still record AUD and get their NZD path separately.
--
-- Changes (each function edited in place from its live definition, only if its live body is the one checked on
-- 1 Oct 2026; every anchor must be found exactly once):
--   security.coverage_admission_plan_v1   identity per country and value from the table (was CRICOS code only);
--                                         a course without CRICOS codes outside Australia is no longer 'unresolved'.
--   security.coverage_admission_apply_v1  NZ rows are written through security.coverage_apply_course_v1 (keyed by the
--                                         course and its evidence) instead of the CRICOS-keyed svc_coursefacts_apply_record.
--   public.layer3_fact_claim_service      intake and English pages chosen by the table (replaces the Australia-only fence
--                                         of 20261001163000 now that NZ has an approved rule).
--   security.layer3_fact_admit_v1         same rule; NZ answers written through security.coverage_apply_course_v1.
--   public.admin_course_edit              a tuition entered by hand defaults to the course country's currency (was AUD).
-- The NZ intake and English items parked on 1 Oct 2026 return to Layer 3. Tuition hand-off stays Australian.

create table if not exists pipeline.coverage_admission_countries (
  country_id uuid primary key references ref.countries(id),
  active boolean not null default true,
  currency_code text not null references ref.currencies(code),
  identities jsonb not null,
  approved_ref text not null,
  updated_at timestamptz not null default now()
);
alter table pipeline.coverage_admission_countries enable row level security;

insert into pipeline.coverage_admission_countries(country_id, currency_code, identities, approved_ref)
select k.id, v.cur, v.ids::jsonb, v.ref
  from (values
    ('AU', 'AUD', '{"official_url":["cricos_code","exact_title"],"intakes":["cricos_code","exact_title"],"english":["cricos_code"],"tuition":["cricos_code"]}',
     'Decision 163 (CRICOS code on page, 29 Sep 2026); Decision 203 (exact title for links and intakes, Platform Admin 1 Oct 2026 16:54 AEST)'),
    ('NZ', 'NZD', '{"official_url":["cricos_code","exact_title"],"intakes":["cricos_code","exact_title"],"english":["cricos_code","exact_title"],"tuition":[]}',
     'Decision 202 (NZ programme code or exact title on the provider''s own site, NZD only; Platform Admin 1 Oct 2026 16:54 AEST). Tuition waits for the NZD tuition path.')
  ) v(cc, cur, ids, ref)
  join ref.countries k on k.iso_alpha2 = v.cc
on conflict (country_id) do nothing;

create or replace function security.coverage_country(p_provider_id uuid) returns text
language sql stable security definer set search_path = '' as $fn$
  select k.iso_alpha2::text from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = p_provider_id
$fn$;

-- p_attr null: accepted for at least one value.
create or replace function security.coverage_identity_allowed(p_provider_id uuid, p_basis text, p_attr text) returns boolean
language sql stable security definer set search_path = '' as $fn$
  select coalesce((
    select case when p_attr is null
                then exists (select 1 from jsonb_each(a.identities) e, jsonb_array_elements_text(e.value) b where b = p_basis)
                else coalesce(a.identities->p_attr ? p_basis, false) end
      from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
     where p.id = p_provider_id), false)
$fn$;

-- Country-neutral write of one page's values, keyed by the course (for countries without CRICOS codes).
create or replace function security.coverage_apply_course_v1(p_course_id uuid, p_source_id uuid, p_evidence_id uuid, p_url text,
                                                             p_hash text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare c record; r jsonb; v_test uuid; v_key text; v_links int := 0; v_intakes int := 0; v_english int := 0; v_fees int := 0; v_cur text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select co.id, co.provider_id, lower(coalesce(nullif(btrim(co.course_code), ''), co.id::text)) code, a.currency_code
    into c from catalogue.courses co join catalogue.providers p on p.id = co.provider_id
    join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
   where co.id = p_course_id;
  if c.id is null then raise exception 'course not found or its country has no admission rule'; end if;
  if security.layer4_entity_or_parent_blocked('course', p_course_id, 'operational') then raise exception 'course operationally blocked by Layer 4' using errcode = '42501'; end if;
  if p_source_id is null or p_evidence_id is null or coalesce(btrim(p_url), '') = '' or coalesce(btrim(p_hash), '') = '' then raise exception 'source, evidence, page and hash required'; end if;

  if nullif(btrim(p_payload->>'course_url'), '') is not null then
    insert into catalogue.course_links(course_id, link_type, url, audience, label, is_primary, status, source_id, evidence_id, confidence, last_verified_at, updated_at)
    values (p_course_id, 'official_course', btrim(p_payload->>'course_url'), 'international', 'Official provider course page', false, 'active', p_source_id, p_evidence_id, 1, now(), now())
    on conflict (course_id, link_type, url) do update set status = 'active', source_id = excluded.source_id, evidence_id = excluded.evidence_id,
           confidence = 1, last_verified_at = now(), updated_at = now();
    v_links := 1;
  end if;
  for r in select value from jsonb_array_elements(coalesce(p_payload->'intakes', '[]'::jsonb)) loop
    if nullif(btrim(r->>'intake_label'), '') is null then raise exception 'intake_label required'; end if;
    v_key := coalesce(nullif(r->>'source_intake_key', ''), c.code || ':' || coalesce(r->>'intake_year', 'current') || ':' || lower(r->>'intake_label'));
    insert into catalogue.course_intakes(course_id, intake_year, intake_label, start_date, status, source_id, evidence_id, confidence, source_intake_key)
    values (p_course_id, nullif(r->>'intake_year', '')::int, r->>'intake_label', nullif(r->>'start_date', '')::date, 'active', p_source_id, p_evidence_id, 1, v_key)
    on conflict (course_id, source_id, source_intake_key) where source_id is not null and source_intake_key is not null
    do update set intake_year = excluded.intake_year, intake_label = excluded.intake_label, start_date = excluded.start_date, status = 'active',
                  evidence_id = excluded.evidence_id, confidence = 1;
    v_intakes := v_intakes + 1;
  end loop;
  for r in select value from jsonb_array_elements(coalesce(p_payload->'english_requirements', '[]'::jsonb)) loop
    select id into v_test from ref.english_tests where code = upper(btrim(r->>'test_code')) limit 1;
    if v_test is null then raise exception 'english test not seeded: %', r->>'test_code'; end if;
    insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence,
                                                      source_requirement_key, status, last_verified_at)
    values (p_course_id, v_test, nullif(r->>'overall_score', '')::numeric, coalesce(r->'component_scores', '{}'::jsonb), r->>'notes', p_source_id, p_evidence_id, 1,
            coalesce(nullif(r->>'source_requirement_key', ''), c.code || ':' || upper(btrim(r->>'test_code'))), 'active', now())
    on conflict (course_id, english_test_id) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores,
           notes = excluded.notes, source_id = excluded.source_id, evidence_id = excluded.evidence_id, confidence = 1,
           source_requirement_key = excluded.source_requirement_key, status = 'active', last_verified_at = now();
    v_english := v_english + 1;
  end loop;
  if p_payload ? 'fee_amount' then
    v_cur := coalesce(nullif(btrim(p_payload->>'currency_code'), ''), c.currency_code);
    if v_cur is distinct from c.currency_code then raise exception 'fee currency % does not match the country currency %', v_cur, c.currency_code; end if;
    if nullif(p_payload->>'fee_amount', '')::numeric is null or (p_payload->>'fee_amount')::numeric <= 0 then raise exception 'positive fee amount required'; end if;
    insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, evidence_id, confidence,
                                      source_fee_key, status, last_verified_at, source_snapshot_at, updated_at)
    values (p_course_id, nullif(p_payload->>'fee_year', '')::int, 'international', 'provider_current_tuition', (p_payload->>'fee_amount')::numeric, v_cur,
            nullif(btrim(p_payload->>'fee_basis'), ''), p_payload->>'fee_notes', p_source_id, p_evidence_id, 1,
            c.code || ':international:' || coalesce(p_payload->>'fee_year', 'current') || ':' || coalesce(nullif(btrim(p_payload->>'fee_basis'), ''), 'tuition'),
            'active', now(), now(), now())
    on conflict (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null
    do update set amount = excluded.amount, currency_code = excluded.currency_code, basis = excluded.basis, fee_year = excluded.fee_year,
                  evidence_id = excluded.evidence_id, confidence = 1, status = 'active', last_verified_at = now(), source_snapshot_at = now(), updated_at = now();
    v_fees := 1;
  end if;
  return jsonb_build_object('course_id', p_course_id, 'links_applied', v_links, 'intakes_applied', v_intakes, 'english_applied', v_english, 'fees_applied', v_fees);
end $fn$;
revoke all on function security.coverage_apply_course_v1(uuid, uuid, uuid, text, text, jsonb) from public, anon, authenticated;

-- In-place edits -------------------------------------------------------------------------------------------------------
do $edits$
declare s text; d text; v text; e jsonb; x jsonb;
  edits jsonb := jsonb_build_array(
    jsonb_build_object('schema','security','name','coverage_admission_plan_v1','md5','2a55770ca342b56d9eb9c797dc12194b','pairs', jsonb_build_array(
      jsonb_build_array('select p.course_id, p.provider_id, p.url, p.evidence_id, p.candidates c, e.content_hash,',
                        'select p.course_id, p.provider_id, p.url, p.evidence_id, p.candidates c, e.content_hash, p.identity_basis ib,'),
      jsonb_build_array($a$where p.read_status='read' and p.identity_basis='cricos_code' and p.candidates->>'extractor'=p_extractor$a$,
                        $b$where p.read_status='read' and security.coverage_identity_allowed(p.provider_id, p.identity_basis, null) and p.candidates->>'extractor'=p_extractor$b$),
      jsonb_build_array(E'      from pg),\n  eng as (',
                        E'      from pg where security.coverage_identity_allowed(pg.provider_id, pg.ib, ''official_url'')),\n  eng as ('),
      jsonb_build_array($a$from pg where pg.c->'english' ?| array['ielts_overall','pte_overall','toefl_overall']),$a$,
                        $b$from pg where pg.c->'english' ?| array['ielts_overall','pte_overall','toefl_overall'] and security.coverage_identity_allowed(pg.provider_id, pg.ib, 'english')),$b$),
      jsonb_build_array($a$from pg where jsonb_array_length(coalesce(pg.c->'intakes','[]'))>0),$a$,
                        $b$from pg where jsonb_array_length(coalesce(pg.c->'intakes','[]'))>0 and security.coverage_identity_allowed(pg.provider_id, pg.ib, 'intakes')),$b$),
      jsonb_build_array($a$when a.pc is null or a.cc is null then 'unresolved'$a$,
                        $b$when (a.pc is null or a.cc is null) and security.coverage_country(a.provider_id) = 'AU' then 'unresolved'$b$))),
    jsonb_build_object('schema','security','name','coverage_admission_apply_v1','md5','c268e676e04011b4e981225cdf6dc018','pairs', jsonb_build_array(
      jsonb_build_array(E'   where a.action=''write''\n     and not exists (select 1 from pipeline.course_fact_source_qualifications q',
                        E'   where a.action=''write'' and a.provider_cricos is not null\n     and not exists (select 1 from pipeline.course_fact_source_qualifications q'),
      jsonb_build_array(E'      perform public.svc_coursefacts_apply_record(security.coverage_sweep_source(r.provider_id), r.evidence_id, r.provider_cricos, r.course_cricos,\n              ''coverage:''||r.course_id, r.page_url, r.content_hash, v_payload, true);',
                        E'      if r.provider_cricos is null or r.course_cricos is null then\n        perform security.coverage_apply_course_v1(r.course_id, security.coverage_sweep_source(r.provider_id), r.evidence_id, r.page_url, r.content_hash, v_payload);\n      else\n      perform public.svc_coursefacts_apply_record(security.coverage_sweep_source(r.provider_id), r.evidence_id, r.provider_cricos, r.course_cricos,\n              ''coverage:''||r.course_id, r.page_url, r.content_hash, v_payload, true);\n      end if;'))),
    jsonb_build_object('schema','public','name','layer3_fact_claim_service','md5','995ced9d6892b1512c5e168aafe2cbe3','pairs', jsonb_build_array(
      jsonb_build_array(E'\n      join catalogue.providers pv on pv.id=pg.provider_id\n      join ref.countries kc on kc.id=pv.country_id and kc.iso_alpha2=''AU''', ''),
      jsonb_build_array($a$where pg.read_status='read' and pg.identity_basis='cricos_code'$a$,
                        $b$where pg.read_status='read' and security.coverage_identity_allowed(pg.provider_id, pg.identity_basis, case p_task_class when 'provider_intake_validation' then 'intakes' else 'english' end)$b$))),
    jsonb_build_object('schema','security','name','layer3_fact_admit_v1','md5','58751c63f6d4b573c1fd6697c93c019e','pairs', jsonb_build_array(
      jsonb_build_array($a$and pg.evidence_id=w.evidence_id and pg.identity_basis='cricos_code'$a$,
                        $b$and pg.evidence_id=w.evidence_id and security.coverage_identity_allowed(pg.provider_id, pg.identity_basis, case p_task_class when 'provider_intake_validation' then 'intakes' else 'english' end)$b$),
      jsonb_build_array($a$if r.pc is null or r.cc is null then raise exception 'provider or course CRICOS unresolved'; end if;$a$,
                        $b$if (r.pc is null or r.cc is null) and security.coverage_country(r.provider_id) = 'AU' then raise exception 'provider or course CRICOS unresolved'; end if;$b$),
      jsonb_build_array(E'      if not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=v_src and q.provider_cricos=upper(r.pc)) then',
                        E'      if r.pc is null then null;\n      elsif not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=v_src and q.provider_cricos=upper(r.pc)) then'),
      jsonb_build_array($a$perform public.svc_coursefacts_apply_record(v_src, r.evidence_id, r.pc, r.cc, 'l3:'||p_task_class||':'||r.course_id, r.url, r.content_hash, v_payload, true);$a$,
                        $b$if r.pc is null or r.cc is null then perform security.coverage_apply_course_v1(r.course_id, v_src, r.evidence_id, r.url, r.content_hash, v_payload); else perform public.svc_coursefacts_apply_record(v_src, r.evidence_id, r.pc, r.cc, 'l3:'||p_task_class||':'||r.course_id, r.url, r.content_hash, v_payload, true); end if;$b$))),
    jsonb_build_object('schema','public','name','admin_course_edit','md5','d767d484948e4fd03f8cc52fd3e64d88','pairs', jsonb_build_array(
      jsonb_build_array($a$v_amount, coalesce(nullif(p_args->>'currency', ''), 'AUD'),$a$,
                        $b$v_amount, coalesce(nullif(p_args->>'currency', ''), (select k.default_currency_code::text from catalogue.providers pv join ref.countries k on k.id = pv.country_id where pv.id = v_c.provider_id), 'AUD'),$b$),
      jsonb_build_array($a$'currency', coalesce(nullif(p_args->>'currency', ''), 'AUD'));$a$,
                        $b$'currency', coalesce(nullif(p_args->>'currency', ''), (select k.default_currency_code::text from catalogue.providers pv join ref.countries k on k.id = pv.country_id where pv.id = v_c.provider_id), 'AUD'));$b$))));
begin
  for e in select * from jsonb_array_elements(edits) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = e->>'schema' and p.proname = e->>'name';
    v := md5(s);
    if v is distinct from e->>'md5' then raise exception '%.% changed (md5 %); not replacing', e->>'schema', e->>'name', v; end if;
    for x in select * from jsonb_array_elements(e->'pairs') loop
      if (length(d) - length(replace(d, x->>0, ''))) / length(x->>0) <> 1 then
        raise exception '%.%: anchor not found exactly once: %', e->>'schema', e->>'name', left(x->>0, 80);
      end if;
      d := replace(d, x->>0, x->>1);
    end loop;
    execute d;
  end loop;
end $edits$;

-- NZ intake and English items parked on 1 Oct 2026 return to Layer 3 (their pages can be claimed again).
update pipeline.layer3_fact_handoffs h set work_item_id = null
  from pipeline.layer3_work_items w
 where w.id = h.work_item_id and w.status = 'parked' and w.last_error like 'parked: not an Australian provider%'
   and w.task_class in ('provider_intake_validation','provider_english_validation');
