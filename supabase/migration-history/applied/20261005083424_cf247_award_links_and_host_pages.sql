-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 19:01, 19:07 and 19:18: courses with no page of their own).
-- Three universities were checked first (RMIT, La Trobe, Monash). Across all adapters 5,400 active courses have no
-- confirmed page. The Platform Admin agreed (19:18) to apply the same rules to every university:
-- 1. Award links (exit and nested awards). An award that a student can leave a longer course with, or that is the
--    first part of a longer course (Graduate Certificate or Diploma inside a Masters, Diploma or Associate Degree
--    inside a Bachelor), takes its page, annual fee, intakes and delivery from its SINGLE-DEGREE parent course.
--    Whole fee = annual x its own full-time years. Never from a double degree. Before a fee is carried across, the
--    award's registered total per year (CRICOS) must agree with the parent's within 0.5% (register check), otherwise
--    the link is kept but not applied and is shown for review. The check is against the parent's current annual fee
--    (2%), or its registered total per year when there is no current fee (3%). Exit awards printed as "X is available as an exit award
--    of this degree" (RMIT wording) are now read too. A field is copied only when the university admits that field.
-- 2. Host pages. A page that carries several registrations (majors on one degree page, research degrees on one page)
--    is proposed as the host of each course bound to it that failed the identity check. When the university admits
--    'host_pages', the identity is confirmed as 'host_page' and the normal adapter flow fills the course's values.
--    Double degrees bound to an unconfirmed page and registrations whose page is gone (404) are proposals only: a
--    Platform Admin confirms the page or records "no public page" by hand (the existing course edit).
-- 3. Pathways (foundation, English, college diplomas) stay under their own provider, out of the university's fee
--    range, with a "leads to" link to the degree: a separate change (1590).
-- Settings: the identity basis 'host_page' is listed in Coverage admission countries (controlled there, not here).
-- Values entered by hand are never changed. No text value in this file contains a semicolon.

alter table pipeline.course_exit_awards add column if not exists link_type text not null default 'exit_award';
alter table pipeline.course_exit_awards add column if not exists register_check text;
alter table pipeline.course_exit_awards add column if not exists check_detail text;
do $p$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.course_exit_awards'::regclass and conname = 'course_exit_awards_link_type_check') then
    alter table pipeline.course_exit_awards add constraint course_exit_awards_link_type_check check (link_type in ('exit_award', 'nested_award'));
  end if;
end $p$;

create or replace function security.is_double_degree_title(p text) returns boolean
language sql immutable set search_path = '' as $f$
  select lower(coalesce(p, '')) ~ '( / |/| and bachelor| and master| and diploma|\mdouble\M|\mdual\M|\mcombined\M)'
$f$;
revoke all on function security.is_double_degree_title(text) from public, anon, authenticated;

-- Full-time years of a course: the registered duration (weeks) rounded to the nearest half year, else what the
-- adapter read on its page.
create or replace function security.course_full_time_years(p_course_id uuid) returns numeric
language sql stable security definer set search_path = '' as $f$
  select coalesce(
    (select case when co.duration_value > 0 then greatest(0.5, least(8, round(case co.duration_unit when 'weeks' then co.duration_value / 26.0 when 'months' then co.duration_value / 6.0 when 'years' then co.duration_value * 2 when 'semesters' then co.duration_value when 'trimesters' then co.duration_value / 1.5 end) / 2)) end
       from catalogue.courses co where co.id = p_course_id),
    (select greatest(0.5, least(8, round(coalesce(security.course_years_from_text(pg.candidates->'adapter_extra'->>'course_years'), security.course_years_from_text(pg.candidates->'adapter_extra'->>'duration')) * 2) / 2))
       from pipeline.coverage_course_pages pg where pg.course_id = p_course_id))
$f$;
revoke all on function security.course_full_time_years(uuid) from public, anon, authenticated;

