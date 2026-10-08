-- CF-247 Standing Review Rule 6, unclear page identity (8 Oct 2026, Platform Admin, multiple choice "Unbind and re-find, no review").
-- Of the 140 courses bound to a page whose address names another course, the 54 whose own CRICOS code is on the page stay as they
-- are ("Do nothing if cricos code matches up on providers course page"). For the others (86: 56 pages show the named course's code,
-- 21 pages show no code, 3 courses have no code on record):
--   * a course whose page was chosen by a person (official_url or course_url locked by hand) is left as it is (15);
--   * otherwise the page stops counting for the course: the binding is marked mismatch, the pair (course, page) is blocked so the
--     link search and the title binder cannot bind it again, values read from that page are withdrawn (intakes and English withdrawn,
--     page fee superseded, the course link made inactive; rows with no source, i.e. entered by hand, are never touched), and the course
--     goes back to the link search (CRICOS code first, then title; free search before Firecrawl, within the daily allowance).
-- No Layer 4 item is raised and no row is deleted. Pages shared by courses whose address names none of them stay ("Keep everything").
create table if not exists pipeline.course_page_blocks (
  course_id uuid not null, url text not null, reason text not null, created_at timestamptz not null default now(), primary key (course_id, url));
alter table pipeline.course_page_blocks enable row level security;
revoke all on pipeline.course_page_blocks from public, anon, authenticated;
alter table pipeline.rule6_page_checks add column if not exists action text, add column if not exists acted_at timestamptz;

do $g$ begin
  if md5(pg_get_functiondef('security.course_link_bind_v1(uuid,uuid,text,text)'::regprocedure)) <> 'd9ee96006cf9444528115c81a782e151' then
    raise exception 'course_link_bind_v1 is not the version this migration expects';
  end if;
end $g$;
create or replace function security.course_link_bind_v1(p_course_id uuid, p_provider_id uuid, p_url text, p_basis text)
 returns void language sql security definer set search_path to '' as $function$
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
  select p_course_id, p_provider_id, p_url, p_basis, 'bound', now(), now(), 0
   where not exists (select 1 from pipeline.course_page_blocks b where b.course_id = p_course_id and b.url = p_url)
  on conflict (course_id) do update set url = excluded.url, basis = excluded.basis, status = 'bound', bound_at = now(),
         score = null, runner_up = null, read_status = null, read_at = null, http_status = null, fetched_via = null,
         identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now()
   where pipeline.coverage_course_pages.status <> 'bound' or pipeline.coverage_course_pages.basis in ('cricos_search','title_search');
$function$;
revoke all on function security.course_link_bind_v1(uuid, uuid, text, text) from public, anon, authenticated;

create or replace function security.l4_rule6_apply_v1()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r record; v_kept_hand int := 0; v_done int := 0; v_itk int := 0; v_en int := 0; v_fee int := 0; v_ln int := 0; n int; v_courses uuid[] := '{}'; v_res jsonb;
begin
  for r in select c.course_id, c.provider_id, c.url, c.course_code, c.found, c.codes
             from pipeline.rule6_page_checks c
            where c.checked_at is not null and c.found is not true and c.action is null loop
    if exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = r.course_id and m.field in ('official_url', 'course_url')) then
      update pipeline.rule6_page_checks set action = 'kept: page chosen by hand', acted_at = now() where course_id = r.course_id;
      v_kept_hand := v_kept_hand + 1; continue;
    end if;
    if not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = r.course_id and p.url = r.url) then
      update pipeline.rule6_page_checks set action = 'skipped: no longer bound to this page', acted_at = now() where course_id = r.course_id;
      continue;
    end if;
    insert into pipeline.course_page_blocks(course_id, url, reason)
    values (r.course_id, r.url, 'Rule 6 (8 Oct 2026): page named for another course and the course''s own CRICOS code is not on it') on conflict do nothing;
    update pipeline.coverage_course_pages set status = 'mismatch', read_status = 'identity_mismatch', leased_until = null where course_id = r.course_id;
    update catalogue.course_intakes i set status = 'withdrawn'
     where i.course_id = r.course_id and i.status = 'active' and i.source_id is not null
       and i.evidence_id in (select e.id from pipeline.evidence_artifacts e where e.source_url = r.url);
    get diagnostics n = row_count; v_itk := v_itk + n;
    update catalogue.course_english_requirements q set status = 'withdrawn'
     where q.course_id = r.course_id and coalesce(q.status, 'active') = 'active' and q.source_id is not null
       and q.evidence_id in (select e.id from pipeline.evidence_artifacts e where e.source_url = r.url);
    get diagnostics n = row_count; v_en := v_en + n;
    update catalogue.course_fees f set status = 'superseded', updated_at = now()
     where f.course_id = r.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.source_id is not null
       and f.evidence_id in (select e.id from pipeline.evidence_artifacts e where e.source_url = r.url);
    get diagnostics n = row_count; v_fee := v_fee + n;
    update catalogue.course_links l set status = 'inactive'
     where l.course_id = r.course_id and l.status = 'active' and l.url = r.url and l.source_id is not null;
    get diagnostics n = row_count; v_ln := v_ln + n;
    insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
    values (r.course_id, r.provider_id, case when r.course_code is not null then 'cricos' else 'title' end, 'queued', now())
    on conflict (course_id) do update set stage = excluded.stage, state = 'queued', attempts = 0, query = null, req_id = null, results = null,
           candidates = null, cand_idx = 0, bound_url = null, queued_at = now(), sent_at = null, done_at = null;
    update pipeline.rule6_page_checks set action = 'unbound and sent back to page finding', acted_at = now() where course_id = r.course_id;
    v_done := v_done + 1; v_courses := v_courses || r.course_id;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  v_res := jsonb_build_object('unbound', v_done, 'kept_hand_chosen', v_kept_hand, 'intakes_withdrawn', v_itk, 'english_withdrawn', v_en,
                              'fees_superseded', v_fee, 'links_inactive', v_ln);
  insert into pipeline.layer4_rule_runs(rule, raised) values ('unclear_identity', v_res);
  return v_res;
end $f$;
revoke all on function security.l4_rule6_apply_v1() from public, anon, authenticated;

select security.l4_rule6_apply_v1();
