-- CF-247 (23 Oct 2026). Platform Admin decisions at 12:40 on the first "Needs a change" list of Why values are missing:
-- 1 "Exact title, field and award, page bound by a person (Recommended)": CA course page fees are admitted (through the AI fee
--   reader) from pages proved by exact title, field and award, or bound by a person; CA joins Fee reader: countries.
--   (2,150 CA courses had a fee on their own page and none admitted: CA fees accepted only a CRICOS code, which Canada has not.)
-- 2 "Switch on for AU (Recommended)": course pages that need a browser are read through the scraper in AU too (about 320 pages).
-- 3 "Yes, admit like exact title (Recommended)": in NZ, a page proved by the adapter's title match admits fee, English and intakes
--   readings like an exact-title page, even where the university's adapter is not set to admit that field (new setting
--   identity.adapter_title_countries, NZ). NZ tuition also lists adapter_title.
-- 4 "AI finds and reads the central page; auto-approve when every score is quoted (Recommended)": the university English rule is
--   found and read without a person: job central-attach (hourly at :48) attaches the best suggested central English page not yet
--   tried for each university with no approved rule (from the central-page search, score at or above central.min_suggest_score, at
--   most central.attach_per_kind pages), the provider-facts job reads it, the pinned AI reads it, and policy-auto-approve approves
--   AI readings with every score quoted for every university (setting central.auto_approve_english_all), not only the AU focus list;
--   readings that most course pages disagree with still go to a person. Why values are missing says whether more central pages are
--   left to try.
-- Replaces: nothing (security.coverage_identity_allowed, security.policy_auto_approve_v1 and security.gap_causes_snapshot_v1 edited in
--   place, md5-guarded)
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

-- settings (G2) ------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'identity.adapter_title_countries', 'Identify the page: adapter title counts like exact title in', 'Countries where a page proved by the university adapter''s title match admits the fields its country list names, even where the adapter is not set to admit that field.', 'list', '["NZ"]'::jsonb, null, null, 'countries', 120, 'Admission checks', 'security.coverage_identity_allowed', 'Platform Admin 23 Oct 2026 12:40: "Yes, admit like exact title"'),
 ('pipeline', 'central.auto_approve_english_all', 'Central pages: approve English rules for every university', 'On (true): an AI reading of a university''s central English page with every score quoted is approved automatically for every university, not only the focus list (readings most course pages disagree with still go to a person).', 'boolean', 'true'::jsonb, null, null, 'on/off', 131, 'Admission checks', 'security.policy_auto_approve_v1', 'Platform Admin 23 Oct 2026 12:40: "auto-approve when every score is quoted"'),
 ('pipeline', 'central.min_suggest_score', 'Central pages: attach suggestions from score', 'Central English pages suggested by the central-page search at or above this score are attached and read when the university has no approved English rule.', 'number', '4'::jsonb, '0', '10', 'score', 132, 'Admission checks', 'job central-attach', 'Platform Admin 23 Oct 2026 12:40'),
 ('pipeline', 'central.attach_per_kind', 'Central pages: pages tried a university', 'The most central English pages attached for one university (each tried in turn until a rule is approved).', 'number', '3'::jsonb, '1', '10', 'pages', 133, 'Admission checks', 'job central-attach', 'Platform Admin 23 Oct 2026 12:40')
on conflict (toolset_key, key) do nothing;

