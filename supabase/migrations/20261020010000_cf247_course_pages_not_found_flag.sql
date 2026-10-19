-- CF-247 (20 Oct 2026). Platform Admin 06:33 (after re-find wave 1): "show me the list of success and failed unis - flag the failed one with
-- reason so they dont get tried again, only operator and above can unflag them. is there scheduled tasks to probe the unflagged and newly
-- added uni or provider to auto adapter and do data ingestion?"
-- 1 New provider flag reason course_pages_not_found (hard). While raised, the provider is out of course-page search, site discovery and AI
--   page matching (security.enrich_focus_v1), and Build adapter leaves it out of a build; nothing spends Firecrawl or AI on it.
-- 2 A Pipeline Operator or above (setting flag.course_pages_release_min_rank, 4) may release this reason; other reasons keep
--   flag.manage_min_rank. admin_flags('summary') returns release_codes so the Flags screen shows Release to them.
-- 3 Released: its onboarding starts again from the website step and its site discovery is due now (security.flag_requeue_v1).
-- 4 Raised now for the 54 providers of re-find wave 1 that found no usable course pages (evidence: site map count, method, pages read).
--   ACBT Education and Harvard International College are not flagged: their adapters were built and wait for a person.
-- Replaces: security.enrich_focus_v1(uuid), security.flag_requeue_v1(bigint) (md5-guarded); public.admin_flags and
--   public.admin_adapter_build (one line each, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'flag.course_pages_release_min_rank', 'Lowest role that may release a "course pages not found" flag', 'Role rank (4 Pipeline Operator, 5 PIM Admin, 6 Platform Admin) that may release a provider held because its course pages could not be found. Other flags keep the general setting.', 'number', to_jsonb(4), 3, 6, 'rank', 327, 'CF-247, Platform Admin 20 Oct 2026 06:33 "only operator and above can unflag them"', 'Flags', 'public.admin_flags')
on conflict (toolset_key, key) do nothing;

do $chk$ begin
  if md5(pg_get_functiondef('security.enrich_focus_v1(uuid)'::regprocedure)) <> '580b9ae121390a4505d103af063ee8e5' then raise exception 'live security.enrich_focus_v1 differs'; end if;
  if md5(pg_get_functiondef('security.flag_requeue_v1(bigint)'::regprocedure)) <> '09003b3f2a83c4837e306a7d4f02b473' then raise exception 'live security.flag_requeue_v1 differs'; end if;
end $chk$;

CREATE OR REPLACE FUNCTION security.enrich_focus_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- page search runs for every provider when the setting is 0, for providers outside Australia, and for the Australian focus providers
  -- CF-247 19 Oct 2026: and for a provider in a re-find wave (Layer 2 > Build adapter, wave named "refind-...")
  -- CF-247 20 Oct 2026: never for a provider held because its course pages could not be found (until a person releases it)
  select not security.flag_provider_held_v1(p_provider_id, array['course_pages_not_found'])
     and (security.pipeline_num_v1('enrich.focus_top_n', 50) = 0
      or coalesce(security.coverage_country(p_provider_id), '') <> 'AU'
      or exists (select 1 from pipeline.enrich_focus_providers f where f.provider_id = p_provider_id and f.in_focus)
      or exists (select 1 from pipeline.adapter_builds b where b.provider_id = p_provider_id and b.wave like 'refind-%'))
$function$;

