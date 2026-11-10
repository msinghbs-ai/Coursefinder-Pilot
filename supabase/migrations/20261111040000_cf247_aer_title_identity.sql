-- CF-247 F-AER.01 course-page identity for entry requirements: verified own-site title AND study-level match (Platform Admin decision 10 Nov 2026 ~23:45 AEDT,
-- AER recovery pack decision 4: "Allow verified own-site and level matching").
-- The decision's controls: the page belongs to the verified provider's official website; the course title and study level match; a unique, unambiguous match with independently
-- validated provider ownership; generic, conflicting, cross-provider or uncertain matches rejected; the evidence for why the association was accepted is kept; applied to the
-- 168 providers / 1,169 courses identified (security.aer_no_source_route_v1 route course_pages_unconfirmed), subject to validation.
-- Evidence (production, read only, 10 Nov 2026 23:5x AEDT): bound pages of those providers by identity basis: exact_title 754 courses / 151 providers (score margin >= 0.1 on 320),
--   degree_name 170 / 6, title_level 157 / 23, no basis 100 / 22, adapter_title 71 / 7. Ties exist (Federation: score 0.857 = runner-up 0.857) and are refused.
-- Rule security.aer_title_identity_ok_v1(course) passes only when ALL hold (each failure is named):
--   switch aer.title_identity_on = 1; the provider is in aer.eligible_countries; the course is active and has a study level; the bound page's basis is in aer.title_identity_bases;
--   the page host is one of the provider's own verified hosts (security.provider_hosts_v1: website, governed aliases, approved extra domains; subdomains of them) and not a shared host
--   (security.l4_shared_hosts_v1); no other provider has a page bound at the same address; no other active course of the provider is bound to the same address;
--   unique: no runner-up, or a score margin of at least aer.title_identity_min_margin over it; the page's h1 (or title before " | ") equals the course title letter for letter
--   (case, spacing and punctuation ignored; a leading course code allowed); and the page heading names the course's study level (credential words of ref.study_levels).
-- Where it is used (md5-guarded edits, each adds the rule as an alternative to the existing identity bases; nothing that passed before is refused now):
--   security.aer_course_population_v1(uuid) (what the scheduled reader may read), security.enrich_entry_record_v1(bigint,jsonb) (whether a finished read is kept),
--   security.aer_machine_check_v1(uuid) (machine admission; the rule's evidence is recorded in the checks as title_identity).
-- A read admitted this way still passes every other gate (E13, D-R3, quote on page) and, in machine mode, every aer-machine-v1 check. No AI or Firecrawl call is made by this migration.
-- Reversal: aer.title_identity_on = 0 (the rule answers false; behaviour is exactly as before).
-- Replaces: the three functions above (same names; md5-guarded edits)
-- Retires: nothing.

do $g$
begin
  if md5(pg_get_functiondef('security.aer_course_population_v1(uuid)'::regprocedure)) <> 'dd90b81a6064e4994186bc570031081d' then raise exception 'aer_course_population_v1 differs from dd90b81a'; end if;
  if md5(pg_get_functiondef('security.enrich_entry_record_v1(bigint,jsonb)'::regprocedure)) <> 'b39d83dfd8bbd3c7e4708a6904c6599d' then raise exception 'enrich_entry_record_v1 differs from b39d83df'; end if;
  if md5(pg_get_functiondef('security.aer_machine_check_v1(uuid)'::regprocedure)) <> 'a46e753c5bc56a7032632ce936aab618' then raise exception 'aer_machine_check_v1 differs from a46e753c'; end if;
  if to_regprocedure('security.provider_hosts_v1(uuid)') is null or to_regprocedure('security.l4_shared_hosts_v1()') is null or to_regprocedure('security.site_host_v1(text)') is null then
    raise exception 'host functions missing';
  end if;
end $g$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.title_identity_on', 'Entry requirements: course pages matched by title and level on the provider''s own site',
  '1 lets a course page matched by title (exact_title, title_level, degree_name, adapter_title) be read and admitted for entry requirements when it is on the provider''s own verified website, the heading equals the course title, the heading names the course''s study level and the match is unique. 0: only code-proved and hand-confirmed pages.',
  'number', to_jsonb(1), 0, 1, 'switch', 1498, 'Entry requirements', 'security.aer_title_identity_ok_v1',
  'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 4): allow verified own-site and level matching'),
 ('pipeline', 'aer.title_identity_bases', 'Entry requirements: title-match bases accepted with the own-site and level checks', 'Identity bases the rule aer_title_identity_ok_v1 considers.',
  'list', '["exact_title", "title_level", "degree_name", "adapter_title"]'::jsonb, null, null, 'bases', 1499, 'Entry requirements', 'security.aer_title_identity_ok_v1',
  'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 4)'),
 ('pipeline', 'aer.title_identity_min_margin', 'Entry requirements: lowest score margin over the runner-up page', 'A title-matched page must beat the next candidate page by at least this score (or have none).',
  'number', to_jsonb(0.1), 0, 1, 'score', 1500, 'Entry requirements', 'security.aer_title_identity_ok_v1',
  'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 4): a unique, unambiguous match')