-- 1 CA fees and 3 NZ adapter title: the country lists (logged as a Settings change) -------------------------------------------------
do $do$
declare v_before jsonb; v_after jsonb; v_cc text; v_attr text; v_add jsonb;
begin
  for v_cc, v_attr, v_add in values ('CA', 'tuition', '["exact_title", "field_award", "manual"]'::jsonb), ('NZ', 'tuition', '["adapter_title"]'::jsonb) loop
    select a.identities->v_attr into v_before from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = v_cc;
    v_after := (select jsonb_agg(distinct x) from jsonb_array_elements_text(coalesce(v_before, '[]'::jsonb) || v_add) x);
    update pipeline.coverage_admission_countries c set identities = jsonb_set(c.identities, array[v_attr], v_after, true), updated_at = now(),
           approved_ref = c.approved_ref || format('; Platform Admin 23 Oct 2026 12:40 (%s: %s)', v_attr, v_after)
      from ref.countries k where k.id = c.country_id and k.iso_alpha2 = v_cc;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('settings', 'change', 'identity.attribute', jsonb_build_object('value', jsonb_build_object('country', v_cc, 'attribute', v_attr, 'identities', v_after), 'before', v_before,
            'reason', 'Platform Admin 23 Oct 2026 12:40 (Why values are missing: Needs a change)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end loop;
end $do$;

-- 1 CA in the fee reader and 2 AU in the scraper countries (logged)
do $do$
declare r record;
begin
  for r in select * from (values ('fees.countries', 'CA', 'Platform Admin 23 Oct 2026 12:40: CA course page fees through the AI fee reader'),
                                 ('pages.render_countries', 'AU', 'Platform Admin 23 Oct 2026 12:40: "Switch on for AU"')) v(k, cc, why) loop
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    select 'toolsets', 'setting', 'pipeline.' || r.k, jsonb_build_object('before', s.value, 'after', s.value || to_jsonb(r.cc), 'reason', r.why), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'
      from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = r.k and not s.value ? r.cc;
    update pipeline.platform_toolset_settings s set value = s.value || to_jsonb(r.cc), reason = r.why, updated_at = now()
     where s.toolset_key = 'pipeline' and s.key = r.k and not s.value ? r.cc;
  end loop;
end $do$;

-- 3 adapter title counts like exact title in the listed countries -----------------------------------------------------------------
select pg_temp.edit_once('security.coverage_identity_allowed(uuid,text,text)', 'ff9ddbc25a96a9cbb7ab371bdcefefde', array[
  array[$o$  select case when p_basis in ('adapter_code', 'adapter_title')
                   and not exists$o$,
        $n$  select case when p_basis in ('adapter_code', 'adapter_title')
                   -- 23 Oct 2026 (Platform Admin 12:40): in the countries of identity.adapter_title_countries an adapter title match counts
                   -- like an exact title for the fields its country list names, whatever the adapter admits
                   and not (p_basis = 'adapter_title' and p_attr is not null
                            and exists (select 1 from catalogue.providers p2 join ref.countries k2 on k2.id = p2.country_id
                                         where p2.id = p_provider_id and k2.iso_alpha2 in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s
                                                                                            where s.toolset_key = 'pipeline' and s.key = 'identity.adapter_title_countries')))
                   and not exists$n$]]);

-- 4 university English rules: attach the next suggested central page, read it with AI, approve when every score is quoted ----------------
create or replace function security.central_pages_attach_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_att int := 0; v_q int := 0; v_max int := security.pipeline_num_v1('central.attach_per_kind', 3)::int; r record;
begin
  -- a university with no approved English rule gets its best suggested central English page not yet tried
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
  select x.provider_id, 'english_policy', x.url, left(x.title, 200), 5, 'search', 'found'
    from (select s.provider_id, e->>'url' url, e->>'title' title,
                 row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc) rn
            from pipeline.provider_central_search s cross join lateral jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
           where e->>'kind' = 'english_policy' and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
             and e->>'url' ~ '^https?://'
             and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = s.provider_id and f.kind = 'english_policy' and f.url = e->>'url')) x
   where x.rn = 1
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = x.provider_id and pp.kind = 'english_policy' and pp.status in ('approved', 'proposed'))
     and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = x.provider_id and f.kind = 'english_policy' and f.status in ('found', 'reading'))
     and (select count(*) from pipeline.provider_fact_sources f where f.provider_id = x.provider_id and f.kind = 'english_policy') < v_max
     and exists (select 1 from catalogue.courses c where c.provider_id = x.provider_id and c.lifecycle_status = 'active')
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)
  on conflict (provider_id, kind, url) do nothing;
  get diagnostics v_att = row_count;
  -- read central English pages go to the pinned AI (the database checks each quote; policy-auto-approve decides)
  for r in select distinct f.provider_id from pipeline.provider_fact_sources f
            where f.kind = 'english_policy' and f.status in ('read', 'parsed', 'no_values')
              and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = f.provider_id and pp.kind = 'english_policy' and pp.status = 'approved') loop
    v_q := v_q + security.central_ai_enqueue_v1(r.provider_id);
  end loop;
  return jsonb_build_object('attached', v_att, 'queued_for_ai', v_q);
end $function$;
revoke execute on function security.central_pages_attach_v1() from public, anon, authenticated;

