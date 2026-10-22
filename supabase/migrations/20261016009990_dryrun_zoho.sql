-- CF-247 (23 Oct 2026). Platform Admin 10:25: "Locations state and city are also missing with English requirement. Do I have to spell
-- out every attribute or you can cross check the gaps and accommodate the ai reader requiement. What is point of hourly reporting if
-- you are not finding gaps and making the platform self sufficient."
-- Found (top 20 NZ universities, 4,189 courses): English missing for 2,190 courses, 705 of them on a course page that was read but
-- whose IELTS the text patterns did not find; the AI fill read campus, duration, delivery, level, field of study and international
-- only, never English or intakes; 50 of 75 campuses had a city but no region (only 1,202 courses, 29%, had a campus with both);
-- the hourly report gave counts, not why each value is missing or what the platform does about it.
-- 1 The AI reader covers every course attribute. Enrich fields (and the standing Fill the gaps task) also read:
--   english   the IELTS overall and lowest band from the stored course page (the quote must name IELTS with the score);
--   intakes   the start months from the stored course page (the quote must name the months);
--   campus_region  the region (state, province or NZ region) of each campus city, chosen from the country's list; a city's region is
--             kept in pipeline.city_regions and given to every campus in that city without asking again.
--   English and intakes are admitted only where the page's proof admits that field for the country (Settings › Identify the page),
--   through the same admission as page readings (security.coverage_apply_course_v1); values set by hand are never changed.
-- 2 Why each value is missing (pipeline.gap_cause_snapshots, job gap-causes every hour at :55): for every active course and attribute
--   (official page, fee, English, intakes, campus, campus region, duration, delivery, level, field of study, international) the cause
--   (no page found, page not read and why, page proof not admitted, AI found no value, in review, queued, not tried yet) and what the
--   platform does about it; a cause with nothing automatic is a design gap. public.admin_gap_causes(country) for Platform health ›
--   Work queues › Why values are missing, and for the hourly report.
-- Replaces: nothing (security.enrich_fields_v1 replaced in full after an md5 check; security.field_gap_queue_tick_v1, public.admin_enrich_fields,
--   security.enrich_coverage_snapshot_v1, security.enrich_fields_slice_v1, public.svc_enrich_ai_next, public.svc_enrich_ai_record and
--   security.enrich_apply_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- Tables ---------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.city_regions (
  country_id uuid not null,
  city_key text not null,
  city text not null,
  subdivision_id uuid not null,
  source text not null default 'ai',
  item_id bigint,
  decided_at timestamptz not null default now(),
  primary key (country_id, city_key)
);
comment on table pipeline.city_regions is 'CF-247 23 Oct 2026 (Platform Admin 10:25 "Locations state and city are also missing"): the region (state, province or NZ region, from ref.subdivisions) of a campus city, chosen by the AI reader from the country''s own list (or set by a person); every campus in that city takes it, so a city is asked once.';
alter table pipeline.city_regions enable row level security;

create table if not exists pipeline.gap_cause_snapshots (
  at timestamptz not null,
  country_code text not null,
  attribute text not null,
  cause text not null,
  action text not null,
  automatic boolean not null,
  courses int not null,
  primary key (at, country_code, attribute, cause)
);
comment on table pipeline.gap_cause_snapshots is 'CF-247 23 Oct 2026 (Platform Admin 10:25 "What is point of hourly reporting if you are not finding gaps"): every hour, for each country and course attribute, how many active courses miss the value and why (the first cause that applies), with what the platform does about it; automatic false is a design gap that needs a change or a person. Kept gaps.cause_keep_days days. Job gap-causes.';
alter table pipeline.gap_cause_snapshots enable row level security;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'gaps.cause_keep_days', 'Gap causes: days kept', 'How many days of the hourly "why values are missing" snapshots are kept.', 'number', '14'::jsonb, '1', '90', 'days', 612, 'Enrichment', 'job gap-causes', 'Platform Admin 23 Oct 2026 10:25: find the gaps every hour')
on conflict (toolset_key, key) do nothing;

