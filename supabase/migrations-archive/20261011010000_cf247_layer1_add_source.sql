-- CF-247 (11 Oct 2026, Platform Admin bugs 11/10-3, Feature 2): Layer 1 › Sources has "+ Add source", like Reference sources.
-- A register added here is recorded with its country, address, authority and refresh interval, paused and marked as needing a reader:
-- it runs once a reader (adapter) is assigned to it. Platform Admin only; every addition is logged. Nothing is dropped or deleted.
create or replace function public.admin_layer1_add_source(p_args jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_country uuid; v_url text := btrim(coalesce(p_args->>'url', '')); v_label text := btrim(coalesce(p_args->>'label', ''));
        v_authority text := btrim(coalesce(p_args->>'authority_name', '')); v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_days int := coalesce(nullif(p_args->>'ingestion_cadence_days', '')::int, 30); v_dom text; v_id uuid;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  select k.id into v_country from ref.countries k where k.iso_alpha2 = upper(btrim(coalesce(p_args->>'country_code', '')));
  if v_country is null then raise exception 'choose a country'; end if;
  if length(v_label) < 4 then raise exception 'enter the register''s name'; end if;
  if v_url !~* '^https://[^[:space:]/]+\.[^[:space:]]+$' then raise exception 'enter the register''s https address'; end if;
  if length(v_authority) < 3 then raise exception 'enter the authority that publishes it'; end if;
  if v_days not between 1 and 365 then raise exception 'the refresh interval is 1 to 365 days'; end if;
  if length(v_reason) < 4 then v_reason := 'Layer 1 › Sources: register added'; end if;
  if exists (select 1 from pipeline.sources s where lower(s.url) = lower(v_url) and s.status <> 'retired') then raise exception 'a source with this address already exists'; end if;
  v_dom := lower(regexp_replace(substring(v_url from '^https://([^/:?#]+)'), '^www\.', ''));
  insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
  values ('web', v_country, v_url, v_label, 10, 'active',
          jsonb_build_object('layer', '1', 'added_in', 'v2.15.246', 'added_by', auth.uid(), 'needs_reader', true, 'dataset_class', coalesce(nullif(p_args->>'dataset_class', ''), 'register'),
                             'notes', nullif(btrim(coalesce(p_args->>'notes', '')), '')))
  returning id into v_id;
  insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused, verification_cadence_days,
         ingestion_cadence_days, variance_warn_percent, variance_block_percent, verification_status, variance_decision, verification_message, next_verification_at, auto_ingest, change_reason, updated_by, updated_at)
  values (v_id, v_authority, array[v_dom], coalesce(nullif(btrim(coalesce(p_args->>'expected_format', '')), ''), 'not set: needs a reader'), 'records', true, true, 1,
          v_days, 5, 20, 'unverified', 'unknown', 'Added by hand; it runs once a reader (adapter) is assigned to it.', null, false, v_reason, auth.uid(), now());
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'add_source', v_id::text, jsonb_build_object('label', v_label, 'url', v_url, 'country', upper(p_args->>'country_code'), 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'source_id', v_id, 'label', v_label);
end $f$;
revoke all on function public.admin_layer1_add_source(jsonb) from public, anon;
grant execute on function public.admin_layer1_add_source(jsonb) to authenticated;
