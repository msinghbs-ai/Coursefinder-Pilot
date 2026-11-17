-- CF-247 (22 Oct 2026). The settings guard (G2) caught the 90-day recheck of a provider's public contacts written as a number in
-- public.svc_provider_contact_next (20261022029000 re-created the function with the number it already had). It is now the setting
-- contact.recheck_days (90, today's value), shown on Settings › Pipeline settings.
-- Replaces: public.svc_provider_contact_next (recheck days from a setting). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'contact.recheck_days', 'Provider contacts checked again after', 'A provider''s public phone and email are looked for again on its own site after this many days.', 'number', to_jsonb(90), 7, 365, 'days', 745, 'CF-247 22 Oct 2026: was a number in the function (G2)', 'Enrichment', 'public.svc_provider_contact_next')
on conflict (toolset_key, key) do nothing;

do $edit$
declare v_def text := pg_get_functiondef('public.svc_provider_contact_next(integer)'::regprocedure);
        v_old text := $o$k.checked_at > now() - interval '90 days')$o$;
begin
  if position('contact.recheck_days' in v_def) > 0 then return; end if;  -- already from the setting
  if md5(v_def) <> '15c3dce064294c0c454430bc1015d61a' then raise exception 'live public.svc_provider_contact_next differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'recheck interval must occur once'; end if;
  execute replace(v_def, v_old, $n$k.checked_at > now() - make_interval(days => security.pipeline_num_v1('contact.recheck_days', 90)::int))$n$);
end $edit$;