-- 1 the AI reader covers every attribute ------------------------------------------------------------------------------------------
do $do$ begin
  if md5(pg_get_functiondef('security.enrich_fields_v1()'::regprocedure)) <> '97df2cd4a37f81582509762fe88af169' then raise exception 'security.enrich_fields_v1 is not the expected version'; end if;
end $do$;
create or replace function security.enrich_fields_v1()
 returns table(field text, label text, level text, sources text[], sort integer)
 language sql
 immutable
 set search_path to ''
as $function$
  select * from (values
    ('campus', 'Campus (with the campus list)', 'course', array['adapter', 'ai_stored'], 1),
    ('duration', 'Duration', 'course', array['adapter', 'ai_stored'], 2),
    ('level', 'Study level', 'course', array['adapter', 'ai_title'], 3),
    ('delivery', 'Delivery mode', 'course', array['adapter', 'ai_stored'], 4),
    ('field_of_study', 'Field of study', 'course', array['ai_title'], 5),
    ('international', 'Open to international students', 'course', array['institution_rule', 'adapter', 'ai_stored'], 6),
    ('provider_address', 'Provider street address', 'provider', array['ai_stored', 'scraper'], 7),
    -- 23 Oct 2026 (Platform Admin 10:25): English, intakes and campus regions too
    ('english', 'English requirement (IELTS)', 'course', array['ai_stored'], 8),
    ('intakes', 'Intakes (start months)', 'course', array['ai_stored'], 9),
    ('campus_region', 'Campus region (state)', 'provider', array['ai_city'], 10)) v(field, label, level, sources, sort)
$function$;

insert into pipeline.field_source_rules(country_code, field, sources, reason) values
 ('ALL', 'english', array['ai_stored'], 'CF-247 23 Oct 2026 (Platform Admin 10:25): the AI reader reads the IELTS requirement from the stored course page'),
 ('ALL', 'intakes', array['ai_stored'], 'CF-247 23 Oct 2026 (Platform Admin 10:25): the AI reader reads the start months from the stored course page'),
 ('ALL', 'campus_region', array['ai_city'], 'CF-247 23 Oct 2026 (Platform Admin 10:25): the AI reader gives each campus city its region from the country''s list')
on conflict do nothing;

-- readings the AI gives, checked against the quote ----------------------------------------------------------------------------------
create or replace function security.enrich_parse_english_v1(p_text text, p_quote text)
 returns jsonb
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare v_n numeric[]; v_o numeric; v_b numeric;
begin
  if p_quote !~* 'ielts' then return null; end if;
  v_n := array(select m[1]::numeric from regexp_matches(coalesce(p_text, ''), '([4-9](?:\.[05])?)', 'g') m);
  if cardinality(v_n) = 0 then return null; end if;
  v_o := v_n[1]; v_b := case when cardinality(v_n) > 1 and v_n[2] <= v_n[1] then v_n[2] end;
  -- the overall score must be in the quote as written (6.5, or 6 / 6.0)
  if not (p_quote ~ ('(^|[^0-9.])' || replace(v_o::text, '.', '\.') || '([^0-9]|$)') or (v_o = trunc(v_o) and p_quote ~ ('(^|[^0-9.])' || trunc(v_o)::text || '(\.0)?([^0-9.]|$)'))) then return null; end if;
  return jsonb_build_object('overall', v_o, 'band', v_b);
end $function$;

create or replace function security.enrich_parse_intakes_v1(p_text text, p_quote text)
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select case when count(*) > 0 then jsonb_build_object('months', jsonb_agg(m.label order by m.n)) end
    from (values (1, 'January'), (2, 'February'), (3, 'March'), (4, 'April'), (5, 'May'), (6, 'June'), (7, 'July'), (8, 'August'),
                 (9, 'September'), (10, 'October'), (11, 'November'), (12, 'December')) m(n, label)
   where coalesce(p_text, '') ~* ('\m' || left(m.label, 3)) and coalesce(p_quote, '') ~* ('\m' || left(m.label, 3))
$function$;

-- known city regions given to campuses without asking
create or replace function security.campus_regions_apply_v1()
 returns int
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v int;
begin
  update catalogue.campuses c set subdivision_id = r.subdivision_id, updated_at = now()
    from pipeline.city_regions r
   where c.subdivision_id is null and c.country_id = r.country_id and lower(btrim(c.city)) = r.city_key;
  get diagnostics v = row_count;
  return v;