-- Register check: the award's registered international tuition (CRICOS total over its registered weeks, as a
-- per-year figure) against the parent's CURRENT annual fee, within 2%. When the parent has no current fee, against
-- the parent's registered total per year, within 3% (a two-year total mixes two fee years). none when the award has
-- no registered total (NZ and Canada). A double-degree parent always fails.
create or replace function security.award_register_check(p_child uuid, p_parent uuid) returns text[]
language sql stable security definer set search_path = '' as $f$
  with c as (select f.amount / nullif(co.duration_value, 0) * 52 py, f.amount a, co.duration_value w from catalogue.courses co
               left join catalogue.course_fees f on f.course_id = co.id and f.fee_type = 'tuition' and f.basis = 'registered_total_course' and f.status = 'active' and f.audience in ('international', 'all') and f.amount > 0
              where co.id = p_child and co.duration_unit = 'weeks' order by f.valid_from desc nulls last limit 1),
       p as (select f.amount / nullif(co.duration_value, 0) * 52 py, f.amount a, co.duration_value w from catalogue.courses co
               left join catalogue.course_fees f on f.course_id = co.id and f.fee_type = 'tuition' and f.basis = 'registered_total_course' and f.status = 'active' and f.audience in ('international', 'all') and f.amount > 0
              where co.id = p_parent and co.duration_unit = 'weeks' order by f.valid_from desc nulls last limit 1),
       a as (select f.amount an, f.fee_year fy from catalogue.course_fees f where f.course_id = p_parent and f.fee_type = 'provider_current_tuition' and f.status = 'active' and f.audience = 'international' and f.amount > 0 order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1)
  select case when security.is_double_degree_title((select canonical_title from catalogue.courses where id = p_parent)) then array['fail', 'parent is a double degree']
              when c.py is null then array['none', 'the award has no registered total']
              when a.an is not null and abs(c.py / a.an - 1) <= 0.02 then array['pass', 'register ' || round(c.a) || ' over ' || c.w || ' weeks = ' || round(c.py) || ' a year against the parent fee ' || round(a.an) || ' (' || a.fy || ')']
              when a.an is not null then array['fail', 'register ' || round(c.a) || ' over ' || c.w || ' weeks = ' || round(c.py) || ' a year is ' || round((c.py / a.an - 1) * 100, 1) || '% off the parent fee ' || round(a.an) || ' (' || a.fy || ')']
              when p.py is null then array['none', 'the parent has no current fee and no registered total']
              when abs(c.py / p.py - 1) <= 0.03 then array['pass', 'register ' || round(c.a) || ' over ' || c.w || ' weeks against the parent register ' || round(p.a) || ' over ' || p.w || ' weeks']
              else array['fail', 'register ' || round(c.a) || ' over ' || c.w || ' weeks is ' || round((c.py / p.py - 1) * 100, 1) || '% off the parent register (' || round(p.a) || ' over ' || p.w || ' weeks)'] end
    from (select 1) one left join c on true left join p on true left join a on true
$f$;
revoke all on function security.award_register_check(uuid, uuid) from public, anon, authenticated;

