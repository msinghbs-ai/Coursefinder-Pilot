-- CF-247 (22 Oct 2026). Platform Admin 07:41: "Maintain daily unpublished providers as the sql script and report, incase someone by mistake
-- enables them, we should have this feature in settings, that can take account of such misc settings backup on daily basis and restore it,
-- only by platform admin".
-- Today 1,315 providers are unpublished (1,305 active, 10 archived); the website shows only published providers, so publishing one by
-- mistake shows it to students. Courses are not published one by one (all are unpublished; the provider switch decides), so the backup
-- holds the provider switch and every value in Pipeline settings and Toolsets & limits (298 settings).
--   1 pipeline.settings_backups: one backup = every provider's published/unpublished state and every setting value, with counts. Kinds:
--     daily (job), manual (Back up now), before_restore (taken automatically before any restore).
--   2 security.settings_backup_take_v1(kind, note); job settings-backup-daily at 19:50 UTC (6:50 am Melbourne, daylight time), catalogued;
--     backups older than retention.settings_backup_days (60) are removed by the job, except before_restore backups of the last 60 days.
--   3 security.settings_backup_diff_v1(backup): what differs now from the backup (provider name, then and now, who changed it last and
--     when, from pipeline.manual_edit_log; setting label, then and now, who changed it last and the reason).
--   4 public.admin_settings_backup(action, args), Platform Admin only (rank 6): list, diff, take, script (a SQL file that puts a backup
--     back), restore (all, providers, settings, or chosen items; reason required; a before_restore backup first; each provider change is
--     written to pipeline.manual_edit_log as action restore; an archived provider is never published).
--   5 Settings › Backup & restore (Platform Admin).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted by this migration (old backups are removed by the job). Consumer API not touched (Decision 266): restoring
-- changes provider data the API reads, never its shape.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'retention.settings_backup_days', 'Keep backups of publishing and settings for', 'Days of daily backups of the provider Published switch and setting values (Settings › Backup & restore); older backups are removed by the daily job.', 'number', to_jsonb(60), 14, 730, 'days', 328,
  'CF-247, Platform Admin 22 Oct 2026 07:41 "settings backup on daily basis and restore it"', 'Storage & retention', 'job settings-backup-daily')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.settings_backups (
  id bigserial primary key,
  taken_at timestamptz not null default now(),
  kind text not null check (kind in ('daily', 'manual', 'before_restore')),
  taken_by uuid,
  note text,
  providers jsonb not null,  -- {provider_id: "published" | "unpublished"}
  settings jsonb not null,   -- [{toolset_key, key, value}]
  counts jsonb not null default '{}'::jsonb
);
create index if not exists settings_backups_taken on pipeline.settings_backups(taken_at desc);
comment on table pipeline.settings_backups is 'CF-247 22 Oct 2026 (Platform Admin "daily unpublished providers ... backup on daily basis and restore it, only by platform admin"): a copy of every provider''s Published switch and every Pipeline settings / Toolsets & limits value. Daily by job settings-backup-daily, by hand, and before every restore. Restored only by the Platform Admin (public.admin_settings_backup).';
alter table pipeline.settings_backups enable row level security;

create or replace function security.settings_backup_take_v1(p_kind text default 'daily', p_note text default null)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_id bigint; v_old int := 0; v_counts jsonb;
begin
  select jsonb_build_object('providers', count(*), 'published', count(*) filter (where publication_status = 'published'),
                            'unpublished', count(*) filter (where publication_status is distinct from 'published'),
                            'settings', (select count(*) from pipeline.platform_toolset_settings))
    into v_counts from catalogue.providers;
  insert into pipeline.settings_backups(kind, taken_by, note, providers, settings, counts)
  values (p_kind, auth.uid(), left(p_note, 500),
          (select coalesce(jsonb_object_agg(p.id::text, coalesce(p.publication_status, 'unpublished')), '{}'::jsonb) from catalogue.providers p),
          (select coalesce(jsonb_agg(jsonb_build_object('toolset_key', s.toolset_key, 'key', s.key, 'value', s.value) order by s.toolset_key, s.key), '[]'::jsonb) from pipeline.platform_toolset_settings s),
          v_counts)
  returning id into v_id;
  if p_kind = 'daily' then
    delete from pipeline.settings_backups
     where taken_at < now() - make_interval(days => security.pipeline_num_v1('retention.settings_backup_days', 60)::int);
    get diagnostics v_old = row_count;
  end if;
  return jsonb_build_object('backup_id', v_id, 'counts', v_counts, 'removed', v_old);