end $function$;
revoke execute on function security.campus_regions_apply_v1() from public, anon, authenticated;

-- the standing Fill the gaps task asks for English, intakes and campus regions too
select pg_temp.edit_once('security.field_gap_queue_tick_v1()', 'cdee936daf6631b37e46431faa7e1552', array[
  array[$o$  v_fields := array(select f.field from security.enrich_fields_v1() f);$o$,
        $n$  v_fields := array(select f.field from security.enrich_fields_v1() f);
  perform security.campus_regions_apply_v1();  -- 23 Oct 2026: a city whose region is known needs no AI$n$],
  array[$o$f.x not in ('provider_address', 'campus_list')$o$, $n$f.x not in ('provider_address', 'campus_list', 'campus_region')$n$],
  array[$o$                    when 'international' then c2.open_to_international is null else false end$o$,
        $n$                    when 'international' then c2.open_to_international is null
                    when 'english' then not exists (select 1 from catalogue.course_english_requirements x where x.course_id = c2.id and coalesce(x.status, 'active') = 'active')
                    when 'intakes' then not exists (select 1 from catalogue.course_intakes x where x.course_id = c2.id and x.status = 'active') else false end$n$],
  array[$o$and exists (select 1 from catalogue.courses c3 where c3.provider_id = p.id and c3.lifecycle_status = 'active')),$o$,
        $n$and exists (select 1 from catalogue.courses c3 where c3.provider_id = p.id and c3.lifecycle_status = 'active')
    union all
    select null::uuid, p.id, 'campus_region'
      from catalogue.providers p
     where 'campus_region' = any (v_fields) and coalesce(p.lifecycle_status, 'active') = 'active'
       and exists (select 1 from catalogue.campuses k where k.provider_id = p.id and k.status = 'active' and k.subdivision_id is null and nullif(btrim(k.city), '') is not null)),$n$]]);