on conflict (toolset_key, key) do nothing;

create or replace function security.aer_title_identity_ok_v1(p_course uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare c record; g pipeline.coverage_course_pages%rowtype; v_host text; v_hosts text[]; v_h1 text; v_tn text; v_hn text; v_lvl text; v_kw text; v_margin numeric;
begin
  if security.pipeline_num_v1('aer.title_identity_on', 0) < 1 then return jsonb_build_object('ok', false, 'why', 'switch_off'); end if;
  select x.id, x.provider_id, x.canonical_title, x.lifecycle_status, l.code lvl_code, k.iso_alpha2 cc into c
    from catalogue.courses x join catalogue.providers p on p.id = x.provider_id left join ref.countries k on k.id = p.country_id left join ref.study_levels l on l.id = x.study_level_id
   where x.id = p_course;
  if c.id is null or c.lifecycle_status <> 'active' then return jsonb_build_object('ok', false, 'why', 'course_not_active'); end if;
  if not coalesce(security.toolset_setting('pipeline', 'aer.eligible_countries'), '[]'::jsonb) ? coalesce(c.cc, '') then return jsonb_build_object('ok', false, 'why', 'country_not_in_scope'); end if;
  if c.lvl_code is null then return jsonb_build_object('ok', false, 'why', 'no_study_level'); end if;
  select * into g from pipeline.coverage_course_pages p where p.course_id = p_course and p.status = 'bound' order by p.bound_at desc nulls last limit 1;
  if g.course_id is null then return jsonb_build_object('ok', false, 'why', 'no_bound_page'); end if;
  if not coalesce(security.toolset_setting('pipeline', 'aer.title_identity_bases'), '[]'::jsonb) ? coalesce(g.identity_basis, '') then
    return jsonb_build_object('ok', false, 'why', 'basis_not_title', 'basis', g.identity_basis);
  end if;
  -- own verified site, not a shared host, no other provider at this address
  v_host := security.site_host_v1(g.url); v_hosts := security.provider_hosts_v1(c.provider_id);
  if v_host is null or not exists (select 1 from unnest(v_hosts) h where v_host = h or v_host like '%.' || h) then
    return jsonb_build_object('ok', false, 'why', 'not_own_site', 'host', v_host, 'provider_hosts', to_jsonb(v_hosts));
  end if;
  if v_host = any (coalesce(security.l4_shared_hosts_v1(), '{}'::text[])) then return jsonb_build_object('ok', false, 'why', 'shared_host', 'host', v_host); end if;
  if exists (select 1 from pipeline.coverage_course_pages o where o.url = g.url and o.status = 'bound' and o.provider_id <> c.provider_id) then
    return jsonb_build_object('ok', false, 'why', 'cross_provider_page');
  end if;
  if exists (select 1 from pipeline.coverage_course_pages o join catalogue.courses oc on oc.id = o.course_id and oc.lifecycle_status = 'active'
              where o.url = g.url and o.status = 'bound' and o.course_id <> p_course) then
    return jsonb_build_object('ok', false, 'why', 'page_bound_to_another_course');
  end if;
  -- unique and unambiguous
  v_margin := case when g.runner_up is null then null else coalesce(g.score, 0) - g.runner_up end;
  if v_margin is not null and v_margin < security.pipeline_num_v1('aer.title_identity_min_margin', 0.1) then
    return jsonb_build_object('ok', false, 'why', 'ambiguous_match', 'score', g.score, 'runner_up', g.runner_up);
  end if;
  -- the page heading equals the course title (letters and digits only; a leading course code allowed)
  v_h1 := coalesce(nullif(btrim(g.candidates->>'h1'), ''), nullif(btrim(split_part(coalesce(g.candidates->>'page_title', ''), ' | ', 1)), ''));
  if v_h1 is null then return jsonb_build_object('ok', false, 'why', 'no_page_heading'); end if;
  v_tn := regexp_replace(lower(coalesce(c.canonical_title, '')), '[^a-z0-9]+', '', 'g');
  v_hn := regexp_replace(lower(v_h1), '[^a-z0-9]+', '', 'g');
  if length(v_tn) < 6 then return jsonb_build_object('ok', false, 'why', 'generic_title'); end if; -- fixed: a title of under six letters is too generic to identify a course
  if not (v_hn = v_tn or (right(v_hn, length(v_tn)) = v_tn and left(v_hn, length(v_hn) - length(v_tn)) ~ '^[a-z]{0,5}[0-9]{2,8}[a-z]{0,2}$')) then -- fixed: the shape of a leading course code (e.g. CHC52025, DHY5)
    return jsonb_build_object('ok', false, 'why', 'title_mismatch', 'h1', v_h1, 'title', c.canonical_title);
  end if;
  -- the heading names the course's study level (credential words)
  v_lvl := c.lvl_code;
  v_kw := case
            when v_lvl in ('bachelor', 'bachelor_honours') then '\mbachelor'
            when v_lvl like 'masters%' then '\mmaster'
            when v_lvl = 'graduate_certificate' then '\mgraduate certificate'
            when v_lvl = 'graduate_diploma' then '\mgraduate diploma'
            when v_lvl = 'advanced_diploma' then '\madvanced diploma'
            when v_lvl = 'diploma' then '\mdiploma'
            when v_lvl = 'associate_degree' then '\massociate degree'
            when v_lvl = 'certificate_i' then '\mcertificate i\M'
            when v_lvl = 'certificate_ii' then '\mcertificate ii\M'
            when v_lvl = 'certificate_iii' then '\mcertificate iii\M'
            when v_lvl = 'certificate_iv' then '\mcertificate iv\M'
            when v_lvl = 'doctorate' then '\m(doctor|phd)'
            when v_lvl = 'foundation' then '\mfoundation'
            else null end; -- fixed: credential words of ref.study_levels; a level with no credential word cannot be proved from a heading
  if v_kw is null then return jsonb_build_object('ok', false, 'why', 'level_not_provable', 'level', v_lvl); end if;
  if lower(v_h1) !~ v_kw then return jsonb_build_object('ok', false, 'why', 'level_mismatch', 'level', v_lvl, 'h1', v_h1); end if;
  if v_lvl = 'diploma' and lower(v_h1) ~ '\m(graduate|advanced) diploma' then return jsonb_build_object('ok', false, 'why', 'level_mismatch', 'level', v_lvl, 'h1', v_h1); end if;
  return jsonb_build_object('ok', true, 'rule', 'aer-title-identity-v1', 'basis', g.identity_basis, 'url', g.url, 'host', v_host, 'h1', v_h1, 'level', v_lvl,
                            'score', g.score, 'runner_up', g.runner_up);
end $f$;
comment on function security.aer_title_identity_ok_v1(uuid) is 'CF-247 F-AER.01 (read only): whether a course''s title-matched bound page may be used for entry requirements: own verified provider host (not shared, no other provider or course at the address), unique match (margin aer.title_identity_min_margin), heading equals the course title, heading names the study level. Answers why it refused; the evidence when it passes. Off while aer.title_identity_on is 0.';
revoke all on function security.aer_title_identity_ok_v1(uuid) from public, anon, authenticated;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_old text, p_new text) returns text language plpgsql as $e$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_cnt int;
begin
  if md5(v_def) <> p_before then raise exception '% differs from %', p_sig, p_before; end if;
  v_cnt := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_cnt <> 1 then raise exception '%: the anchored text occurs % times', p_sig, v_cnt; end if;
  execute replace(v_def, p_old, p_new);
  return p_sig || ' -> ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $e$;