end $function$;
revoke execute on function security.settings_backup_take_v1(text, text) from public, anon, authenticated;

create or replace function security.settings_backup_diff_v1(p_backup bigint)
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  with b as (select * from pipeline.settings_backups where id = p_backup),
  pv as (
    select p.id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2 country, b2.v then_status, coalesce(p.publication_status, 'unpublished') now_status, p.lifecycle_status,
           (select jsonb_build_object('at', l.at, 'by', coalesce(u.email, l.actor::text), 'action', l.action) from pipeline.manual_edit_log l left join auth.users u on u.id = l.actor
             where l.entity = 'provider' and l.entity_id = p.id and l.field = 'publication_status' order by l.at desc limit 1) last_change
      from b, jsonb_each_text(b.providers) b2(id, v)
      join catalogue.providers p on p.id = b2.id::uuid
      left join ref.countries k on k.id = p.country_id
     where b2.v is distinct from coalesce(p.publication_status, 'unpublished')),
  sv as (
    select s.toolset_key, s.key, s.label, s.section, x->'value' then_value, s.value now_value, s.reason, s.updated_at, coalesce(u.email, s.updated_by::text) updated_by
      from b, jsonb_array_elements(b.settings) x
      join pipeline.platform_toolset_settings s on s.toolset_key = x->>'toolset_key' and s.key = x->>'key'
      left join auth.users u on u.id = s.updated_by
     where s.value is distinct from x->'value')
  select jsonb_build_object(
    'backup', (select jsonb_build_object('id', id, 'taken_at', taken_at, 'kind', kind, 'counts', counts) from b),
    'providers', coalesce((select jsonb_agg(to_jsonb(pv) order by (pv.now_status = 'published') desc, pv.name) from pv), '[]'::jsonb),
    'settings', coalesce((select jsonb_agg(to_jsonb(sv) order by sv.toolset_key, sv.key) from sv), '[]'::jsonb),
    'new_settings', (select count(*) from pipeline.platform_toolset_settings s, b
                      where not exists (select 1 from jsonb_array_elements(b.settings) x where x->>'toolset_key' = s.toolset_key and x->>'key' = s.key)),
    'new_providers', (select count(*) from catalogue.providers p, b where not (b.providers ? p.id::text)))
$function$;
revoke execute on function security.settings_backup_diff_v1(bigint) from public, anon, authenticated;