-- a task a person starts (Layer 2/3 › Enrich fields) counts and queues them too
select pg_temp.edit_once('public.admin_enrich_fields(text,jsonb)', '359786b53a4f9ea0858ba38c79d27830', array[
  array[$o$                                        when 'international' then (select count(*) from scope s where s.open_to_international is null)$o$,
        $n$                                        when 'international' then (select count(*) from scope s where s.open_to_international is null)
                                        when 'english' then (select count(*) from scope s where not exists (select 1 from catalogue.course_english_requirements x where x.course_id = s.id and coalesce(x.status, 'active') = 'active'))
                                        when 'intakes' then (select count(*) from scope s where not exists (select 1 from catalogue.course_intakes x where x.course_id = s.id and x.status = 'active'))
                                        when 'campus_region' then (select count(*) from catalogue.campuses k where k.provider_id in (select provider_id from scope) and k.status = 'active' and k.subdivision_id is null and nullif(btrim(k.city), '') is not null)$n$],
  array[$o$                    when 'international' then c.open_to_international is null else false end
    on conflict do nothing;$o$,
        $n$                    when 'international' then c.open_to_international is null
                    when 'english' then not exists (select 1 from catalogue.course_english_requirements x where x.course_id = c.id and coalesce(x.status, 'active') = 'active')
                    when 'intakes' then not exists (select 1 from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active') else false end
    on conflict do nothing;
    -- 23 Oct 2026: campus regions, one item per university with campus cities that have no region
    perform security.campus_regions_apply_v1();
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
    select v_job, p.id, null::uuid, 'campus_region'
      from catalogue.providers p join ref.countries k on k.id = p.country_id
     where 'campus_region' = any (v_fields)
       and (cardinality(v_cc) = 0 or k.iso_alpha2::text = any (v_cc)) and (cardinality(v_pids) = 0 or p.id = any (v_pids))
       and exists (select 1 from catalogue.campuses k2 where k2.provider_id = p.id and k2.status = 'active' and k2.subdivision_id is null and nullif(btrim(k2.city), '') is not null)
    on conflict do nothing;$n$]]);

-- the coverage snapshot counts English and intakes held
select pg_temp.edit_once('security.enrich_coverage_snapshot_v1()', '095af693d490440a83bad7a32f5862f8', array[
  array[$o$                                           when 'international' then s.open_to_international is not null else false end)$o$,
        $n$                                           when 'international' then s.open_to_international is not null
                                           when 'english' then s.has_english when 'intakes' then s.has_intakes else false end)$n$],
  array[$o$                 exists (select 1 from catalogue.course_campuses x where x.course_id = c.id) has_campus$o$,
        $n$                 exists (select 1 from catalogue.course_campuses x where x.course_id = c.id) has_campus,
                 exists (select 1 from catalogue.course_english_requirements x where x.course_id = c.id and coalesce(x.status, 'active') = 'active') has_english,
                 exists (select 1 from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active') has_intakes$n$]]);

-- the slice sends campus regions to the AI
select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', '64e59f05adac04e10e948cb40779e275', array[
  array[$o$      elsif v_src = 'scraper' then$o$,
        $n$      elsif v_src = 'ai_city' and it.field = 'campus_region' then
        -- 23 Oct 2026: known city regions first; the AI is asked only for cities still without one
        perform security.campus_regions_apply_v1();
        if not exists (select 1 from catalogue.campuses k where k.provider_id = it.provider_id and k.status = 'active' and k.subdivision_id is null and nullif(btrim(k.city), '') is not null) then
          update pipeline.field_enrich_items set state = 'filled', reason = 'every campus city has a region', updated_at = now() where id = it.id;
          v_settled := true; exit;
        end if;
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_city', updated_at = now() where id = it.id;
        v_settled := true; exit;
      elsif v_src = 'scraper' then$n$]]);

-- what the worker is given: the cities without a region and the country's regions
select pg_temp.edit_once('public.svc_enrich_ai_next(integer)', '664db9052d724b1bd24476917d06bb70', array[
  array[$o$    'addresses', coalesce($o$,
        $n$    'regions', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider', coalesce(p.display_name, p.canonical_name), 'country', k.name,
                         'cities', (select coalesce(jsonb_agg(distinct btrim(c2.city)), '[]'::jsonb) from catalogue.campuses c2
                                     where c2.provider_id = u.provider_id and c2.status = 'active' and c2.subdivision_id is null and nullif(btrim(c2.city), '') is not null),
                         'regions', (select coalesce(jsonb_agg(s2.name order by s2.name), '[]'::jsonb) from ref.subdivisions s2 where s2.country_id = p.country_id)))
                        from upd u join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id where u.field = 'campus_region'), '[]'::jsonb),
    'addresses', coalesce($n$]]);

-- what the worker reports: English and intakes checked against the quote; city regions
select pg_temp.edit_once('public.svc_enrich_ai_record(jsonb)', 'ac4159dceed08694d2888c017a517bb9', array[
  array[$o$        when 'campus' then null end;$o$,
        $n$        when 'english' then security.enrich_parse_english_v1(r->'value'->>'text', r->>'quote')
        when 'intakes' then security.enrich_parse_intakes_v1(r->'value'->>'text', r->>'quote')
        when 'campus_region' then (select r->'value' where jsonb_array_length(coalesce(r->'value'->'cities', '[]'::jsonb)) > 0)
        when 'campus' then null end;$n$]]);

