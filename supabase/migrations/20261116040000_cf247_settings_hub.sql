-- CF-247 Settings Hub (Phase 3 of the UI/UX and settings simplification; Platform Admin 16 Nov 2026 05:12 decisions 2 and 4, and 05:23
-- "proceed directly into Phase 2 and Phase 3"; audit claude/ui-ux-settings-audit-2026-11-15.md §4.1, §6, §7.5 and §8).
--   1. pipeline.settings_hub_groups (new): which of the five hub groups a toolset or section belongs to (AI & Models, Schedulers & Cadence,
--      Circuit Breakers, Consumer APIs, Pipeline steps). A section row wins over its toolset's '*' row; anything not listed is Pipeline steps.
--      security.settings_hub_group_v1(toolset, section) reads it. Grouping lives beside the settings, so no setting or key is renamed.
--   2. public.admin_settings_register_read() (Settings › Settings) also gives each section its hub_group and read_only (true for Consumer APIs),
--      and each setting 'changed' (a person changed it: updated_by is set). Additive: no key is removed or renamed. md5-guarded edit in place.
--   3. public.admin_toolsets_write('setting'): a setting in the Consumer APIs group (the Website API and Zoho API sections) is read-only by default
--      (decision 4). A change is refused, recorded in pipeline.admin_control_events (action 'refused') and answered {ok: false, refused:
--      'consumer_api_read_only'}, unless the call carries the explicit unlock ("unlock": "consumer_api"), which the screen sends only after the
--      Platform Admin ticks "Unlock: this is an approved change"; the unlock is kept in the change log. Every other setting is written as before.
--      md5-guarded edit in place.
-- These are admin screen reads and writes, not consumer API objects (G3): the consumer API reads the setting values, which nothing here changes.
-- G1: no job. G2: no number written into code. G3: security.consumer_api_check_v1() before and after.
-- Replaces: public.admin_settings_register_read() and public.admin_toolsets_write(text, jsonb) (same names and signatures; md5-guarded edits).
-- Retires: nothing. The Settings screen is reorganised in place (SettingsRegister), so links and anchors keep working. Nothing is dropped or deleted.

set local lock_timeout = '5s';

-- 1. The hub groups ------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.settings_hub_groups (
  toolset_key text not null,
  section text not null,
  hub_group text not null check (hub_group in ('AI & Models', 'Schedulers & Cadence', 'Circuit Breakers', 'Consumer APIs', 'Pipeline steps')),
  primary key (toolset_key, section));
comment on table pipeline.settings_hub_groups is 'CF-247 Settings Hub (16 Nov 2026): the hub group of a toolset (section ''*'') or of one of its sections; read by security.settings_hub_group_v1. Consumer APIs is read-only (decision 4).';
alter table pipeline.settings_hub_groups enable row level security;
insert into pipeline.settings_hub_groups(toolset_key, section, hub_group) values
  ('pipeline', '*', 'Pipeline steps'),
  ('firecrawl', '*', 'Pipeline steps'),
  ('serper', '*', 'Pipeline steps'),
  ('scrapingbee', '*', 'Pipeline steps'),
  ('openrouter', '*', 'AI & Models'),
  ('edge_functions', '*', 'Circuit Breakers'),
  ('scheduled_jobs', '*', 'Circuit Breakers'),
  ('firecrawl', 'Daily budget', 'Circuit Breakers'),
  ('firecrawl', 'Notices', 'Circuit Breakers'),
  ('pipeline', 'Website API', 'Consumer APIs'),
  ('pipeline', 'Zoho API', 'Consumer APIs'),
  ('pipeline', 'AI answer limits', 'AI & Models'),
  ('pipeline', 'AI evaluation', 'AI & Models'),
  ('pipeline', 'Job sizes', 'Schedulers & Cadence'),
  ('pipeline', 'Re-read and retry', 'Schedulers & Cadence'),
  ('pipeline', 'Rollup scheduler', 'Schedulers & Cadence'),
  ('pipeline', 'Admission rule runner', 'Schedulers & Cadence'),
  ('pipeline', 'Housekeeping', 'Schedulers & Cadence'),
  ('pipeline', 'Storage & retention', 'Schedulers & Cadence'),
  ('pipeline', 'Work continuity', 'Schedulers & Cadence'),
  ('pipeline', 'Maintenance mode', 'Schedulers & Cadence'),
  ('pipeline', 'Run now', 'Schedulers & Cadence'),
  ('pipeline', 'Integration queue', 'Schedulers & Cadence'),
  ('pipeline', 'Cost and yield', 'Circuit Breakers'),
  ('pipeline', 'Waste rules', 'Circuit Breakers'),
  ('pipeline', 'Alerts', 'Circuit Breakers'),
  ('pipeline', 'Flags', 'Circuit Breakers'),
  ('pipeline', 'Self-healing', 'Circuit Breakers'),
  ('pipeline', 'Operating targets', 'Circuit Breakers'),
  ('pipeline', 'Health report', 'Circuit Breakers'),
  ('pipeline', 'Zero-yield pages', 'Circuit Breakers'),
  ('pipeline', 'Operations controller', 'Circuit Breakers'),
  ('pipeline', 'Governed actions', 'Circuit Breakers'),
  ('pipeline', 'On demand', 'Circuit Breakers')
on conflict (toolset_key, section) do nothing;

-- 2. The group of a setting -----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION security.settings_hub_group_v1(p_toolset text, p_section text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select g.hub_group from pipeline.settings_hub_groups g where g.toolset_key = p_toolset and g.section = p_section),
                  (select g.hub_group from pipeline.settings_hub_groups g where g.toolset_key = p_toolset and g.section = '*'),
                  'Pipeline steps')
