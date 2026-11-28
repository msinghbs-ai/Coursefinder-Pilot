-- CF-247 s1327 (S1-Build; Platform Admin / SS-Programme-Control 28 Nov 2026 06:54 AEDT: "Approve the scoped Batch 08 development exception for
-- UNE and TAFE Queensland only ... Register and qualify both sources through the existing Decision 162 mechanism").
-- What it adds (data in the existing Decision 162 tables; no table, column or function shape changes):
--   1. One provider_fee_schedule source each for the University of New England (CRICOS 00003G, the 2027 international course fees page) and
--      TAFE Queensland (CRICOS 03020E, the 2027 international price list; only its higher education table, "Cost (annual indicative)", is
--      read; its vocational tables print whole-of-course totals and are parked until the mechanism carries that fee basis).
--   2. Their Decision 162 qualifications (international_fee; exact CRICOS course code within the provider; schedule kept as evidence with its
--      SHA-256), approved by the Platform Admin 28 Nov 2026 06:54 for these two providers only. The worker (fee-schedule-etl v0.9.0) reads
--      the two HTML pages with the same row rule; svc_fee_schedule_apply keeps every existing check (bound active course, one amount per
--      code, newer year current, same year different amount to Layer 4).
--   3. svc_fee_schedule_apply (md5 guarded, one anchored edit): an HTML schedule's evidence is registered as text/html, not application/pdf.
-- G1: no job. G2: no operational value. G3: 75/48 checked. Locks, Layer 4 decisions and cron checked. $0. Nothing dropped or deleted.
-- Replaces: public.svc_fee_schedule_apply (md5 d5bc73e93f83c950e5a37130a0488fd2; the evidence media type of an HTML schedule).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

create temp table s1327_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) as decided_before;

do $e$
declare v jsonb := security.consumer_api_check_v1(); d text; o oid; n int; v_au uuid; v_sys uuid;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  select c.id into v_au from ref.countries c where c.iso_alpha2 = 'AU';
  select s.system_id into v_sys from pipeline.sources s where s.source_type = 'provider_fee_schedule' and s.metadata->>'decision' = 'Decision 162' limit 1;
  if v_au is null or v_sys is null then raise exception 'pre-check: the Decision 162 fee schedule system or AU is missing'; end if;

  insert into pipeline.sources (url, label, status, metadata, system_id, country_id, trust_rank, provider_id, source_type)
  select x.url, x.label, 'active',
         jsonb_build_object('facts', jsonb_build_array('international_fee'), 'decision', 'Decision 162', 'course_identity', 'exact CRICOS course code within the provider',
                            'provider_cricos', x.cricos, 'format', 'html', 'change', 's1327'),
         v_sys, v_au, 95, x.pid, 'provider_fee_schedule'
    from (values ('https://www.une.edu.au/international/fees-and-scholarships/course-fees-2027', 'University of New England international course fees (annual: two full-time trimesters)', '00003G', 'fa0e0d13-838a-42ff-b6a3-9cea84bd80b2'::uuid),
                 ('https://tafeqld.edu.au/international/courses/international-pricelist', 'TAFE Queensland international price list: higher education (annual indicative)', '03020E', 'bf68c5a3-77c4-4ab8-8c84-6d99e435b1f5'::uuid)) x(url, label, cricos, pid)
   where not exists (select 1 from pipeline.sources s where s.source_type = 'provider_fee_schedule' and s.metadata->>'provider_cricos' = x.cricos);

  insert into pipeline.course_fact_source_qualifications (notes, metadata, source_id, country_id, source_key, source_class, authority_name, provider_cricos, admitted_domains,
                                                          mapping_strategy, evidence_strategy, qualification_status)
  select 'Decision 162 step 2: deterministic fee-schedule parser (HTML table, s1327); scoped exception approved by the Platform Admin 28 Nov 2026 06:54 for UNE and TAFE Queensland only',
         jsonb_build_object('gate', 'Decision-162-fee-schedule', 'search_gate', 'approved 28 Nov 2026 06:54 (Platform Admin scoped exception, s1327)', 'qualified_at', now(),
                            'apply_admitted', true, 'search_admitted', true, 'change_control_ref', 'CF-CHG-20260915-247', 'identity_authority', false, 'change', 's1327'),
         s.id, v_au, 'au_' || lower(s.metadata->>'provider_cricos') || '_intl_fee_schedule', 'provider_first_party',
         case s.metadata->>'provider_cricos' when '00003G' then 'University of New England' else 'TAFE Queensland' end, s.metadata->>'provider_cricos', array['international_fee'],
         'exact CRICOS course code printed in the provider schedule, within the provider (Decision 149)',
         'schedule page retained as evidence with its SHA-256; one row per course; annual fee for one full-time year', 'qualified'
    from pipeline.sources s
   where s.source_type = 'provider_fee_schedule' and s.metadata->>'provider_cricos' in ('00003G', '03020E') and s.metadata->>'change' = 's1327'
     and not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id = s.id);
  get diagnostics n = row_count;
  if (select count(*) from pipeline.sources s join pipeline.course_fact_source_qualifications q on q.source_id = s.id and q.qualification_status = 'qualified'
       where s.source_type = 'provider_fee_schedule' and s.metadata->>'provider_cricos' in ('00003G', '03020E')) <> 2 then
    raise exception 'post-check: the two qualified fee schedule sources are not in place';
  end if;

  select p.oid into o from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'svc_fee_schedule_apply';
  d := pg_get_functiondef(o);
  if position('s1327' in d) = 0 then
    if md5(d) <> 'd5bc73e93f83c950e5a37130a0488fd2' then raise exception 'guard: public.svc_fee_schedule_apply differs from the definition this change edits (live md5 %)', md5(d); end if;
    n := regexp_count(d, 'p_sha256,''application/pdf'',');
    if n <> 1 then raise exception 'guard: evidence media type anchor found % times', n; end if;
    d := replace(d, 'p_sha256,''application/pdf'',', 'p_sha256,case when p_storage_path ~* ''\.html?$'' then ''text/html'' else ''application/pdf'' end /* s1327 */,');
    execute d;
  end if;
end $e$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from pg_temp.s1327_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from cron.job where active) <> b.cron_before then raise exception 'post-check: active job count changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) <> b.decided_before then raise exception 'post-check: a Layer 4 item was decided'; end if;
end $post$;