-- admission: English and intakes through the page-reading admission, where the page's proof admits the field; city regions kept and given
select pg_temp.edit_once('security.enrich_apply_v1(bigint)', '84bf1e9a71c64ae356f9b9eae2d761ea', array[
  array[$o$  elsif i.field = 'campus' and i.course_id is not null then$o$,
        $n$  elsif i.field in ('english', 'intakes') and i.course_id is not null then
    -- 23 Oct 2026 (Platform Admin 10:25): the AI reading of the course page, admitted like a page reading
    declare g record; v_src uuid; v_payload jsonb;
    begin
      select pg.provider_id, pg.identity_basis, pg.url, pg.evidence_id, e.content_hash, coalesce(e.source_url, pg.url) src_url into g
        from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.course_id = i.course_id;
      if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.course_id
                   and l.field in (case i.field when 'english' then 'english_requirements' else 'intake' end, i.field, 'all')) then
        update pipeline.field_enrich_items set state = 'skipped', reason = 'locked by hand', updated_at = now() where id = i.id; return 'locked';
      end if;
      if g.provider_id is null or not security.coverage_identity_allowed(g.provider_id, g.identity_basis, i.field) then
        update pipeline.field_enrich_items set state = 'skipped', reason = 'the page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit ' || i.field || ' for this country', updated_at = now() where id = i.id;
        return 'not_admitted';
      end if;
      if (i.field = 'english' and exists (select 1 from catalogue.course_english_requirements x where x.course_id = i.course_id and coalesce(x.status, 'active') = 'active'))
         or (i.field = 'intakes' and exists (select 1 from catalogue.course_intakes x where x.course_id = i.course_id and x.status = 'active')) then
        update pipeline.field_enrich_items set state = 'skipped', reason = 'already filled', updated_at = now() where id = i.id; return 'already';
      end if;
      v_src := security.coverage_sweep_source(g.provider_id);
      insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
      select 'courses', case i.field when 'english' then 'course_english' else 'course_intake' end, v_src, 'approved',
             'CF-CHG-20260915-247, Platform Admin 23 Oct 2026 10:25 (AI reader for every attribute; page proof admitted by country)', now(), now(), now()
       where not exists (select 1 from search.enrichment_source_gates x where x.projection_code = 'courses' and x.domain_code = case i.field when 'english' then 'course_english' else 'course_intake' end and x.source_id = v_src);
      v_payload := case i.field
        when 'english' then jsonb_build_object('english_requirements', jsonb_build_array(jsonb_build_object('test_code', 'IELTS', 'overall_score', (i.value->>'overall')::numeric,
                 'component_scores', case when i.value->>'band' is null then '{}'::jsonb else jsonb_build_object('listening', (i.value->>'band')::numeric, 'reading', (i.value->>'band')::numeric, 'writing', (i.value->>'band')::numeric, 'speaking', (i.value->>'band')::numeric) end,
                 'notes', left('AI reading of the course page: ' || coalesce(i.quote, ''), 300))))
        else jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', lower(i.course_id::text) || ':ai:' || lower(m))) from jsonb_array_elements_text(i.value->'months') m)) end;
      perform security.coverage_apply_course_v1(i.course_id, v_src, coalesce(i.evidence_id, g.evidence_id), g.src_url, g.content_hash, v_payload);
      perform search.refresh_course_enrichment_scoped_v1(array[i.course_id], true);
    end;
    -- the row count below says whether the value is now held
    update pipeline.field_enrich_items set updated_at = now() where id = i.id
       and ((i.field = 'english' and exists (select 1 from catalogue.course_english_requirements x where x.course_id = i.course_id and coalesce(x.status, 'active') = 'active'))
         or (i.field = 'intakes' and exists (select 1 from catalogue.course_intakes x where x.course_id = i.course_id and x.status = 'active')));
  elsif i.field = 'campus_region' then
    insert into pipeline.city_regions(country_id, city_key, city, subdivision_id, source, item_id)
    select p.country_id, lower(btrim(x->>'city')), btrim(x->>'city'), s.id, 'ai', i.id
      from jsonb_array_elements(coalesce(i.value->'cities', '[]'::jsonb)) x
      join catalogue.providers p on p.id = i.provider_id
      join ref.subdivisions s on s.country_id = p.country_id and s.name = x->>'region'
    on conflict (country_id, city_key) do nothing;
    update catalogue.campuses c set subdivision_id = r.subdivision_id, updated_at = now()
      from pipeline.city_regions r
     where c.subdivision_id is null and c.country_id = r.country_id and lower(btrim(c.city)) = r.city_key
       and c.provider_id = i.provider_id;
  elsif i.field = 'campus' and i.course_id is not null then$n$]]);