create or replace function security.exit_awards_detect_v2(p_provider_id uuid) returns integer
language plpgsql security definer set search_path = '' as $f$
declare n int := 0; r record; m text[]; v_child uuid; v_name text; v_years numeric; v_single uuid; v_chk text[];
begin
  -- A. "After completing N years of full-time study You can exit with a <Award>" (La Trobe wording)
  --    and "<Award> is available as an exit award of this degree" (RMIT wording)
  for r in
    select pg.course_id, pg.url, pg.evidence_id, pg.candidates->'adapter_extra'->>'exit_awards' ex, co.canonical_title
      from pipeline.coverage_course_pages pg join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
     where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null
       and coalesce(pg.candidates->'adapter_extra'->>'exit_awards', '') <> ''
       and not security.is_double_degree_title(co.canonical_title)
  loop
    for m in select regexp_matches(r.ex, '([0-9](?:\.[0-9])?)\s+years?\s+of\s+full[ -]time\s+study[^|]{0,60}exit\s+with\s+(?:an?\s+)?([A-Z][^|.\n]{4,150})', 'gi') loop
      select co.id into v_child from catalogue.courses co
       where co.provider_id = p_provider_id and co.lifecycle_status = 'active' and co.id <> r.course_id
         and security.course_title_key(co.canonical_title) = security.course_title_key(btrim(m[2]))
       order by co.id limit 1;
      continue when v_child is null or security.course_title_key(m[2]) = security.course_title_key(r.canonical_title);
      insert into pipeline.course_exit_awards(child_course_id, parent_course_id, provider_id, exit_years, page_url, evidence_id, printed, reason, link_type)
        values (v_child, r.course_id, p_provider_id, m[1]::numeric, r.url, r.evidence_id, left(m[1] || ' years: ' || btrim(m[2]), 300), 'read from the course page by the adapter', 'exit_award')
      on conflict (child_course_id) do update set parent_course_id = excluded.parent_course_id, exit_years = excluded.exit_years, page_url = excluded.page_url, evidence_id = excluded.evidence_id, printed = excluded.printed, link_type = excluded.link_type, set_at = now() where pipeline.course_exit_awards.set_by = 'adapter';
      n := n + 1;
    end loop;
    for m in select regexp_matches(r.ex, '((?:Graduate|Diploma|Associate|Advanced|Bachelor|Master|Certificate)[^|.\n]{4,200})\s+(?:is|are)\s+available\s+as\s+(?:an?\s+)?exit\s+awards?', 'gi') loop
      foreach v_name in array regexp_split_to_array(m[1], '\s*(?:,|\mand\M)\s*(?=(?:Graduate|Diploma|Associate|Advanced|Bachelor|Master|Certificate))') loop
        v_name := btrim(regexp_replace(v_name, '^(the|a|an)\s+', '', 'i'));
        continue when length(v_name) < 8;
        select co.id into v_child from catalogue.courses co
         where co.provider_id = p_provider_id and co.lifecycle_status = 'active' and co.id <> r.course_id
           and security.course_title_key(co.canonical_title) = security.course_title_key(v_name)
         order by co.id limit 1;
        continue when v_child is null;
        v_years := security.course_full_time_years(v_child);
        continue when v_years is null;
        insert into pipeline.course_exit_awards(child_course_id, parent_course_id, provider_id, exit_years, page_url, evidence_id, printed, reason, link_type)
          values (v_child, r.course_id, p_provider_id, v_years, r.url, r.evidence_id, left(v_name || ' is available as an exit award (' || v_years || ' years from its registered length)', 300), 'read from the course page by the adapter', 'exit_award')
        on conflict (child_course_id) do update set parent_course_id = excluded.parent_course_id, exit_years = excluded.exit_years, page_url = excluded.page_url, evidence_id = excluded.evidence_id, printed = excluded.printed, link_type = excluded.link_type, set_at = now() where pipeline.course_exit_awards.set_by = 'adapter';
        n := n + 1;
      end loop;
    end loop;
  end loop;
  -- B. Nested awards by title: Graduate Certificate/Diploma in X within Master of X, Diploma/Associate Degree/Advanced
  --    Diploma of X within Bachelor of X, where the award has no confirmed page of its own (or sits on the parent's
  --    page or a handbook page) and exactly one single-degree parent with a confirmed page matches.
  for r in
    select ch.id child_id, ch.canonical_title child_title,
           (select array_agg(pc.id) from catalogue.courses pc join pipeline.coverage_course_pages pp on pp.course_id = pc.id and pp.read_status = 'read' and pp.identity_basis is not null
             where pc.provider_id = p_provider_id and pc.lifecycle_status = 'active' and pc.id <> ch.id and not security.is_double_degree_title(pc.canonical_title)
               and security.course_title_key(pc.canonical_title) = security.course_title_key(
                     case when sl.code in ('graduate_certificate', 'graduate_diploma') then regexp_replace(ch.canonical_title, '^Graduate (Certificate|Diploma) (in|of) ', 'Master of ', 'i')
                          else regexp_replace(ch.canonical_title, '^(Diploma|Associate Degree|Advanced Diploma) (in|of) ', 'Bachelor of ', 'i') end)) parents
      from catalogue.courses ch join ref.study_levels sl on sl.id = ch.study_level_id
      left join pipeline.coverage_course_pages pg on pg.course_id = ch.id
     where ch.provider_id = p_provider_id and ch.lifecycle_status = 'active'
       and sl.code in ('graduate_certificate', 'graduate_diploma', 'diploma', 'associate_degree', 'advanced_diploma')
       and (pg.course_id is null or pg.read_status is distinct from 'read' or pg.identity_basis is null or pg.url ~* 'handbook'
            or exists (select 1 from pipeline.coverage_course_pages p2 where p2.url = pg.url and p2.course_id <> ch.id and p2.identity_basis is not null))
       and not exists (select 1 from pipeline.course_exit_awards x where x.child_course_id = ch.id and x.set_by = 'hand')
  loop
    continue when r.parents is null or cardinality(r.parents) <> 1;
    v_single := r.parents[1];
    v_years := security.course_full_time_years(r.child_id);
    continue when v_years is null;
    insert into pipeline.course_exit_awards(child_course_id, parent_course_id, provider_id, exit_years, page_url, evidence_id, printed, reason, link_type)
      select r.child_id, v_single, p_provider_id, v_years, pg.url, pg.evidence_id, left(r.child_title || ' within ' || pc.canonical_title || ' (title match, ' || v_years || ' years from its registered length)', 300), 'matched by title to the parent course', 'nested_award'
        from pipeline.coverage_course_pages pg join catalogue.courses pc on pc.id = pg.course_id where pg.course_id = v_single
    on conflict (child_course_id) do update set parent_course_id = excluded.parent_course_id, exit_years = excluded.exit_years, page_url = excluded.page_url, evidence_id = excluded.evidence_id, printed = excluded.printed, link_type = excluded.link_type, set_at = now() where pipeline.course_exit_awards.set_by = 'adapter' and pipeline.course_exit_awards.link_type = 'nested_award';
    n := n + 1;
  end loop;
  -- C. Adapter links whose parent is a double degree move to the single degree with the same title, when it has a
  --    confirmed page.
  for r in
    select x.child_course_id, x.parent_course_id, pc.canonical_title ptitle
      from pipeline.course_exit_awards x join catalogue.courses pc on pc.id = x.parent_course_id
     where x.provider_id = p_provider_id and x.set_by = 'adapter' and security.is_double_degree_title(pc.canonical_title)
  loop
    v_single := null;
    for v_name in select btrim(s) from unnest(regexp_split_to_array(r.ptitle, '\s*(?:/| and (?=Bachelor|Master|Diploma))\s*')) s loop
      select pc.id into v_single from catalogue.courses pc join pipeline.coverage_course_pages pp on pp.course_id = pc.id and pp.read_status = 'read' and pp.identity_basis is not null
       where pc.provider_id = p_provider_id and pc.lifecycle_status = 'active' and not security.is_double_degree_title(pc.canonical_title)
         and security.course_title_key(pc.canonical_title) = security.course_title_key(v_name)
         and position(security.course_title_key(regexp_replace((select canonical_title from catalogue.courses where id = r.child_course_id), '^[A-Za-z ]+ (in|of) ', '')) in security.course_title_key(pc.canonical_title)) > 0
       order by pc.id limit 1;
      exit when v_single is not null;
    end loop;
    if v_single is not null then
      update pipeline.course_exit_awards x set parent_course_id = v_single, page_url = pp.url, evidence_id = pp.evidence_id, set_at = now(), check_detail = 'moved from the double degree to its single degree' from pipeline.coverage_course_pages pp where pp.course_id = v_single and x.child_course_id = r.child_course_id;
    end if;
  end loop;
  -- D. Register check on every link of this university (hand links are checked too, never changed).
  for r in select x.child_course_id, x.parent_course_id, x.check_detail from pipeline.course_exit_awards x where x.provider_id = p_provider_id loop
    v_chk := security.award_register_check(r.child_course_id, r.parent_course_id);
    update pipeline.course_exit_awards set register_check = v_chk[1], check_detail = case when r.check_detail like 'moved from%' then r.check_detail || ' / ' || v_chk[2] else v_chk[2] end where child_course_id = r.child_course_id;
  end loop;
  return n;