select pg_temp.edit_once('security.policy_auto_approve_v1()', 'ebf52656ee474c062f46a09d5b8a45a6', array[
  array[$o$             join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id and f.in_focus
            where x.status = 'proposed' and x.parser like 'ai:%' and x.kind in ('english_policy', 'intake_calendar')
            order by f.rank, x.created_at loop$o$,
        $n$             left join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id
            where x.status = 'proposed' and x.parser like 'ai:%' and x.kind in ('english_policy', 'intake_calendar')
              -- 23 Oct 2026 (Platform Admin 12:40): English rules for every university, not only the focus list
              and (coalesce(f.in_focus, false)
                   or (x.kind = 'english_policy' and coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve_english_all'), false)))
            order by f.rank nulls last, x.created_at loop$n$]]);

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('central-attach', 'Course pages', 35, 'University English rules: find and read',
  'Every hour at :48: for each university with no approved English rule, attaches the best suggested central English page not yet tried (score at least Central pages: attach suggestions from score, at most Central pages: pages tried a university) and sends read central English pages to the pinned AI; job policy-auto-approve approves readings with every score quoted.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('central-attach', '48 * * * *', $$select security.central_pages_attach_v1()$$);

-- Why values are missing: whether more central pages are left to try ---------------------------------------------------------------
select pg_temp.edit_once('security.gap_causes_snapshot_v1()', 'f2edb55a463d98e16cdbe6d589d606da', array[
  array[$o$     group by k.provider_id, k.kind;$o$,
        $n$     group by k.provider_id, k.kind;
  -- 23 Oct 2026 12:40: a rule not found or giving no values is automatic while suggested central pages are left to try
  update _grule r set state = r.state || ' (more central pages to try)'
   where r.kind = 'english_policy' and r.state in ('not found', 'gives no values')
     and exists (select 1 from pipeline.provider_central_search s cross join lateral jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
                  where s.provider_id = r.provider_id and e->>'kind' = 'english_policy' and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
                    and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = s.provider_id and f.kind = 'english_policy' and f.url = e->>'url'))
     and (select count(*) from pipeline.provider_fact_sources f where f.provider_id = r.provider_id and f.kind = 'english_policy') < security.pipeline_num_v1('central.attach_per_kind', 3);$n$],
  array[$o$           when z.cause like 'AI:%approved' then$o$,
        $n$           when z.cause like 'AI:%(more central pages to try)' then 'next suggested central page read by AI and approved when every score is quoted (jobs central-attach, central-ai, policy-auto-approve)'
           when z.cause like 'AI:%approved' then$n$],
  array[$o$              or (z.cause like 'AI:%' and (z.cause like '%approved' or$o$,
        $n$              or (z.cause like 'AI:%' and z.cause not like '%(more central pages to try)' and (z.cause like '%approved' or$n$]]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.central_pages_attach_v1', 'Layer 2', 'Job central-attach: next suggested central English page per university without a rule; read pages to the AI', 'active', '{}', '20261023015000')
on conflict (kind, name) do nothing;

select security.central_pages_attach_v1();
select security.gap_causes_snapshot_v1();
select 'CA fees, AU scraper, NZ adapter title, university English rules found and approved automatically' ok;
do $t$ begin
  raise exception 'DRYRUN OK %', jsonb_build_object(
    'attached', (select jsonb_agg(left(p.display_name,20)||': '||left(f.url,70)) from pipeline.provider_fact_sources f join catalogue.providers p on p.id=f.provider_id where f.kind='english_policy' and f.status='found' and f.created_at > now() - interval '1 minute' and security.coverage_country(f.provider_id)='NZ'),
    'adapter_title_fee', (select count(*) from pipeline.coverage_course_pages g where g.identity_basis='adapter_title' and security.coverage_country(g.provider_id)='NZ' and security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'tuition')),
    'au_adapter_title_english', (select count(*) filter (where security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'english')) || '/' || count(*) from pipeline.coverage_course_pages g where g.identity_basis='adapter_title' and security.coverage_country(g.provider_id)='AU'),
    'ca_exact_fee', (select count(*) from pipeline.coverage_course_pages g where g.identity_basis='exact_title' and security.coverage_country(g.provider_id)='CA' and security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'tuition')),
    'settings', (select jsonb_object_agg(key, value) from pipeline.platform_toolset_settings where key in ('fees.countries','pages.render_countries')),
    'nz_english_ai', (select jsonb_agg(jsonb_build_object('c', cause, 'n', courses, 'a', automatic)) from pipeline.gap_cause_snapshots where at=(select max(at) from pipeline.gap_cause_snapshots) and country_code='NZ' and attribute='english' and cause like 'AI:%')); end $t$;
