-- CF-247 s903 (Platform Admin 21 Nov 2026 07:48 AEDT, chat S1-Coverage-Unlock-UI-Notes; decision "On-demand, up to 20,000"): one on-demand
-- window for the universities with coverage gaps, capped at 20,000 Firecrawl credits; the scheduled limits are unchanged.
-- What the audit found (read live 21 Nov 2026 08:10-09:40 AEDT, rolled back): the coverage limits are not written into code. They are settings
-- (G2): firecrawl.daily_budget_total 4,000 a day with daily shares (scholarships 1,500, course search 1,200, reads 1,200, central 1,000,
-- provider descriptions 300, other 200), firecrawl.ondemand_credits_per_day 2,000 (enrichment plan screen only), scholarship_cap_per_uni 150,
-- target_countries AU, NZ, CA with target_only. The "38/40" figure is coverage (AU universities with published scholarships), not a cap.
-- None is changed here. Firecrawl left on this month's plan: 67,214 credits.
-- An open on-demand request (security.on_demand_open_v1) lets its providers' Firecrawl spend pass the daily shares; until now only the monthly
-- plan limit and the directory-site rule held it. So the cap is enforced here first:
--   1. security.on_demand_request_for_v2 (md5-guarded edit): a request whose estimate carries cap_firecrawl_units stops covering spend once the
--      units recorded against it (pipeline.coverage_vendor_usage.on_demand_request) reach the cap; that spend then meets the daily shares again.
--      Requests without a cap are unchanged. A partial index makes the sum cheap.
--   2. The window: the active universities (security.scholarship_university) in Australia, New Zealand and Canada with no active entry table and
--      a course without a course entry requirement, or no published scholarship (109 universities, 10,559 courses at the read), Firecrawl only
--      (OpenRouter stays on its own limits), purpose groups central, scholarships and reads (course page search, the lowest priority, is left
--      out), ondemand.window_hours long (6). It is closed, with the actual use and the credit left reported, after it has run.
-- Replaces: security.on_demand_request_for_v2 (same name and arguments; md5-guarded edit).
-- Retires: nothing.
-- G1: no job. G2: no setting changed; the cap is a value of this one request. G3: no consumer object (75/48). Nothing dropped or deleted.
-- Spend: up to 20,000 Firecrawl credits (approved by the Platform Admin, 21 Nov 2026 07:48).

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1. the cap
select pg_temp.edit_once('security.on_demand_request_for_v2(uuid,text)', '2b6d99d5302434bed1040625a0248338', '3a41986e53e8dc4629c120db84176bd2', array[
  array[$o$     and (r.purpose_groups is null or security.fc_purpose_group_v1(p_purpose) = any (r.purpose_groups))
$o$,
        $n$     and (r.purpose_groups is null or security.fc_purpose_group_v1(p_purpose) = any (r.purpose_groups))
     -- CF-247 s903: a request with a Firecrawl cap stops covering spend once its own recorded use reaches the cap (scheduled limits apply again)
     and (r.estimate->>'cap_firecrawl_units' is null
          or coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.on_demand_request = r.id), 0) < (r.estimate->>'cap_firecrawl_units')::numeric)
$n$]
], array[1]);

create index if not exists coverage_vendor_usage_on_demand_request_idx on pipeline.coverage_vendor_usage (on_demand_request) where on_demand_request is not null;

-- 2. the window
do $s903$
declare v_ids uuid[]; v_open jsonb; v_id uuid; v_courses int;
begin
  select array_agg(p.id order by p.id), sum((select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'))
    into v_ids, v_courses
    from catalogue.providers p join ref.countries k on k.id = p.country_id
   where p.lifecycle_status = 'active' and k.iso_alpha2 in ('AU', 'NZ', 'CA') and security.scholarship_university(p.id)
     and ((not exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = p.id and m.status = 'active')
           and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'
                        and not exists (select 1 from catalogue.course_entry_requirements r where r.course_id = c.id and r.status = 'active')))
          or not exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active' and s.publication_status = 'published'));
  if coalesce(cardinality(v_ids), 0) = 0 then raise notice 's903: no university has a coverage gap; no window opened'; return; end if;
  v_open := security.on_demand_open_v1('claude_session',
    'CF-247 s903 coverage unlock (Platform Admin 21 Nov 2026 07:48): universities with no active entry table or no published scholarship; Firecrawl only, capped',
    v_ids,
    jsonb_build_object('firecrawl_units', 20000, 'cap_firecrawl_units', 20000, 'universities', cardinality(v_ids), 'courses', v_courses,
                       'purpose_groups', jsonb_build_array('central', 'scholarships', 'reads'), 'approved', 'Platform Admin 21 Nov 2026 07:48 AEDT'),
    null, '{firecrawl}');
  v_id := (v_open->>'id')::uuid;
  perform security.on_demand_scope_v1(v_id, '{central,scholarships,reads}');
  -- post-checks
  if not exists (select 1 from pipeline.on_demand_requests r where r.id = v_id and r.state = 'open' and r.purpose_groups = '{central,scholarships,reads}'
                  and (r.estimate->>'cap_firecrawl_units')::numeric = 20000 and r.toolsets = '{firecrawl}') then
    raise exception 'post-check: the window is not open with its cap, scope and toolset';
  end if;
  if security.on_demand_request_for_v2(v_ids[1], 'central_map') is distinct from v_id then raise exception 'post-check: the window does not cover a listed university'; end if;
  if security.on_demand_request_for_v2(v_ids[1], 'course_link_search') is not null then raise exception 'post-check: course page search is covered'; end if;
  raise notice 's903: window % opened for % universities (% courses); %', v_id, cardinality(v_ids), v_courses, v_open;
end $s903$;