-- 2 why each value is missing -------------------------------------------------------------------------------------------------------
create or replace function security.gap_causes_snapshot_v1()
 returns int
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_at timestamptz := date_trunc('hour', now()); v int;
        v_render text[] := array(select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'pages.render_countries');
        v_fee_cc text[] := array(select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.countries');
begin
  delete from pipeline.gap_cause_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('gaps.cause_keep_days', 14)::int);
  delete from pipeline.gap_cause_snapshots where at = v_at;  -- run again within the hour: the latest wins
  insert into pipeline.gap_cause_snapshots(at, country_code, attribute, cause, action, automatic, courses)
  with c as (
    select c.id, c.provider_id, k.iso_alpha2::text cc, c.duration_value, c.study_level_id, c.delivery_mode, c.primary_field_id, c.open_to_international,
           g.status gs, g.read_status rs, g.identity_basis ib,
           (select s.state from pipeline.course_link_search s where s.course_id = c.id) ls
      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
     where c.lifecycle_status = 'active' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)),
  m as (
    select c.*, x.attr
      from c cross join lateral (values
        ('official_page', exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')),
        ('fee', exists (select 1 from catalogue.course_fees f where f.course_id = c.id and f.audience = 'international' and f.status = 'active')),
        ('english', exists (select 1 from catalogue.course_english_requirements e where e.course_id = c.id and coalesce(e.status, 'active') = 'active')),
        ('intakes', exists (select 1 from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active')),
        ('campus', exists (select 1 from catalogue.course_campuses cc where cc.course_id = c.id)),
        ('campus_region', exists (select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id where cc.course_id = c.id and k.subdivision_id is not null)),
        ('duration', c.duration_value is not null),
        ('delivery', nullif(btrim(c.delivery_mode), '') is not null),
        ('level', c.study_level_id is not null),
        ('field_of_study', c.primary_field_id is not null),
        ('international', c.open_to_international is not null)) x(attr, held)
     where not x.held),
  e as (  -- the latest Enrich fields item and any open "AI found no value" hold for the course and field
    select m.*,
           (select f.state from pipeline.field_enrich_items f where f.course_id = m.id and f.field = m.attr order by f.id desc limit 1) item_state,
           exists (select 1 from pipeline.enrichment_flags f where f.entity = 'course' and f.entity_key = m.id::text and f.field = m.attr
                     and f.reason_code = 'enrich_no_value' and f.state in ('raised', 'counting')) no_value
      from m),
  z as (
    select e.cc, e.attr,
      case
        when e.attr = 'campus_region' and not exists (select 1 from catalogue.course_campuses cc where cc.course_id = e.id) then 'no campus yet'
        when e.attr = 'campus_region' and not exists (select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id where cc.course_id = e.id and nullif(btrim(k.city), '') is not null) then 'campus has no city'
        when e.attr = 'campus_region' then 'campus city has no region yet'
        when e.attr in ('level', 'field_of_study') and e.item_state in ('queued', 'waiting', 'ai', 'leased') then 'AI reading queued'
        when e.attr in ('level', 'field_of_study') and e.no_value then 'AI: the title gives no value'
        when e.attr in ('level', 'field_of_study') then 'not tried yet'
        when e.gs is null or e.gs <> 'bound' then case when e.ls = 'queued' then 'no page: web search queued' when e.ls = 'none' then 'no page: search and AI page match found none' else 'no page found' end
        when e.rs is distinct from 'read' then 'page not read: ' || coalesce(e.rs, 'not yet')
        when e.attr in ('official_page', 'fee', 'english', 'intakes') and not security.coverage_identity_allowed(e.provider_id, e.ib, case e.attr when 'fee' then 'tuition' when 'official_page' then 'official_url' else e.attr end)
          then 'page proof (' || coalesce(e.ib, 'none') || ') not admitted for this field'
        when e.attr = 'official_page' then 'page read, address not admitted yet'
        when e.attr = 'fee' and exists (select 1 from pipeline.layer4_review_items r where r.entity_id = e.id and r.field_code = 'provider_current_tuition_validation' and r.status = 'pending') then 'fee waiting in review'
        when e.attr = 'fee' and exists (select 1 from pipeline.fee_reader_queue q where q.course_id = e.id and q.state in ('queued', 'leased')) then 'fee reader queued'
        when e.attr = 'fee' and not (e.cc = any (v_fee_cc)) then 'fee reader not on for this country'
        when e.attr = 'fee' and exists (select 1 from pipeline.fee_reader_rows r join pipeline.fee_reader_queue q on q.id = r.queue_id where q.course_id = e.id and r.outcome in ('domestic', 'not_yearly'))
          then 'page shows no international yearly fee'
        when e.attr = 'fee' and exists (select 1 from pipeline.fee_reader_queue q where q.course_id = e.id and q.state = 'done') then 'fee reader found no fee on the page'
        when e.attr = 'fee' then 'page shows no single international fee to the reader'
        when e.item_state in ('queued', 'waiting', 'ai', 'leased') then 'AI reading queued'
        when e.no_value then 'AI: the page does not state it'
        else 'not tried yet' end cause
      from e)
  select v_at, z.cc, z.attr, z.cause,
         case
           when z.cause like 'no page: web search queued' then 'web search for the course page (job link-search)'
           when z.cause like 'no page%' then 'AI page match and the university course source finder (jobs coverage-ai-match, source-find)'
           when z.cause = 'page not read: needs_render' and z.cc = any (v_render) then 'read through the scraper (pages.render_countries)'
           when z.cause = 'page not read: needs_render' then 'none: the scraper is not on for this country (pages.render_countries)'
           when z.cause in ('page not read: robots_disallowed') then 'none: the site does not allow reading'
           when z.cause like 'page not read: identity_mismatch' then 'search again for the right page'
           when z.cause like 'page not read%' then 'read again later (job coverage-read)'
           when z.cause like 'page proof%' then 'none: Settings › Identify the page decides which proofs admit this field'
           when z.cause = 'page read, address not admitted yet' then 'admission job coverage-admit'
           when z.cause = 'fee waiting in review' then 'a person decides in Layer 4'
           when z.cause = 'fee reader queued' then 'AI fee reader (job fee-reader)'
           when z.cause = 'fee reader not on for this country' then 'none: add the country to Fee reader: countries'
           when z.cause like 'page shows no%' or z.cause = 'fee reader found no fee on the page' then 'fee schedule pages of the university (AI fee reader)'
           when z.cause = 'AI reading queued' then 'AI reader (Enrich fields)'
           when z.cause like 'AI:%' then 'read again when the page changes; university-wide rule where there is one'
           when z.cause = 'no campus yet' then 'AI reader campus, then the region'
           when z.cause = 'campus has no city' then 'none: the campus record needs its city'
           when z.cause = 'campus city has no region yet' then 'AI reader campus region (Fill the gaps)'
           else 'AI reader (Fill the gaps, job field-gap-queue)' end,
         not (z.cause like 'page proof%' or z.cause in ('page not read: robots_disallowed', 'fee reader not on for this country', 'campus has no city', 'fee waiting in review')
              or (z.cause = 'page not read: needs_render' and not (z.cc = any (v_render)))),
         count(*)
    from z group by z.cc, z.attr, z.cause;
  get diagnostics v = row_count;
  return v;
end $function$;
revoke execute on function security.gap_causes_snapshot_v1() from public, anon, authenticated;

create or replace function public.admin_gap_causes(p_country text default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_at timestamptz; v_prev timestamptz;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select max(at) into v_at from pipeline.gap_cause_snapshots;
  select max(at) into v_prev from pipeline.gap_cause_snapshots where at < v_at;
  return jsonb_build_object('at', v_at, 'previous', v_prev,
    'countries', (select coalesce(jsonb_agg(distinct s.country_code), '[]'::jsonb) from pipeline.gap_cause_snapshots s where s.at = v_at),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('country', s.country_code, 'attribute', s.attribute, 'cause', s.cause, 'action', s.action, 'automatic', s.automatic,
                     'courses', s.courses, 'change', s.courses - coalesce(p.courses, 0)) order by s.country_code, s.attribute, s.courses desc), '[]'::jsonb)
               from pipeline.gap_cause_snapshots s
               left join pipeline.gap_cause_snapshots p on p.at = v_prev and p.country_code = s.country_code and p.attribute = s.attribute and p.cause = s.cause
              where s.at = v_at and (p_country is null or s.country_code = upper(p_country))));
end $function$;
revoke all on function public.admin_gap_causes(text) from public, anon;
grant execute on function public.admin_gap_causes(text) to authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('gap-causes', 'Course pages', 34, 'Why values are missing',
  'Every hour at :55: for every active course and attribute (official page, fee, English, intakes, campus, campus region, duration, delivery, level, field of study, international), why the value is missing and what the platform does about it; causes with nothing automatic are design gaps. Platform health › Work queues › Why values are missing; the hourly report.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('gap-causes', '55 * * * *', $$select security.gap_causes_snapshot_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.city_regions', 'Layer 2', 'Region of each campus city (AI from the country''s list), given to every campus in the city', 'active', '{}', '20261023012000'),
 ('table', 'pipeline.gap_cause_snapshots', 'Platform', 'Hourly: why each attribute is missing per country, and what the platform does about it', 'active', '{}', '20261023012000'),
 ('function', 'security.gap_causes_snapshot_v1', 'Platform', 'Job gap-causes: why values are missing', 'active', '{}', '20261023012000'),
 ('function', 'public.admin_gap_causes', 'Platform', 'Why values are missing, for Platform health and the hourly report', 'active', '{}', '20261023012000'),
 ('function', 'security.campus_regions_apply_v1', 'Layer 2', 'Known city regions given to campuses', 'active', '{}', '20261023012000'),
 ('function', 'security.enrich_parse_english_v1', 'Layer 2', 'IELTS overall and band from an AI reading, checked against its quote', 'active', '{}', '20261023012000'),
 ('function', 'security.enrich_parse_intakes_v1', 'Layer 2', 'Start months from an AI reading, checked against its quote', 'active', '{}', '20261023012000')
on conflict (kind, name) do nothing;

select security.gap_causes_snapshot_v1();
select 'the AI reader covers every attribute; why values are missing, every hour' ok;
do $t$ declare v_job uuid; v_c uuid; v_p uuid; v_item bigint; r1 text; r2 text; v_kp uuid; t0 timestamptz := clock_timestamp(); n int; begin
  select id into v_job from pipeline.admin_jobs where kind = 'enrich_fields' order by created_at desc limit 1;
  select g.course_id, g.provider_id into v_c, v_p from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
   where g.read_status = 'read' and security.coverage_country(g.provider_id) = 'NZ' and security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'english')
     and not exists (select 1 from catalogue.course_english_requirements e where e.course_id = g.course_id) limit 1;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, quote)
  values (v_job, v_p, v_c, 'english', 'ai', 'ai_stored', security.enrich_parse_english_v1('6.5/6.0', 'IELTS Academic overall 6.5 with no band less than 6.0'), 'IELTS Academic overall 6.5 with no band less than 6.0') returning id into v_item;
  r1 := security.enrich_apply_v1(v_item);
  select k.provider_id into v_kp from catalogue.campuses k where k.city = 'Napier' and k.subdivision_id is null limit 1;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value)
  values (v_job, v_kp, null, 'campus_region', 'ai', 'ai_city', '{"cities":[{"city":"Napier","region":"Hawke''s Bay"}]}'::jsonb) returning id into v_item;
  r2 := security.enrich_apply_v1(v_item);
  select count(*) into n from pipeline.gap_cause_snapshots;
  raise exception 'DRYRUN OK %', jsonb_build_object('english_apply', r1, 'english_rows', (select jsonb_agg(jsonb_build_object('o', overall_score, 'c', component_scores)) from catalogue.course_english_requirements where course_id = v_c),
    'intakes_parse', security.enrich_parse_intakes_v1('February, July', 'Start dates: February and July'), 'bad_parse', security.enrich_parse_english_v1('7.0', 'IELTS 6.5 overall'),
    'region_apply', r2, 'napier', (select count(*) from catalogue.campuses where city = 'Napier' and subdivision_id is not null),
    'snap_rows', n, 'nz_english', (select jsonb_agg(jsonb_build_object('c', cause, 'n', courses, 'a', automatic) order by courses desc) from pipeline.gap_cause_snapshots where country_code = 'NZ' and attribute = 'english'),
    'design_gaps', (select jsonb_agg(jsonb_build_object('cc', country_code, 'f', attribute, 'c', cause, 'n', courses)) from (select * from pipeline.gap_cause_snapshots where not automatic order by courses desc limit 8) d),
    'x', 1); end $t$;
