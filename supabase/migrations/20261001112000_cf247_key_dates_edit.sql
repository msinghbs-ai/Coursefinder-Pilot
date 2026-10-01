-- CF-247 Key dates edited in place (screen review 1 Oct 2026, Key dates marked Fix: "dates-no-edit", "dates-raw-fields",
-- "dates-form-first"). The list comes first; each row can be changed in place or cancelled, and a new date is added from
-- a short form (more targeting fields behind "More"). Curator and above; every change is logged
-- (admin_control_events area 'key_dates'). The existing rules stay: vague wording is kept as wording, an exact date needs
-- a date, and a date can trigger a refresh only when it is tied to a source, provider, course or scholarship.

create or replace function public.admin_key_dates_read() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 2 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_edit', v_rank >= 3,
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'country', d.country_code, 'event_type', d.event_type, 'title', d.title,
                'source_url', d.source_url, 'precision', d.date_precision, 'starts_on', coalesce(d.starts_on, (d.starts_at at time zone coalesce(d.timezone, 'Australia/Melbourne'))::date),
                'ends_on', coalesce(d.ends_on, (d.ends_at at time zone coalesce(d.timezone, 'Australia/Melbourne'))::date), 'wording', d.source_wording,
                'warning_days', extract(day from d.warning_window)::int, 'scope', d.scope_type, 'refresh_layer', d.refresh_layer, 'status', d.status, 'updated_at', d.updated_at)
              order by d.status <> 'active', coalesce(d.starts_on, d.starts_at::date) nulls last, d.title), '[]'::jsonb) from pipeline.important_dates d),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
               from (select * from pipeline.admin_control_events where area = 'key_dates' order by created_at desc limit 15) e left join auth.users u on u.id = e.actor));
end $f$;
revoke all on function public.admin_key_dates_read() from public, anon;
grant execute on function public.admin_key_dates_read() to authenticated;

create or replace function public.admin_key_date_save(p_id uuid, p_fields jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_old pipeline.important_dates%rowtype; v_new pipeline.important_dates%rowtype; v_keys text[];
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'nothing to save'; end if;
  select array_agg(k) into v_keys from jsonb_object_keys(p_fields) k;
  if exists (select 1 from unnest(v_keys) k where k not in ('country','event_type','title','source_url','precision','starts_on','ends_on','wording','warning_days','scope','refresh_layer','entity_type','entity_id')) then
    raise exception 'unknown field'; end if;
  if p_fields ? 'source_url' and coalesce(p_fields->>'source_url', '') !~* '^https?://' then raise exception 'the source address must start with http:// or https://'; end if;
  if p_id is null then
    insert into pipeline.important_dates(country_code, event_type, title, source_url, scope_type, entity_type, entity_id, date_precision, starts_on, ends_on,
      timezone, source_wording, warning_window, refresh_layer, status, change_control_ref, created_by, updated_by)
    values (upper(coalesce(nullif(btrim(p_fields->>'country'), ''), 'AU')), coalesce(p_fields->>'event_type', 'national_education_event'), btrim(coalesce(p_fields->>'title', '')),
      btrim(coalesce(p_fields->>'source_url', '')), coalesce(nullif(p_fields->>'scope', ''), 'country_reference'), nullif(p_fields->>'entity_type', ''), nullif(p_fields->>'entity_id', '')::uuid,
      coalesce(p_fields->>'precision', 'exact'), nullif(p_fields->>'starts_on', '')::date, nullif(p_fields->>'ends_on', '')::date, 'Australia/Melbourne',
      nullif(btrim(coalesce(p_fields->>'wording', '')), ''), make_interval(days => coalesce(nullif(p_fields->>'warning_days', '')::int, 14)),
      nullif(p_fields->>'refresh_layer', '')::smallint, 'active', 'CF-CHG-20260915-247', auth.uid(), auth.uid())
    returning * into v_new;
    if length(v_new.title) < 3 then raise exception 'give the date a title'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('key_dates', 'add', v_new.title, jsonb_build_object('id', v_new.id), auth.uid());
    return public.admin_key_dates_read() || jsonb_build_object('saved', v_new.id);
  end if;
  select * into v_old from pipeline.important_dates where id = p_id for update;
  if not found then raise exception 'date not found'; end if;
  update pipeline.important_dates set
    country_code = case when p_fields ? 'country' then upper(btrim(p_fields->>'country')) else country_code end,
    event_type = case when p_fields ? 'event_type' then p_fields->>'event_type' else event_type end,
    title = case when p_fields ? 'title' then btrim(p_fields->>'title') else title end,
    source_url = case when p_fields ? 'source_url' then btrim(p_fields->>'source_url') else source_url end,
    date_precision = case when p_fields ? 'precision' then p_fields->>'precision' else date_precision end,
    starts_on = case when p_fields ? 'starts_on' then nullif(p_fields->>'starts_on', '')::date else starts_on end,
    starts_at = case when p_fields ? 'starts_on' then null else starts_at end,
    ends_on = case when p_fields ? 'ends_on' then nullif(p_fields->>'ends_on', '')::date else ends_on end,
    ends_at = case when p_fields ? 'ends_on' then null else ends_at end,
    source_wording = case when p_fields ? 'wording' then nullif(btrim(coalesce(p_fields->>'wording', '')), '') else source_wording end,
    warning_window = case when p_fields ? 'warning_days' then make_interval(days => (p_fields->>'warning_days')::int) else warning_window end,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id returning * into v_new;
  if length(coalesce(v_new.title, '')) < 3 then raise exception 'give the date a title'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('key_dates', 'change', v_new.title, jsonb_build_object('id', p_id, 'fields', to_jsonb(v_keys),
          'before', jsonb_build_object('title', v_old.title, 'source_url', v_old.source_url, 'precision', v_old.date_precision, 'starts_on', v_old.starts_on,
                    'starts_at', v_old.starts_at, 'ends_on', v_old.ends_on, 'wording', v_old.source_wording, 'event_type', v_old.event_type, 'country', v_old.country_code)), auth.uid());
  return public.admin_key_dates_read() || jsonb_build_object('saved', p_id);
exception
  when check_violation then
    raise exception '%', case
      when sqlerrm like '%important_dates_check1%' then 'a vague date needs the wording from the source'
      when sqlerrm like '%exact_source_value%' then 'an exact date needs a date'
      when sqlerrm like '%bounded_scope%' then 'a date tied to a source, provider, course or scholarship needs which one'
      when sqlerrm like '%event_type%' then 'unknown kind of date'
      when sqlerrm like '%date_precision%' then 'unknown precision'
      else sqlerrm end;
end $f$;
revoke all on function public.admin_key_date_save(uuid, jsonb) from public, anon;
grant execute on function public.admin_key_date_save(uuid, jsonb) to authenticated;

create or replace function public.admin_key_date_action(p_id uuid, p_action text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v pipeline.important_dates%rowtype;
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action not in ('cancel', 'restore') then raise exception 'unknown action %', p_action; end if;
  update pipeline.important_dates set status = case when p_action = 'cancel' then 'cancelled' else 'active' end, updated_by = auth.uid(), updated_at = now()
   where id = p_id returning * into v;
  if not found then raise exception 'date not found'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('key_dates', p_action, v.title, jsonb_build_object('id', p_id), auth.uid());
  return public.admin_key_dates_read();
end $f$;
revoke all on function public.admin_key_date_action(uuid, text) from public, anon;
grant execute on function public.admin_key_date_action(uuid, text) to authenticated;