CREATE OR REPLACE FUNCTION security.flag_requeue_v1(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.enrichment_flags; v_jobid bigint;
begin
  select * into f from pipeline.enrichment_flags where id = p_id;
  if f.reason_code in ('logo_not_found', 'site_unreachable') or (f.entity = 'provider' and f.reason_code = 'manual_hold') then
    update pipeline.provider_logo_finds set status = 'queued', updated_at = now() where provider_id = f.provider_id and status in ('not_found', 'failed');
    update pipeline.provider_central_search set state = 'queued', attempts = 0, leased_until = null, updated_at = now()
     where provider_id = f.provider_id and state in ('queued', 'failed') and f.reason_code <> 'logo_not_found';
    return case when f.reason_code = 'logo_not_found' then 'logo finder' else 'logo finder and central pages' end;
  elsif f.reason_code in ('central_not_due', 'central_budget') then
    update pipeline.provider_central_search set state = 'queued', attempts = 0, leased_until = null, updated_at = now() where provider_id = f.provider_id;
    return 'central pages';
  elsif f.entity = 'provider' and f.reason_code = 'course_pages_not_found' then
    -- CF-247 20 Oct 2026: released by a person: onboarding again from the website step, and its site mapped again
    update pipeline.provider_onboarding ob set status = 'website', stop_reason = null, step_started_at = now(), job_id = null,
           note = 'Released by a person (course pages not found); starting again from the website.', updated_at = now()
     where ob.id = (select o2.id from pipeline.provider_onboarding o2 where o2.provider_id = f.provider_id order by o2.created_at desc limit 1)
       and ob.status in ('stopped', 'done', 'cancelled');
    update pipeline.coverage_provider_discovery set status = 'pending', attempts = 0, next_due_at = now(), leased_until = null, updated_at = now()
     where provider_id = f.provider_id;
    return 'onboarding and site discovery';
  elsif f.entity = 'job' and f.reason_code in ('idle_paused', 'manual_hold') then
    select jobid into v_jobid from cron.job where jobname = f.entity_key;
    if v_jobid is not null then perform cron.alter_job(v_jobid, active := true); end if;
    update pipeline.job_idle_watch set paused_at = null, resumed_at = now() where jobname = f.entity_key;
    return 'job switched on';
  elsif f.entity = 'course' then
    return 'the next Enrich fields task includes it';
  end if;
  return null;
end $function$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('public.admin_flags(text,jsonb)', '89a074e62d3fb96676d7caf49b31309f', array[
  array['if not v_can then raise exception ''your role cannot change flags''',
        'if not v_can and not (p_action = ''release'' and v_rank >= security.pipeline_num_v1(''flag.course_pages_release_min_rank'', 4)::int  -- CF-247 20 Oct 2026: operators release "course pages not found"
        and not exists (select 1 from jsonb_array_elements_text(coalesce(p_args->''ids'', ''[]''::jsonb)) i join pipeline.enrichment_flags x on x.id = i::bigint where x.reason_code <> ''course_pages_not_found'')) then raise exception ''your role cannot change flags'''],
  array['return jsonb_build_object(''can_change'', v_can,
      ''by_reason'',',
        'return jsonb_build_object(''can_change'', v_can,
      ''release_codes'', case when v_can then ''["*"]''::jsonb when v_rank >= security.pipeline_num_v1(''flag.course_pages_release_min_rank'', 4)::int then ''["course_pages_not_found"]''::jsonb else ''[]''::jsonb end,
      ''by_reason'',']
]);

select pg_temp.edit_once('public.admin_adapter_build(text,jsonb)', '9ffbcbcb8f8fd6a7b40c9c51f96dcf6c', array[
  array['if cardinality(v_pids) = 0 then raise exception ''choose universities''; end if;
    v_open :=',
        'v_pids := array(select i from unnest(v_pids) i where not security.flag_provider_held_v1(i, array[''course_pages_not_found'']));  -- CF-247 20 Oct 2026: held providers are left out
    if cardinality(v_pids) = 0 then raise exception ''choose universities (those held because their course pages could not be found are left out until released)''; end if;
    v_open :=']
]);

-- 4 the 54 providers of re-find wave 1 without usable course pages
select security.flag_raise_v1('provider', b.provider_id::text, b.provider_id, '', 'course_pages_not_found',
         case when coalesce(d.status, '') = 'mapped' then
                format('Re-find wave 1 (19 Oct 2026): the site %s was mapped (%s addresses) but no course page could be matched and read (%s read for %s active courses). Not tried again until a person releases it; check the website or add course page addresses in the Adapter builder (2.1) first.',
                       p.website, coalesce(d.url_count, 0), (select count(*) from pipeline.coverage_course_pages g where g.provider_id = b.provider_id and g.read_status = 'read'),
                       (select count(*) from catalogue.courses c where c.provider_id = b.provider_id and c.lifecycle_status = 'active'))
              else
                format('Re-find wave 1 (19 Oct 2026): the site map of %s returned no course pages (%s addresses), after earlier course-page searches also found none. Not tried again until a person releases it; check the website or add course page addresses in the Adapter builder (2.1) first.',
                       p.website, coalesce(d.url_count, 0)) end,
         'hard', 'cf247-refind-1', 'auto',
         jsonb_build_object('wave', 'refind-1', 'site', p.website, 'discovery', d.status, 'method', d.method, 'addresses', d.url_count,
                            'pages_read', (select count(*) from pipeline.coverage_course_pages g where g.provider_id = b.provider_id and g.read_status = 'read'),
                            'decision', 'Platform Admin 20 Oct 2026 06:33'),
         null, null)
  from pipeline.adapter_builds b join catalogue.providers p on p.id = b.provider_id
  left join pipeline.coverage_provider_discovery d on d.provider_id = b.provider_id
 where b.wave = 'refind-1'
   and not exists (select 1 from pipeline.uni_adapters u where u.provider_id = b.provider_id);