select pg_temp.edit_once('security.aer_course_population_v1(uuid)', 'dd90b81a6064e4994186bc570031081d',
  $o$where security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')$o$,
  $n$where (security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements') or coalesce((security.aer_title_identity_ok_v1(c.id)->>'ok')::boolean, false)) -- 20261111040000: own-site title and level match (Platform Admin decision 10 Nov 2026)$n$);

select pg_temp.edit_once('security.enrich_entry_record_v1(bigint,jsonb)', 'b39d83dfd8bbd3c7e4708a6904c6599d',
  $o$if g.provider_id is null or not security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'entry_requirements') then$o$,
  $n$if g.provider_id is null or not (security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'entry_requirements') or coalesce((security.aer_title_identity_ok_v1(i.course_id)->>'ok')::boolean, false)) then -- 20261111040000: own-site title and level match$n$);

select pg_temp.edit_once('security.aer_machine_check_v1(uuid)', 'a46e753c5bc56a7032632ce936aab618',
  $o$  if not security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements') then$o$,
  $n$  if not (security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements') or coalesce((security.aer_title_identity_ok_v1(c.id)->>'ok')::boolean, false)) then -- 20261111040000$n$);

select pg_temp.edit_once('security.aer_machine_check_v1(uuid)', md5(pg_get_functiondef('security.aer_machine_check_v1(uuid)'::regprocedure)),
  $o$jsonb_build_object('identity_basis', g.identity_basis, 'source_url'$o$,
  $n$jsonb_build_object('identity_basis', g.identity_basis, 'title_identity', case when security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements') then null else security.aer_title_identity_ok_v1(c.id) end, 'source_url'$n$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_title_identity_ok_v1', 'Layer 2', 'Own-site title and study-level identity for entry requirements', 'active', '{}', '20261111040000')
on conflict do nothing;

do $p$
begin
  if position('aer_title_identity_ok_v1' in pg_get_functiondef('security.aer_course_population_v1(uuid)'::regprocedure)) = 0 then raise exception 'post-check: population'; end if;
  if position('aer_title_identity_ok_v1' in pg_get_functiondef('security.enrich_entry_record_v1(bigint,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: record'; end if;
  if position('title_identity' in pg_get_functiondef('security.aer_machine_check_v1(uuid)'::regprocedure)) = 0 then raise exception 'post-check: machine check'; end if;
end $p$;