create or replace function public.admin_settings_backup(p_action text, p_args jsonb default '{}'::jsonb)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_id bigint := nullif(p_args->>'backup_id', '')::bigint; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_scope text := coalesce(p_args->>'scope', 'all'); v_before jsonb; v_p int := 0; v_s int := 0; v_skipped int := 0;
        r record; v_sql text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'list' then
    return jsonb_build_object('backups', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'taken_at', b.taken_at, 'kind', b.kind, 'note', b.note, 'counts', b.counts,
                                                     'by', (select u.email from auth.users u where u.id = b.taken_by)) order by b.taken_at desc)
                                                   from pipeline.settings_backups b), '[]'::jsonb),
                              'keep_days', security.pipeline_num_v1('retention.settings_backup_days', 60));
  elsif p_action = 'take' then
    return security.settings_backup_take_v1('manual', nullif(v_reason, ''));
  end if;
  if v_id is null or not exists (select 1 from pipeline.settings_backups where id = v_id) then raise exception 'backup not found'; end if;
  if p_action = 'diff' then
    return security.settings_backup_diff_v1(v_id);
  elsif p_action = 'script' then
    -- a SQL file that puts this backup back (for keeping outside the platform; run by the Platform Admin)
    select string_agg(l, E'\n') into v_sql from (
      select format('-- StudySearch: backup %s (%s, %s). Puts back every provider''s Published switch and every setting value as they were.', b.id, b.kind, to_char(b.taken_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI')) l, 0 o
        from pipeline.settings_backups b where b.id = v_id
      union all select 'begin;', 1
      union all select 'select set_config(''cf.manual_edit'', ''on'', true);', 2
      union all
      select format('update catalogue.providers set publication_status = %L, updated_at = now() where id = %L and publication_status is distinct from %L%s;  -- %s',
                    x.v, x.id, x.v, case when x.v = 'published' then ' and lifecycle_status = ''active''' else '' end, coalesce(p.display_name, p.canonical_name)), 3
        from pipeline.settings_backups b, jsonb_each_text(b.providers) x(id, v) left join catalogue.providers p on p.id = x.id::uuid where b.id = v_id
      union all
      select format('update pipeline.platform_toolset_settings set value = %L::jsonb, reason = %L, updated_at = now() where toolset_key = %L and key = %L and value is distinct from %L::jsonb;',
                    s->'value', 'Restored from backup ' || v_id, s->>'toolset_key', s->>'key', s->'value'), 4
        from pipeline.settings_backups b, jsonb_array_elements(b.settings) s where b.id = v_id
      union all select 'insert into search.refresh_requests(requested_by) values (''settings backup ' || v_id || ' restored by script'');', 5
      union all select 'commit;', 6
      order by 2) q;
    return jsonb_build_object('backup_id', v_id, 'sql', v_sql);
  elsif p_action = 'restore' then
    if length(v_reason) < 10 then raise exception 'say why (at least 10 characters)'; end if;
    if v_scope not in ('all', 'providers', 'settings', 'items') then raise exception 'scope must be all, providers, settings or items'; end if;
    v_before := security.settings_backup_take_v1('before_restore', 'Before restoring backup ' || v_id || ': ' || v_reason);
    perform set_config('cf.manual_edit', 'on', true);
    if v_scope in ('all', 'providers', 'items') then
      for r in select p.id, coalesce(p.publication_status, 'unpublished') now_status, x.v then_status, p.lifecycle_status
                 from pipeline.settings_backups b, jsonb_each_text(b.providers) x(id, v) join catalogue.providers p on p.id = x.id::uuid
                where b.id = v_id and x.v is distinct from coalesce(p.publication_status, 'unpublished')
                  and (v_scope <> 'items' or coalesce(p_args->'providers', '[]'::jsonb) ? p.id::text) loop
        if r.then_status = 'published' and r.lifecycle_status <> 'active' then v_skipped := v_skipped + 1; continue; end if;
        update catalogue.providers set publication_status = r.then_status, updated_at = now() where id = r.id;
        insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
        values ('provider', r.id, 'publication_status', 'restore', to_jsonb(r.now_status), to_jsonb(r.then_status), left('Backup ' || v_id || ': ' || v_reason, 500), auth.uid());
        v_p := v_p + 1;
      end loop;
    end if;
    if v_scope in ('all', 'settings', 'items') then
      for r in select s.toolset_key, s.key, x->'value' then_value
                 from pipeline.settings_backups b, jsonb_array_elements(b.settings) x
                 join pipeline.platform_toolset_settings s on s.toolset_key = x->>'toolset_key' and s.key = x->>'key'
                where b.id = v_id and s.value is distinct from x->'value'
                  and (v_scope <> 'items' or coalesce(p_args->'settings', '[]'::jsonb) ? (s.toolset_key || '/' || s.key)) loop
        update pipeline.platform_toolset_settings set value = r.then_value, reason = left('Restored from backup ' || v_id || ': ' || v_reason, 500),
               updated_by = auth.uid(), updated_at = now()
         where toolset_key = r.toolset_key and key = r.key;
        v_s := v_s + 1;
      end loop;
    end if;
    if v_p > 0 then insert into search.refresh_requests(requested_by) values ('settings backup ' || v_id || ' restored'); end if;
    return jsonb_build_object('backup_id', v_id, 'providers', v_p, 'settings', v_s, 'archived_not_published', v_skipped, 'before_restore', v_before->'backup_id');
  end if;
  raise exception 'unknown action %', p_action;
end $function$;
revoke execute on function public.admin_settings_backup(text, jsonb) from public, anon;
grant execute on function public.admin_settings_backup(text, jsonb) to authenticated;

select security.settings_backup_take_v1('daily', 'First backup, taken when this feature was added');

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('settings-backup-daily', 'Reporting', 42, 'Daily backup of publishing and settings', 'Daily at 6:50 am Melbourne (daylight time): keeps a copy of every provider''s Published switch and every setting value, so a mistake can be put back (Settings › Backup & restore, Platform Admin). Keeps Settings › Pipeline settings › Storage & retention days.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('settings-backup-daily', '50 19 * * *', $$select security.settings_backup_take_v1('daily')$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.settings_backups', 'Platform', 'Daily backups of the provider Published switch and setting values', 'active', '20261022012000'),
 ('function', 'security.settings_backup_take_v1', 'Platform', 'Takes a backup of publishing and settings', 'active', '20261022012000'),
 ('function', 'security.settings_backup_diff_v1', 'Platform', 'What differs now from a backup', 'active', '20261022012000'),
 ('function', 'public.admin_settings_backup', 'Platform', 'Settings › Backup & restore (Platform Admin)', 'active', '20261022012000'),
 ('job', 'settings-backup-daily', 'Platform', 'Daily backup of publishing and settings', 'active', '20261022012000')
on conflict (kind, name) do nothing;
