-- CF-247 F-OPS.05 (Platform Admin directive, 10 Nov 2026, "Simplify production controls"): reduce the settings a person has to maintain to the minimum.
--
-- What this does (one nullable column, a backfill for the provider-description controls, and one screen read; no new setting, job, table or consumer object):
--   1 pipeline.platform_toolset_settings.control_class text, null or one of: 'human' (a person decides it: switches, scope, spend and call ceilings, admission policy, policy word lists),
--     'automatic' (software-tuned inside the range the row already carries: timings, retries, queue and concurrency, thresholds, text limits, patterns, registry rules, report and preview keys),
--     'retiring' (switched off in favour of a newer control; kept, never deleted). Null means not yet classified: the screen treats it as human, so nothing changes for the other toolsets.
--   2 the backfill (provider descriptions only): the 19 human keys below (pdesc.provider_keys is a scope pin a person decides, so it is human); every other pdesc.* key, batch.provider_description and reading.provider_* key is automatic. Only rows still null are set,
--     so a later change made by the Platform Admin is never overwritten by applying this again.
--   3 public.admin_settings_register_read(): each setting also carries control_class and replaced_by (the component register row of a retiring setting, if one exists). Additive: no key is removed
--     or renamed. This is an admin screen read, not a website, Zoho or api-schema object (G3 not touched).
-- Retiring: none is set. pdesc.provider_keys (human: a live scope pin) is still read by security.provider_description_scope_v1 (the picker's scope test) and by the run and funnel functions; pdesc.queue_per_run (automatic) is still read by
--   security.provider_description_enqueue_v1 and the manual cohort functions. Both stay 'automatic' until a change removes their last reader (then that change marks them retiring and registers it).
-- Automatic values stay inside their own range: the row's min_value and max_value are enforced by the settings write, and by the ops guard while a remedy runs (security.ops_guard_settings_v1). The
--   screen keeps them visible and editable with a reason.
-- Live definition this change edits (pg_proc.prosrc md5, read 10 Nov 2026 AEDT): public.admin_settings_register_read() e340e9cf37475ea2e8310b6fb0401931. The migration stops if the live body is neither this
--   one nor one that already carries control_class; applying it twice changes nothing.
-- Consumer API (G3): not touched. No operational number is written into code (G2). No job is added (G1).
-- Replaces: nothing
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration.

do $g$
begin
  if to_regclass('pipeline.platform_toolset_settings') is null then raise exception 'required pipeline.platform_toolset_settings is missing'; end if;
  if to_regprocedure('public.admin_settings_register_read()') is null then raise exception 'required public.admin_settings_register_read() is missing'; end if;
end $g$;

-- 1. the column ------------------------------------------------------------------------------------------------------------------------------------------------------
alter table pipeline.platform_toolset_settings add column if not exists control_class text check (control_class in ('human', 'automatic', 'retiring'));
comment on column pipeline.platform_toolset_settings.control_class is 'CF-247 F-OPS.05: who maintains the setting. human = a person decides it; automatic = software-tuned within the row''s own min_value and max_value (still visible and editable with a reason); retiring = switched off for a newer control (kept, never deleted). Null = not yet classified, shown as human.';

-- 2. the backfill: provider descriptions only; only rows not yet classified -------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set control_class = 'human'
 where toolset_key = 'pipeline' and control_class is null
   and key in ('pdesc.enabled', 'pdesc.countries', 'pdesc.provider_types', 'pdesc.ai_usd_max', 'pdesc.firecrawl_reads_max', 'pdesc.acquire_firecrawl', 'pdesc.acquire_direct',
               'pdesc.machine_admit_on', 'pdesc.registry_factual_on', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr', 'pdesc.machine_numbers_allowed',
               'pdesc.evidence_claim_words', 'pdesc.pending_max', 'reading.provider_quote_fragments_on', 'pdesc.superlatives', 'pdesc.claim_words', 'pdesc.machine_neutral_words', 'pdesc.provider_keys');
update pipeline.platform_toolset_settings set control_class = 'automatic'
 where toolset_key = 'pipeline' and control_class is null
   and (key like 'pdesc.%' or key like 'reading.provider\_%' escape '\' or key = 'batch.provider_description');

-- 3. the screen read carries the class (and, for a retiring setting, what replaced it) -------------------------------------------------------------------------------
do $r$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'public.admin_settings_register_read()'::regprocedure);
begin
  -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if v_src like '%control_class%' then return; end if;
  if md5(v_src) <> 'e340e9cf37475ea2e8310b6fb0401931' then raise exception 'live public.admin_settings_register_read() differs from the definition this change edits (body md5 %)', md5(v_src); end if;
  execute $def$
create or replace function public.admin_settings_register_read()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'sections', (select coalesce(jsonb_agg(jsonb_build_object('section', z.section, 'settings', z.settings) order by z.first_sort), '[]'::jsonb)
                   from (select s.section, min(s.sort) first_sort,
                                jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                                          'unit', s.unit, 'used_by', s.used_by, 'reason', s.reason, 'updated_at', s.updated_at,
                                          'control_class', s.control_class,
                                          'replaced_by', (select r.replaced_by from pipeline.component_register r where r.name = s.toolset_key || '.' || s.key and r.status = 'retiring' limit 1)) order by s.sort, s.key) settings
                           from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' group by s.section) z),
    'check', (select coalesce(jsonb_agg(jsonb_build_object('job', c.jobname, 'detail', c.detail)), '[]'::jsonb) from security.controls_check_v1() c),
    'jobs', (select count(*) from cron.job where active));
end $function$
  $def$;
end $r$;

-- 4. post-check ----------------------------------------------------------------------------------------------------------------------------------------------------------
do $p$
declare v_h int; v_n int;
begin
  select count(*) into v_h from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and control_class = 'human'
     and key in ('pdesc.enabled', 'pdesc.countries', 'pdesc.provider_types', 'pdesc.ai_usd_max', 'pdesc.firecrawl_reads_max', 'pdesc.acquire_firecrawl', 'pdesc.acquire_direct',
                 'pdesc.machine_admit_on', 'pdesc.registry_factual_on', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr', 'pdesc.machine_numbers_allowed',
                 'pdesc.evidence_claim_words', 'pdesc.pending_max', 'reading.provider_quote_fragments_on', 'pdesc.superlatives', 'pdesc.claim_words', 'pdesc.machine_neutral_words', 'pdesc.provider_keys');
  if v_h <> 19 then raise exception 'F-OPS.05 post-check: % of 19 human keys classified', v_h; end if;
  select count(*) into v_n from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and control_class is null
     and (key like 'pdesc.%' or key like 'reading.provider\_%' escape '\' or key = 'batch.provider_description');
  if v_n <> 0 then raise exception 'F-OPS.05 post-check: % provider-description setting(s) left unclassified', v_n; end if;
  if (select p.prosrc from pg_proc p where p.oid = 'public.admin_settings_register_read()'::regprocedure) not like '%control_class%' then raise exception 'F-OPS.05 post-check: the settings read does not carry control_class'; end if;
end $p$;