$function$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in)
values ('function', 'security.settings_hub_group_v1', 'Platform', 'Settings', 'The Settings Hub group of a toolset section (Consumer APIs is read-only)', 'active', '{}', '20261116040000')
on conflict (kind, name) do nothing;

-- 3. The edit helper (this transaction only) ------------------------------------------------------------------------------------------------
-- p_edits: one row per edit {kind, old, new, n}: kind 'swap' replaces old with new; kind 'mark' appends " -- fixed: <new>" to each line that
-- contains old. Each edit must match exactly n times, or nothing is changed.
create or replace function pg_temp.cf_g2_edit(p_fn text, p_md5 text, p_done text, p_edits jsonb) returns text language plpgsql as $edit$
declare v_def text := pg_get_functiondef(p_fn::regprocedure); v_new text; e jsonb; v_n int; v_pat text;
begin
  if position(p_done in v_def) > 0 then return 'already'; end if;
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_fn, md5(v_def); end if;
  v_new := v_def;
  for e in select * from jsonb_array_elements(p_edits) loop
    v_n := (length(v_new) - length(replace(v_new, e->>'old', ''))) / length(e->>'old');
    if v_n <> (e->>'n')::int then raise exception '%: "%" found % time(s), expected %', p_fn, e->>'old', v_n, e->>'n'; end if;
    if e->>'kind' = 'swap' then
      v_new := replace(v_new, e->>'old', e->>'new');
    else
      v_pat := regexp_replace(e->>'old', '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '[^\n]*';
      v_new := regexp_replace(v_new, v_pat, '\& -- fixed: ' || (e->>'new'), 'g');
    end if;
  end loop;
  if position(p_done in v_new) = 0 then raise exception '%: the edited definition does not carry %', p_fn, p_done; end if;
  execute v_new;
  return md5(pg_get_functiondef(p_fn::regprocedure));
end $edit$;

-- 4. The edits ------------------------------------------------------------------------------------------------------------------------------
do $$
declare v_a text; v_b text;
begin
  v_a := pg_temp.cf_g2_edit('public.admin_settings_register_read()', 'c3e4f273e08c7b348da6de1764205fc8', 'settings_hub_group_v1', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'jsonb_agg(jsonb_build_object(''section'', z.section, ''settings'', z.settings) order by z.first_sort)', 'new', 'jsonb_agg(jsonb_build_object(''section'', z.section, ''hub_group'', security.settings_hub_group_v1(''pipeline'', z.section), ''read_only'', security.settings_hub_group_v1(''pipeline'', z.section) = ''Consumer APIs'', ''settings'', z.settings) order by z.first_sort)', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', '''control_class'', s.control_class,', 'new', '''control_class'', s.control_class, ''changed'', s.updated_by is not null,', 'n', 1)));
  v_b := pg_temp.cf_g2_edit('public.admin_toolsets_write(text,jsonb)', '55e3818580f3eab117734e9307150283', 'consumer_api_read_only', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'if v_set.key is null then raise exception ''unknown setting''; end if;', 'new', 'if v_set.key is null then raise exception ''unknown setting''; end if;
    -- Settings Hub (Platform Admin 16 Nov 2026, decision 4): Consumer APIs settings are read-only unless the change is unlocked; a refusal is recorded
    if security.settings_hub_group_v1(v_set.toolset_key, v_set.section) = ''Consumer APIs'' and coalesce(p_args->>''unlock'', '''') <> ''consumer_api'' then
      insert into pipeline.admin_control_events(area, action, target, detail, actor) values (''toolsets'', ''refused'', v_set.toolset_key || ''.'' || v_set.key,
        jsonb_build_object(''why'', ''Consumer APIs settings are read-only; unlock the change first'', ''reason'', v_reason, ''value'', p_args->''value''), auth.uid());
      return jsonb_build_object(''ok'', false, ''refused'', ''consumer_api_read_only'', ''toolset'', v_set.toolset_key, ''key'', v_set.key);
    end if;', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', 'jsonb_build_object(''before'', v_before, ''after'', v_val, ''reason'', v_reason)', 'new', 'jsonb_build_object(''before'', v_before, ''after'', v_val, ''reason'', v_reason, ''unlock'', p_args->>''unlock'')', 'n', 1)));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('settings', 'migration', 'Settings Hub', jsonb_build_object('migration', '20261116040000', 'functions',
          jsonb_build_object('public.admin_settings_register_read()', v_a, 'public.admin_toolsets_write(text,jsonb)', v_b)), null);
end $$;

-- 5. Post-checks ----------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if security.settings_hub_group_v1('pipeline', 'Website API') <> 'Consumer APIs' or security.settings_hub_group_v1('pipeline', 'Zoho API') <> 'Consumer APIs' then
    raise exception 'post-check: the Website API and Zoho API sections are not in Consumer APIs';
  end if;
  if exists (select 1 from pipeline.platform_toolset_settings s where security.settings_hub_group_v1(s.toolset_key, s.section) = 'Consumer APIs'
              and s.section not in ('Website API', 'Zoho API')) then
    raise exception 'post-check: a setting outside the Website API and Zoho API sections is in Consumer APIs';
  end if;
  if (select count(distinct security.settings_hub_group_v1(s.toolset_key, s.section)) from pipeline.platform_toolset_settings s) <> 5 then
    raise exception 'post-check: the settings do not fall into the five hub groups';
  end if;
  if position('settings_hub_group_v1' in pg_get_functiondef('public.admin_settings_register_read()'::regprocedure)) = 0
     or position('consumer_api_read_only' in pg_get_functiondef('public.admin_toolsets_write(text,jsonb)'::regprocedure)) = 0 then
    raise exception 'post-check: the register read or the settings write was not edited';
  end if;
end $$;