end $f$;
revoke all on function security.exit_awards_detect_v2(uuid) from public, anon, authenticated;

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.exit_awards_apply_v1(uuid)'::regprocedure) is distinct from 'c54ca541ba097d40f1d108ad933d00d9' then
    raise exception 'exit_awards_apply_v1 changed, not basing v2 on it'; end if;
end $p$;

-- v2: a link that failed the register check is skipped, and each value is copied only when the university admits
-- that field (fee, intakes, delivery). Otherwise as v1.
create or replace function security.exit_awards_apply_v2(p_provider_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; v_src uuid; v_hash text; v_fee record; v_itk text[]; v_payload jsonb; v_mode text; v_done int := 0; v_err int := 0; v_skipped int := 0; v_last text; v_courses uuid[] := '{}'; v_af text[];
begin
  select u.admit_fields into v_af from pipeline.uni_adapters u where u.provider_id = p_provider_id and u.enabled and u.admit and 'exit_awards' = any (u.admit_fields);
  if v_af is null then
    return jsonb_build_object('ok', false, 'note', 'exit awards are not admitted for this university'); end if;
  v_src := security.coverage_sweep_source(p_provider_id);
  for r in
    select x.*, pc.course_url parent_url, pc.delivery_mode parent_mode, ch.delivery_mode child_mode
      from pipeline.course_exit_awards x join catalogue.courses pc on pc.id = x.parent_course_id join catalogue.courses ch on ch.id = x.child_course_id and ch.lifecycle_status = 'active'
     where x.provider_id = p_provider_id and x.active and x.evidence_id is not null
       and not security.layer4_entity_or_parent_blocked('course', x.child_course_id, 'operational')
  loop
    if r.register_check = 'fail' then v_skipped := v_skipped + 1; continue; end if;
    begin
      select e.content_hash into v_hash from pipeline.evidence_artifacts e where e.id = r.evidence_id;
      v_payload := jsonb_build_object('course_url', r.page_url);
      v_fee := null;
      if 'fee' = any (v_af) then
        select f.amount, f.fee_year, f.currency_code into v_fee from catalogue.course_fees f
         where f.course_id = r.parent_course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.amount > 0
         order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1;
      end if;
      if v_fee.amount is not null and not security.uni_adapter_excluded(r.child_course_id, 'fee')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('tuition', 'fee', 'fees'))
         and (select f.amount from catalogue.course_fees f where f.course_id = r.child_course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = coalesce(v_fee.fee_year, 0) order by f.updated_at desc nulls last limit 1) is distinct from v_fee.amount then
        update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = r.child_course_id and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = coalesce(v_fee.fee_year, 0) and amount <> v_fee.amount;
        v_payload := v_payload || jsonb_build_object('fee_amount', v_fee.amount, 'fee_year', v_fee.fee_year, 'currency_code', v_fee.currency_code, 'fee_basis', 'annual', 'audience', 'international',
                       'fee_notes', case r.link_type when 'nested_award' then 'Award within the course on this page (' || r.exit_years || ' years of full-time study): annual fee as the course, whole fee ' || round(v_fee.amount * r.exit_years, 2) || ' (annual x ' || r.exit_years || ')'
                                    else 'Exit award after ' || r.exit_years || ' years of full-time study in the course on this page: annual fee as the course, whole fee ' || round(v_fee.amount * r.exit_years, 2) || ' (annual x ' || r.exit_years || ')' end);
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'fee', null, jsonb_build_object('amount', v_fee.amount, 'year', v_fee.fee_year, 'exit_award_of', r.parent_course_id, 'link_type', r.link_type, 'years', r.exit_years, 'whole_fee', round(v_fee.amount * r.exit_years, 2), 'register_check', r.register_check), r.evidence_id, r.page_url);
      end if;
      v_itk := null;
      if 'intakes' = any (v_af) then
        v_itk := (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = r.parent_course_id and i.status = 'active');
      end if;
      if v_itk is not null and not security.uni_adapter_excluded(r.child_course_id, 'intakes')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('intakes', 'intake'))
         and (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = r.child_course_id and i.status = 'active') is distinct from v_itk then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.child_course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        v_payload := v_payload || jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', 'exit-award:' || r.child_course_id || ':' || lower(m))) from unnest(v_itk) m));
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'intakes', null, jsonb_build_object('months', to_jsonb(v_itk), 'exit_award_of', r.parent_course_id), r.evidence_id, r.page_url);
      end if;
      perform security.coverage_apply_course_v1(r.child_course_id, v_src, r.evidence_id, r.page_url, v_hash, v_payload);
      v_mode := case when 'delivery' = any (v_af) then r.parent_mode end;
      if v_mode is not null and r.child_mode is distinct from v_mode and not security.uni_adapter_excluded(r.child_course_id, 'delivery')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('delivery_mode', 'delivery')) then
        update catalogue.courses set delivery_mode = v_mode, updated_at = now() where id = r.child_course_id;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'delivery', to_jsonb(r.child_mode), jsonb_build_object('mode', v_mode, 'exit_award_of', r.parent_course_id), r.evidence_id, r.page_url);
      end if;
      update pipeline.course_exit_awards set applied_at = now(), annual_fee = v_fee.amount, fee_year = v_fee.fee_year, total_fee = round(v_fee.amount * r.exit_years, 2) where child_course_id = r.child_course_id;
      v_done := v_done + 1; v_courses := v_courses || r.child_course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('ok', true, 'applied', v_done, 'skipped_check_failed', v_skipped, 'errors', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.exit_awards_apply_v2(uuid) from public, anon, authenticated;

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.exit_awards_hourly_v1()'::regprocedure) is distinct from '235c984904c6af4383f9f12a4c502c03' then
    raise exception 'exit_awards_hourly_v1 changed, not replacing'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_exit_awards(text,jsonb)'::regprocedure) is distinct from 'dc73f26c28e2b15deef0f0aef85c1f98' then
    raise exception 'admin_exit_awards changed, not replacing'; end if;
end $p$;

create or replace function security.exit_awards_hourly_v1() returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare u record; v jsonb := '[]'::jsonb;
begin
  for u in select a.provider_id from pipeline.uni_adapters a where a.enabled and a.admit and 'exit_awards' = any (a.admit_fields) loop
    v := v || jsonb_build_array(jsonb_build_object('provider_id', u.provider_id, 'found', security.exit_awards_detect_v2(u.provider_id), 'apply', security.exit_awards_apply_v2(u.provider_id)));
  end loop;
  return v;
end $f$;

create or replace function public.admin_exit_awards(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid; v_res jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Layer 4 reviewer or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return coalesce((select jsonb_agg(jsonb_build_object('child_course_id', x.child_course_id, 'child', ch.canonical_title, 'child_code', ch.course_code, 'parent_course_id', x.parent_course_id, 'parent', pc.canonical_title,
                     'years', x.exit_years, 'page_url', x.page_url, 'printed', x.printed, 'active', x.active, 'set_by', x.set_by, 'link_type', x.link_type, 'register_check', x.register_check, 'check_detail', x.check_detail,
                     'annual_fee', x.annual_fee, 'fee_year', x.fee_year, 'total_fee', x.total_fee, 'applied_at', x.applied_at) order by pc.canonical_title, x.exit_years)
                     from pipeline.course_exit_awards x join catalogue.courses ch on ch.id = x.child_course_id join catalogue.courses pc on pc.id = x.parent_course_id where x.provider_id = v_pid), '[]'::jsonb);
  end if;
  if coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'detect' then
    v_res := jsonb_build_object('found', security.exit_awards_detect_v2(v_pid));
  elsif p_action = 'apply' then
    v_res := security.exit_awards_apply_v2(v_pid);
  elsif p_action = 'set' then
    if not exists (select 1 from catalogue.courses c where c.id = (p_args->>'child_course_id')::uuid and c.provider_id = v_pid)
       or not exists (select 1 from catalogue.courses c where c.id = (p_args->>'parent_course_id')::uuid and c.provider_id = v_pid) then
      raise exception 'both courses must belong to this university';
    end if;
    if coalesce((p_args->>'years')::numeric, 0) not between 0.5 and 8 then raise exception 'years must be from 0.5 to 8'; end if;
    if security.is_double_degree_title((select c.canonical_title from catalogue.courses c where c.id = (p_args->>'parent_course_id')::uuid)) then raise exception 'the parent must be a single degree, not a double degree'; end if;
    insert into pipeline.course_exit_awards(child_course_id, parent_course_id, provider_id, exit_years, page_url, evidence_id, printed, set_by, reason, link_type)
      select (p_args->>'child_course_id')::uuid, pg.course_id, v_pid, (p_args->>'years')::numeric, coalesce(nullif(btrim(p_args->>'page_url'), ''), pg.url), pg.evidence_id, left(p_args->>'printed', 300), 'hand', v_reason, coalesce(nullif(p_args->>'link_type', ''), 'exit_award')
      from pipeline.coverage_course_pages pg where pg.course_id = (p_args->>'parent_course_id')::uuid
    on conflict (child_course_id) do update set parent_course_id = excluded.parent_course_id, exit_years = excluded.exit_years, page_url = excluded.page_url, evidence_id = excluded.evidence_id, printed = excluded.printed, set_by = 'hand', reason = excluded.reason, active = true, link_type = excluded.link_type, set_at = now() where pipeline.course_exit_awards.child_course_id = excluded.child_course_id;
    update pipeline.course_exit_awards x set register_check = c.v[1], check_detail = c.v[2] from (select security.award_register_check((p_args->>'child_course_id')::uuid, (p_args->>'parent_course_id')::uuid) v) c where x.child_course_id = (p_args->>'child_course_id')::uuid;
    v_res := jsonb_build_object('ok', true);
  elsif p_action in ('off', 'on') then
    update pipeline.course_exit_awards set active = (p_action = 'on'), set_by = 'hand', reason = v_reason, set_at = now() where child_course_id = (p_args->>'child_course_id')::uuid;
    v_res := jsonb_build_object('ok', true);
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'exit_awards_' || p_action, coalesce(v_pid::text, p_args->>'child_course_id'), jsonb_build_object('result', v_res, 'args', p_args), auth.uid());
  return v_res;
end $f$;

-- Host pages: a page that carries several courses, a double degree's unconfirmed page, or a page that is gone.
create table if not exists pipeline.course_host_pages (
  course_id uuid primary key references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  link_type text not null check (link_type in ('shared_page', 'double_degree', 'no_public_page')),
  host_course_id uuid references catalogue.courses(id),
  host_url text,
  basis text,
  printed text,
  evidence_id uuid,
  register_check text,
  check_detail text,
  active boolean not null default true,
  set_by text not null default 'detector',
  reason text,
  set_at timestamptz not null default now(),
  applied_at timestamptz
);
alter table pipeline.course_host_pages enable row level security;
revoke all on table pipeline.course_host_pages from anon, authenticated;

create or replace function security.host_pages_detect_v1(p_provider_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_shared int; v_double int; v_gone int; v_r record; v_chk text[];
begin
  -- shared_page: the course's page failed the identity check, but the same page is confirmed for another course of
  -- the university whose title is the start of this course's title (majors, research disciplines).
  with cand as (
    select ch.id child_id, hp.course_id host_id, pg.url, hp.evidence_id, hc.canonical_title host_title, ch.canonical_title child_title
      from pipeline.coverage_course_pages pg join catalogue.courses ch on ch.id = pg.course_id and ch.lifecycle_status = 'active'
      join pipeline.coverage_course_pages hp on hp.url = pg.url and hp.provider_id = pg.provider_id and hp.course_id <> pg.course_id and hp.read_status = 'read' and hp.identity_basis is not null
      join catalogue.courses hc on hc.id = hp.course_id and hc.lifecycle_status = 'active'
     where pg.provider_id = p_provider_id and pg.read_status = 'identity_mismatch' and pg.http_status = 200
       and not security.is_double_degree_title(ch.canonical_title)
       and (security.course_title_key(ch.canonical_title) = security.course_title_key(hc.canonical_title)
            or lower(ch.canonical_title) like lower(hc.canonical_title) || ' (%')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = ch.id and k.field in ('official_url', 'course_url'))),
  one as (select distinct on (child_id) * from cand order by child_id, length(host_title) desc, host_id),
  ins as (
    insert into pipeline.course_host_pages(course_id, provider_id, link_type, host_course_id, host_url, basis, printed, evidence_id, reason)
    select child_id, p_provider_id, 'shared_page', host_id, url, 'title', left(child_title || ' on the page of ' || host_title, 300), evidence_id, 'the same page is confirmed for the host course'
      from one
    on conflict (course_id) do update set host_course_id = excluded.host_course_id, host_url = excluded.host_url, printed = excluded.printed, evidence_id = excluded.evidence_id, set_at = now() where pipeline.course_host_pages.set_by = 'detector'
    returning 1)
  select count(*) into v_shared from ins;
  for v_r in select h.course_id, h.host_course_id from pipeline.course_host_pages h where h.provider_id = p_provider_id and h.link_type = 'shared_page' loop
    v_chk := security.award_register_check(v_r.course_id, v_r.host_course_id);
    update pipeline.course_host_pages set register_check = v_chk[1], check_detail = v_chk[2] where course_id = v_r.course_id;
  end loop;
  -- double_degree: a double degree bound to a page that was read but not confirmed, and not shared with another course
  with cand as (
    select ch.id child_id, pg.url, pg.evidence_id, ch.canonical_title
      from pipeline.coverage_course_pages pg join catalogue.courses ch on ch.id = pg.course_id and ch.lifecycle_status = 'active'
     where pg.provider_id = p_provider_id and pg.read_status = 'identity_mismatch' and pg.http_status = 200
       and security.is_double_degree_title(ch.canonical_title)
       and not exists (select 1 from pipeline.coverage_course_pages p2 where p2.url = pg.url and p2.course_id <> pg.course_id)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = ch.id and k.field in ('official_url', 'course_url'))),
  ins as (
    insert into pipeline.course_host_pages(course_id, provider_id, link_type, host_url, basis, printed, evidence_id, reason)
    select child_id, p_provider_id, 'double_degree', url, 'bound page', left(canonical_title || ' bound to ' || url, 300), evidence_id, 'read but the identity was not confirmed: confirm by hand'
      from cand
    on conflict (course_id) do update set host_url = excluded.host_url, printed = excluded.printed, evidence_id = excluded.evidence_id, set_at = now() where pipeline.course_host_pages.set_by = 'detector'
    returning 1)
  select count(*) into v_double from ins;
  -- no_public_page: the bound page is gone (404 twice or more)
  with cand as (
    select ch.id child_id, pg.url, ch.canonical_title
      from pipeline.coverage_course_pages pg join catalogue.courses ch on ch.id = pg.course_id and ch.lifecycle_status = 'active'
     where pg.provider_id = p_provider_id and pg.read_status = 'fetch_failed' and pg.http_status = 404 and coalesce(pg.read_attempts, 0) >= 2
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = ch.id and k.field in ('official_url', 'course_url'))),
  ins as (
    insert into pipeline.course_host_pages(course_id, provider_id, link_type, host_url, basis, printed, reason)
    select child_id, p_provider_id, 'no_public_page', url, '404', left(canonical_title || ': ' || url || ' is gone', 300), 'the page returned 404 twice or more: record no public page by hand'
      from cand
    on conflict (course_id) do update set host_url = excluded.host_url, printed = excluded.printed, set_at = now() where pipeline.course_host_pages.set_by = 'detector'
    returning 1)
  select count(*) into v_gone from ins;
  return jsonb_build_object('shared_page', v_shared, 'double_degree', v_double, 'no_public_page', v_gone);
