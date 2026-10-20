CREATE OR REPLACE FUNCTION public.admin_scholarship_coverage_write(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_sid uuid := nullif(p_args->>'scholarship_id', '')::uuid;
        v_url text := btrim(coalesce(p_args->>'url', '')); v_id bigint := nullif(p_args->>'id', '')::bigint; v_res jsonb; v_hash text;
begin
  if auth.uid() is null or v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if p_action not in ('watch', 'unwatch') and v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action = 'add_listing' then
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if not security.url_on_provider_sites(v_url, v_pid) then raise exception 'this page is not on the provider''s own website'; end if;
    insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at, added_by)
    values (v_pid, v_url, security.scholarship_url_norm(v_url), 'manual', true, 'waiting', now(), auth.uid())
    on conflict (provider_id, url_norm) do update set active = true, source = case when pipeline.scholarship_listing_pages.source = 'suggested' then 'manual' else pipeline.scholarship_listing_pages.source end,
       status = case when pipeline.scholarship_listing_pages.status = 'suggested' then 'waiting' else pipeline.scholarship_listing_pages.status end, next_read_at = now(), added_by = auth.uid();
  elsif p_action = 'use_suggested' then
    update pipeline.scholarship_listing_pages set source = 'manual', status = 'waiting', active = true, next_read_at = now(), added_by = auth.uid() where id = v_id and source = 'suggested';
    select provider_id into v_pid from pipeline.scholarship_listing_pages where id = v_id;
  elsif p_action = 'remove_listing' then
    update pipeline.scholarship_listing_pages set active = false where id = v_id returning provider_id into v_pid;
  elsif p_action = 'read_now' then
    update pipeline.scholarship_listing_pages set next_read_at = now() where provider_id = v_pid and active and source <> 'suggested';
    update pipeline.scholarship_pages sp set next_read_at = now() from scholarship.scholarships s where s.id = sp.scholarship_id and s.provider_id = v_pid and s.lifecycle_status = 'active';
  elsif p_action = 'sign_off' then
    select md5(coalesce(string_agg(lower(item_name), '|' order by lower(item_name)), '')) into v_hash from security.scholarship_listing_match_v1(v_pid);
    insert into pipeline.scholarship_coverage_checks(provider_id, checked_by, checked_at, item_hash, note) values (v_pid, auth.uid(), now(), v_hash, left(p_args->>'note', 300))
    on conflict (provider_id) do update set checked_by = auth.uid(), checked_at = now(), item_hash = excluded.item_hash, note = excluded.note;
  elsif p_action = 'watch' then
    insert into pipeline.scholarship_watch(provider_id, added_by) values (v_pid, auth.uid()) on conflict (provider_id) do update set active = true, added_by = auth.uid(), added_at = now();
  elsif p_action = 'unwatch' then
    update pipeline.scholarship_watch set active = false where provider_id = v_pid;
  elsif p_action = 'publish' then
    select provider_id into v_pid from scholarship.scholarships where id = v_sid;
    if not coalesce((select x.publishable from security.scholarship_publishability_v1() x where x.scholarship_id = v_sid), false) then
      raise exception 'this scholarship does not pass every check yet; see its reasons'; end if;
    update scholarship.scholarships set publication_status = 'published', updated_at = now() where id = v_sid and publication_status <> 'published';
    insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('publish', 'coverage check: published by hand', array[v_sid]);
  elsif p_action = 'hold' then
    -- withdraws it if published, and keeps it from automatic publishing until released
    select provider_id into v_pid from scholarship.scholarships where id = v_sid;
    insert into pipeline.scholarship_publication_holds(scholarship_id, reason, held_by) values (v_sid, coalesce(nullif(btrim(p_args->>'reason'), ''), 'Held on the coverage check'), 'admin')
    on conflict (scholarship_id) do update set reason = excluded.reason, held_by = 'admin', held_at = now(), released_at = null, release_note = null;
    update scholarship.scholarships set publication_status = 'withdrawn', updated_at = now() where id = v_sid and publication_status = 'published';
  elsif p_action = 'release' then
    select provider_id into v_pid from scholarship.scholarships where id = v_sid;
    update pipeline.scholarship_publication_holds set released_at = now(), release_note = 'released on the coverage check' where scholarship_id = v_sid and released_at is null;
  elsif p_action = 'confirm_international' then
    select provider_id into v_pid from scholarship.scholarships where id = v_sid;
    insert into scholarship.criteria(scholarship_id, criterion_type, operator, value_codes, value_json, human_text, is_mandatory, machine_evaluable, status, confidence)
    values (v_sid, 'student_type', 'in', array['international'], jsonb_build_object('by', 'person', 'actor', auth.uid(), 'basis', 'listed on the provider''s international scholarships page'),
            left(coalesce(nullif(btrim(p_args->>'note'), ''), 'Listed on the provider''s international scholarships page'), 300), true, true, 'active', 1);
    update scholarship.scholarships set audience = case when audience ~* 'domestic' then 'international_and_domestic' else 'international' end, updated_at = now() where id = v_sid and coalesce(audience, '') !~* 'international';
  else
    raise exception 'unknown action %', p_action;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('scholarship_coverage', p_action, coalesce(v_sid::text, v_pid::text, v_id::text), p_args, auth.uid());
  if v_pid is null then return jsonb_build_object('ok', true); end if;
  return public.admin_scholarship_coverage_provider(v_pid);
end $function$