end $f$;
revoke all on function security.host_pages_detect_v1(uuid) from public, anon, authenticated;

-- Applies shared pages when the university admits 'host_pages': the course's page row is confirmed with the identity
-- basis 'host_page', so the normal adapter flow fills its values from that page (as admitted).
create or replace function security.host_pages_apply_v1(p_provider_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; v_done int := 0;
begin
  if not exists (select 1 from pipeline.uni_adapters u where u.provider_id = p_provider_id and u.enabled and u.admit and 'host_pages' = any (u.admit_fields)) then
    return jsonb_build_object('ok', false, 'note', 'host pages are not admitted for this university'); end if;
  for r in
    select h.course_id, h.host_course_id, h.host_url from pipeline.course_host_pages h
     where h.provider_id = p_provider_id and h.active and h.link_type = 'shared_page' and coalesce(h.register_check, 'none') <> 'fail'
       and exists (select 1 from pipeline.coverage_course_pages pg where pg.course_id = h.course_id and pg.url = h.host_url and pg.read_status = 'identity_mismatch')
       and exists (select 1 from pipeline.coverage_course_pages hp where hp.course_id = h.host_course_id and hp.url = h.host_url and hp.read_status = 'read' and hp.identity_basis is not null)
  loop
    update pipeline.coverage_course_pages pg set read_status = 'read', identity_basis = 'host_page', candidates = case when pg.candidates ? 'adapter_extra' then pg.candidates else coalesce(pg.candidates, '{}'::jsonb) || coalesce((select jsonb_build_object('adapter_extra', hp.candidates->'adapter_extra') from pipeline.coverage_course_pages hp where hp.course_id = r.host_course_id and hp.candidates ? 'adapter_extra'), '{}'::jsonb) end, evidence_id = coalesce(pg.evidence_id, (select hp.evidence_id from pipeline.coverage_course_pages hp where hp.course_id = r.host_course_id)) where pg.course_id = r.course_id and pg.url = r.host_url;
    update pipeline.course_host_pages set applied_at = now() where course_id = r.course_id;
    v_done := v_done + 1;
  end loop;
  return jsonb_build_object('ok', true, 'confirmed', v_done);
end $f$;
revoke all on function security.host_pages_apply_v1(uuid) from public, anon, authenticated;

create or replace function security.host_pages_hourly_v1() returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare u record; v jsonb := '[]'::jsonb;
begin
  for u in select a.provider_id from pipeline.uni_adapters a where a.enabled and a.admit and 'host_pages' = any (a.admit_fields) loop
    v := v || jsonb_build_array(jsonb_build_object('provider_id', u.provider_id, 'found', security.host_pages_detect_v1(u.provider_id), 'apply', security.host_pages_apply_v1(u.provider_id)));
  end loop;
  return v;
end $f$;
revoke all on function security.host_pages_hourly_v1() from public, anon, authenticated;
select cron.schedule('host-pages-apply', '42 * * * *', 'select security.host_pages_hourly_v1()');

create or replace function public.admin_host_pages(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_cid uuid := nullif(p_args->>'course_id', '')::uuid; v_res jsonb; v_h pipeline.course_host_pages%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Layer 4 reviewer or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return coalesce((select jsonb_agg(jsonb_build_object('course_id', h.course_id, 'course', ch.canonical_title, 'code', ch.course_code, 'link_type', h.link_type, 'host_course_id', h.host_course_id, 'host', hc.canonical_title,
                     'host_url', h.host_url, 'basis', h.basis, 'printed', h.printed, 'register_check', h.register_check, 'check_detail', h.check_detail, 'active', h.active, 'set_by', h.set_by, 'applied_at', h.applied_at, 'set_at', h.set_at) order by h.link_type, ch.canonical_title)
                     from pipeline.course_host_pages h join catalogue.courses ch on ch.id = h.course_id left join catalogue.courses hc on hc.id = h.host_course_id where h.provider_id = v_pid), '[]'::jsonb);
  end if;
  if coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'detect' then
    v_res := security.host_pages_detect_v1(v_pid);
  elsif p_action = 'apply' then
    v_res := security.host_pages_apply_v1(v_pid);
  elsif p_action = 'confirm_page' then
    select * into v_h from pipeline.course_host_pages h where h.course_id = v_cid;
    if v_h.course_id is null or v_h.link_type = 'no_public_page' then raise exception 'no page to confirm for this course'; end if;
    update pipeline.coverage_course_pages pg set read_status = 'read', identity_basis = 'host_page' where pg.course_id = v_cid and pg.url = v_h.host_url and pg.read_status = 'identity_mismatch';
    update pipeline.course_host_pages set set_by = 'hand', reason = v_reason, applied_at = now(), set_at = now() where course_id = v_cid;
    v_res := jsonb_build_object('ok', true);
  elsif p_action = 'no_page' then
    v_res := public.admin_course_edit(v_cid, 'remove_official_url', jsonb_build_object('reason', v_reason));
    update pipeline.course_host_pages set set_by = 'hand', reason = v_reason, applied_at = now(), set_at = now() where course_id = v_cid;
    v_res := jsonb_build_object('ok', true);
  elsif p_action in ('off', 'on') then
    update pipeline.course_host_pages set active = (p_action = 'on'), set_by = 'hand', reason = v_reason, set_at = now() where course_id = v_cid;
    v_res := jsonb_build_object('ok', true);
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'host_pages_' || p_action, coalesce(v_pid::text, v_cid::text), jsonb_build_object('result', v_res, 'args', p_args), auth.uid());
  return v_res;
end $f$;
revoke all on function public.admin_host_pages(text, jsonb) from public, anon;
grant execute on function public.admin_host_pages(text, jsonb) to authenticated;

-- The admitted field 'host_pages'
do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_control(text,jsonb)'::regprocedure) is distinct from '57a71930902a0c64538e1e3547a3b030' then
    raise exception 'admin_uni_adapter_control changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_control(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$f where f not in ('intakes', 'english', 'fee', 'delivery', 'exit_awards')$s$, $s$f where f not in ('intakes', 'english', 'fee', 'delivery', 'exit_awards', 'host_pages')$s$],
    array[$s$'fields must be a list of intakes, english, fee, delivery and exit_awards'$s$, $s$'fields must be a list of intakes, english, fee, delivery, exit_awards and host_pages'$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

-- The identity basis 'host_page' joins the lists for official_url, intakes and english (the Coverage admission
-- countries setting controls these lists).
update pipeline.coverage_admission_countries a set identities = (select jsonb_object_agg(e.key, case when e.key in ('official_url', 'intakes', 'english') and not (e.value ? 'host_page') then e.value || '["host_page"]'::jsonb else e.value end) from jsonb_each(a.identities) e) where a.active;

create or replace function security.university_course_host_v1(p_course_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select coalesce(
    (select jsonb_build_object('kind', x.link_type, 'host', pc.canonical_title, 'host_course_id', x.parent_course_id, 'years', x.exit_years, 'register_check', x.register_check, 'active', x.active, 'applied', x.applied_at is not null)
       from pipeline.course_exit_awards x join catalogue.courses pc on pc.id = x.parent_course_id where x.child_course_id = p_course_id),
    (select jsonb_build_object('kind', h.link_type, 'host', hc.canonical_title, 'host_course_id', h.host_course_id, 'url', h.host_url, 'register_check', h.register_check, 'active', h.active, 'applied', h.applied_at is not null, 'set_by', h.set_by)
       from pipeline.course_host_pages h left join catalogue.courses hc on hc.id = h.host_course_id where h.course_id = p_course_id))
$f$;
revoke all on function security.university_course_host_v1(uuid) from public, anon, authenticated;

-- The courses list shows the host of a hosted course
do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_university_courses_read(uuid,jsonb)'::regprocedure) is distinct from 'fe68bd7397f9692f76f0c89e950bfb54' then
    raise exception 'admin_university_courses_read changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_university_courses_read(uuid,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$'requirement', security.university_course_requirement_v1(y.course_id)) order by y.course)$s$, $s$'requirement', security.university_course_requirement_v1(y.course_id), 'host', security.university_course_host_v1(y.course_id)) order by y.course)$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
