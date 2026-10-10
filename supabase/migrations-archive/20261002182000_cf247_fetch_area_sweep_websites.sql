-- CF-247 (Decision 222, 2 Oct 2026). Platform Admin, 12:41, with screenshots: "Manual job for Latrobe was submitted but
-- open job button do nothing. Work area error are description are not helpful and no steps are guided to perform to
-- resolve ... Which uni source tried should be handed to manually edited for url to layer 4." Then, asked what Fetch an
-- area should do now the old pipeline is retired: "Align the sweep function with new sweep process."
--  1. Fetch an area works on the course-page sweep: public.admin_coverage_fetch_area(action, args).
--     options / scope_page  countries, states and universities with their sweep state;
--     preview               for a country, state or university: sites known, not found, pages found and read, facts
--                           admitted, searches waiting;
--     start (Pipeline Operator and above)  puts the scope first in the sweep: a priority pin (the same pins as
--                           Scheduled jobs › Priority), site search again for providers whose site was not found, failed
--                           site maps retried, a page search queued for active courses with no page (a search that
--                           found nothing is repeated only after 7 days), and found pages not yet read read now.
--                           Nothing already admitted or entered by hand is changed.
--  2. Websites to find (Layer 4): universities whose site the finder could not confirm, with what was tried.
--     public.admin_provider_websites(args) lists them; public.admin_provider_website_set(provider, url) records the
--     website a person enters (through admin_provider_edit, so it is locked as entered by hand and logged), restarts the
--     site map, adds the generic course-page recipe and queues the page search.
--  3. The AI tuition check (layer3-work-dispatch) is called with a 5-minute wait instead of 2: it works for up to 4
--     minutes, so the caller kept giving up ("Timed out") while the check carried on.
--  4. The tuition hand-off picks pages faster: only pages with an international fee candidate (not a whole-course total)
--     reach the per-page checks (statement timeout at 12:20). The same pages qualify as before.
-- Function patches are behind md5 guards on their current source.

do $p$
declare r record; s text; d text; i int;
begin
  for r in select * from (values
    ('pipeline','svc_pilot_submit_nonce','ae4f50b65a29f416b92b80504db42bed',
      array[$o$timeout_milliseconds:=120000$o$],
      array[$n$timeout_milliseconds:=case when p_function='layer3-work-dispatch' then 300000 else 120000 end$n$]),
    ('public','svc_coverage_tuition_handoff_next','93aa3ce4766a49c9393d16c5ab058826',
      array[$o$where p.read_status='read' and security.coverage_identity_allowed($o$],
      array[$n$where p.read_status='read' and p.candidates->'fee'->'candidates' @> '[{"international": true}]'::jsonb
       and coalesce(p.candidates->'fee'->>'basis','')<>'total' and security.coverage_identity_allowed($n$])
  ) t(sch, fn, guard, olds, news) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = r.sch and p.proname = r.fn;
    if md5(s) is distinct from r.guard then raise exception '%.% changed (md5 %); not replacing', r.sch, r.fn, md5(s); end if;
    for i in 1..array_length(r.olds, 1) loop
      if (length(d) - length(replace(d, r.olds[i], ''))) / length(r.olds[i]) <> 1 then raise exception '%.% piece % not found once', r.sch, r.fn, i; end if;
      d := replace(d, r.olds[i], r.news[i]);
    end loop;
    execute d;
  end loop;
end $p$;

-- providers in a Fetch an area scope (active courses only)
create or replace function security.coverage_scope_providers(p_country text, p_type text, p_id uuid)
returns table(provider_id uuid) language sql stable security definer set search_path = '' as $f$
  select p.id from catalogue.providers p join ref.countries k on k.id = p.country_id
   where k.iso_alpha2 = upper(p_country)
     and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
     and case coalesce(p_type, 'country')
           when 'country' then true
           when 'university' then p.id = p_id
           when 'state' then p.subdivision_id = p_id or exists (
             select 1 from catalogue.courses c join catalogue.course_campuses cc on cc.course_id = c.id
               join catalogue.campuses cam on cam.id = cc.campus_id
              where c.provider_id = p.id and c.lifecycle_status = 'active' and cam.subdivision_id = p_id)
           else false end
$f$;
revoke all on function security.coverage_scope_providers(text, text, uuid) from public, anon, authenticated;

create or replace function security.coverage_scope_summary(p_country text, p_type text, p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $f$
  with sp as (select provider_id from security.coverage_scope_providers(p_country, p_type, p_id)),
  co as (select c.id, c.provider_id from catalogue.courses c join sp on sp.provider_id = c.provider_id where c.lifecycle_status = 'active'),
  di as (select d.* from pipeline.coverage_provider_discovery d join sp on sp.provider_id = d.provider_id),
  pg as (select g.* from pipeline.coverage_course_pages g join co on co.id = g.course_id),
  cv as (select a.attribute, count(*) filter (where a.state = 'admitted') n from pipeline.course_attribute_coverage a join co on co.id = a.course_id
          where a.attribute in ('official_url','english','intakes','provider_tuition') group by 1)
  select jsonb_build_object(
    'providers', (select count(*) from sp),
    'courses', (select count(*) from co),
    'sites', jsonb_build_object(
       'known', (select count(*) from di where di.status in ('mapped','pending') and di.website is not null),
       'mapped', (select count(*) from di where di.status = 'mapped'),
       'not_found', (select count(*) from di where di.status = 'no_website' and di.site_searched_at is not null),
       'to_search', (select count(*) from di where di.status = 'no_website' and di.site_searched_at is null),
       'failed', (select count(*) from di where di.status = 'failed'),
       'not_queued', (select count(*) from sp where not exists (select 1 from di where di.provider_id = sp.provider_id))),
    'pages', jsonb_build_object(
       'found', (select count(*) from pg where pg.status in ('bound','ambiguous')),
       'read', (select count(*) from pg where pg.read_status = 'read'),
       'to_read', (select count(*) from pg where pg.status in ('bound','ambiguous') and pg.read_status is distinct from 'read'),
       'not_this_course', (select count(*) from pg where pg.status = 'mismatch'),
       'no_page', (select count(*) from co where not exists (select 1 from pg where pg.course_id = co.id))),
    'searches_waiting', (select count(*) from pipeline.course_link_search s join co on co.id = s.course_id where s.state in ('queued','sent')),
    'facts', coalesce((select jsonb_object_agg(attribute, n) from cv), '{}'::jsonb),
    'facts_built_at', (select max(computed_at) from pipeline.course_attribute_coverage),
    'first_in_sweep', exists (select 1 from pipeline.priority_pins x where x.kind = case coalesce(p_type,'country') when 'university' then 'provider' else coalesce(p_type,'country') end
                               and x.target_id = case when coalesce(p_type,'country') = 'country' then (select k.id from ref.countries k where k.iso_alpha2 = upper(p_country)) else p_id end))
$f$;
revoke all on function security.coverage_scope_summary(text, text, uuid) from public, anon, authenticated;

create or replace function security.coverage_fetch_area_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_country text := upper(coalesce(p_args->>'country', ''));
  v_type text := coalesce(nullif(p_args->>'scope_type', ''), 'country'); v_id uuid := nullif(p_args->>'scope_id', '')::uuid;
  v_q text := lower(nullif(btrim(coalesce(p_args->>'query', '')), '')); v_off int := greatest(coalesce((p_args->>'offset')::int, 0), 0);
  v_kind text; v_target uuid; v_label text; n_pin int := 0; n_new int := 0; n_site int := 0; n_map int := 0; n_search int := 0; n_read int := 0; v_items jsonb; v_total int;
begin
  if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  if p_action = 'options' then
    return jsonb_build_object('countries', coalesce((select jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'providers', x.pn, 'courses', x.cn) order by x.cn desc) from (
      select k.iso_alpha2::text code, k.name, count(distinct c.provider_id) pn, count(*) cn
        from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
       where c.lifecycle_status = 'active' group by 1, 2) x), '[]'::jsonb));
  end if;
  if v_country !~ '^[A-Z]{2}$' then raise exception 'choose a country'; end if;
  if v_type not in ('country','state','university') then raise exception 'choose a country, state or university'; end if;
  if v_type <> 'country' and v_id is null and p_action in ('preview','start') then raise exception 'choose a %', case v_type when 'state' then 'state' else 'university' end; end if;
  if p_action = 'scope_page' then
    if coalesce(p_args->>'kind', '') = 'state' then
      select coalesce(jsonb_agg(jsonb_build_object('value', q.id, 'label', q.name, 'meta', q.code) order by lower(q.name)), '[]'::jsonb), max(q.total)
        into v_items, v_total
        from (select sd.id, sd.name, sd.code, count(*) over () total from ref.subdivisions sd join ref.countries k on k.id = sd.country_id
               where k.iso_alpha2 = v_country and (v_q is null or lower(sd.name || ' ' || coalesce(sd.code, '')) like '%' || v_q || '%')
                 and exists (select 1 from catalogue.providers p where p.subdivision_id = sd.id
                              and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'))
               order by lower(sd.name) limit 10 offset v_off) q;
    else
      select coalesce(jsonb_agg(jsonb_build_object('value', q.id, 'label', q.name,
               'meta', q.courses || ' courses · ' || case when q.dstatus = 'mapped' then 'site found, ' || q.read_pages || ' pages read'
                                                          when q.dstatus = 'no_website' then 'no website found yet'
                                                          when q.dstatus = 'failed' then 'site map failed'
                                                          when q.dstatus = 'pending' then 'site waiting to be mapped'
                                                          else 'not in the sweep yet' end) order by lower(q.name)), '[]'::jsonb), max(q.total)
        into v_items, v_total
        from (select p.id, coalesce(p.display_name, p.canonical_name) name, count(*) over () total,
                     (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') courses,
                     (select d.status from pipeline.coverage_provider_discovery d where d.provider_id = p.id) dstatus,
                     (select count(*) from pipeline.coverage_course_pages g where g.provider_id = p.id and g.read_status = 'read') read_pages
                from catalogue.providers p join security.coverage_scope_providers(v_country, case when nullif(p_args->>'state_id', '') is null then 'country' else 'state' end, nullif(p_args->>'state_id', '')::uuid) s on s.provider_id = p.id
               where v_q is null or lower(coalesce(p.display_name, '') || ' ' || p.canonical_name) like '%' || v_q || '%'
               order by lower(coalesce(p.display_name, p.canonical_name)) limit 10 offset v_off) q;
    end if;
    return jsonb_build_object('items', v_items, 'total', coalesce(v_total, 0), 'offset', v_off, 'has_more', v_off + jsonb_array_length(v_items) < coalesce(v_total, 0));
  end if;
  if p_action = 'preview' then
    return security.coverage_scope_summary(v_country, v_type, v_id) || jsonb_build_object('country', v_country, 'scope_type', v_type, 'scope_id', v_id);
  end if;
  if p_action <> 'start' then raise exception 'unknown action'; end if;

  -- 1. first in the sweep: the same priority pins as Scheduled jobs › Priority
  v_kind := case v_type when 'university' then 'provider' else v_type end;
  v_target := case when v_type = 'country' then (select k.id from ref.countries k where k.iso_alpha2 = v_country) else v_id end;
  v_label := security.priority_pin_label(v_kind, v_target)->>'label';
  if v_label is null then raise exception 'not found'; end if;
  insert into pipeline.priority_pins(kind, target_id, sort, note, created_by)
  values (v_kind, v_target, coalesce((select min(sort) from pipeline.priority_pins), 1) - 1, 'Fetch an area', auth.uid())
  on conflict (kind, target_id) do update set sort = (select min(sort) from pipeline.priority_pins) - 1;
  get diagnostics n_pin = row_count;
  perform security.provider_priority_refresh_v1();
  -- 2. providers not yet in the sweep join it
  insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, updated_at)
  select p.id, nullif(btrim(p.website), ''), case when nullif(btrim(p.website), '') is null then 'no_website' else 'pending' end, 0, now()
    from catalogue.providers p join security.coverage_scope_providers(v_country, v_type, v_id) s on s.provider_id = p.id
  on conflict (provider_id) do nothing;
  get diagnostics n_new = row_count;
  -- 3. site search again where the site was not found; failed site maps retried
  update pipeline.coverage_provider_discovery d set site_searched_at = null, leased_until = null, updated_at = now()
    from security.coverage_scope_providers(v_country, v_type, v_id) s
   where d.provider_id = s.provider_id and d.status = 'no_website' and d.site_searched_at is not null;
  get diagnostics n_site = row_count;
  update pipeline.coverage_provider_discovery d set status = 'pending', attempts = 0, next_due_at = null, last_error = null, leased_until = null, updated_at = now()
    from security.coverage_scope_providers(v_country, v_type, v_id) s
   where d.provider_id = s.provider_id and d.status = 'failed';
  get diagnostics n_map = row_count;
  -- 4. a page search for active courses with no page (a search that found nothing is repeated only after 7 days)
  insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
  select c.id, c.provider_id, case when c.course_code ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now()
    from catalogue.courses c join security.coverage_scope_providers(v_country, v_type, v_id) s on s.provider_id = c.provider_id
   where c.lifecycle_status = 'active'
     and exists (select 1 from pipeline.course_link_recipes r where r.provider_id = c.provider_id and r.active)
     and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.status <> 'mismatch')
  on conflict (course_id) do update set state = 'queued', stage = excluded.stage, queued_at = now(), sent_at = null, done_at = null
   where pipeline.course_link_search.state = 'none' and coalesce(pipeline.course_link_search.done_at, pipeline.course_link_search.queued_at) < now() - interval '7 days';
  get diagnostics n_search = row_count;
  -- 5. found pages not yet read are read now
  update pipeline.coverage_course_pages g set next_read_at = now(), read_attempts = 0
    from security.coverage_scope_providers(v_country, v_type, v_id) s
   where g.provider_id = s.provider_id and g.status in ('bound','ambiguous') and g.read_status is distinct from 'read'
     and coalesce(g.leased_until, '-infinity') < now();
  get diagnostics n_read = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fetch_area', 'start', v_label, p_args || jsonb_build_object('pinned', n_pin, 'joined', n_new, 'site_search_again', n_site, 'site_map_retry', n_map,
          'page_searches_queued', n_search, 'pages_to_read_now', n_read), auth.uid());
  return security.coverage_scope_summary(v_country, v_type, v_id) || jsonb_build_object('country', v_country, 'scope_type', v_type, 'scope_id', v_id, 'label', v_label,
    'started', jsonb_build_object('joined', n_new, 'site_search_again', n_site, 'site_map_retry', n_map, 'page_searches_queued', n_search, 'pages_to_read_now', n_read));
end $f$;
revoke all on function security.coverage_fetch_area_v1(text, jsonb) from public, anon, authenticated;

create or replace function public.admin_coverage_fetch_area(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language sql security definer set search_path = '' as $f$ select security.coverage_fetch_area_v1(p_action, coalesce(p_args, '{}'::jsonb)) $f$;
revoke all on function public.admin_coverage_fetch_area(text, jsonb) from public, anon;
grant execute on function public.admin_coverage_fetch_area(text, jsonb) to authenticated;

-- Websites to find (Layer 4)
create or replace function public.admin_provider_websites(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_country text := upper(nullif(p_args->>'country', '')); v_lim int := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200);
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return (with q as (
    select p.id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2::text country, d.site_searched_at, d.site_evidence,
           (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') courses,
           (select min(upper(r.registration_code)) from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos') cricos,
           (select min(upper(r.registration_code)) from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'ircc_dli') dli
      from pipeline.coverage_provider_discovery d join catalogue.providers p on p.id = d.provider_id join ref.countries k on k.id = p.country_id
     where d.status = 'no_website' and d.site_searched_at is not null and (v_country is null or k.iso_alpha2 = v_country))
    select jsonb_build_object('total', (select count(*) from q), 'can_edit', true,
      'countries', coalesce((select jsonb_object_agg(country, n) from (select country, count(*) n from q group by 1) c), '{}'::jsonb),
      'items', coalesce((select jsonb_agg(jsonb_build_object('provider_id', id, 'name', name, 'country', country, 'courses', courses, 'cricos', cricos, 'dli', dli,
                 'searched_at', site_searched_at, 'query', site_evidence->>'query', 'note', site_evidence->>'note',
                 'tried', coalesce((select jsonb_agg(t->>'page') from jsonb_array_elements(coalesce(site_evidence->'tried', '[]'::jsonb)) t where t->>'page' is not null), '[]'::jsonb))
               order by courses desc, name) from (select * from q order by courses desc, name limit v_lim) z), '[]'::jsonb)));
end $f$;
revoke all on function public.admin_provider_websites(jsonb) from public, anon;
grant execute on function public.admin_provider_websites(jsonb) to authenticated;

create or replace function public.admin_provider_website_set(p_provider_id uuid, p_url text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_url text := btrim(coalesce(p_url, '')); v_dom text;
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
  -- recorded as entered by hand (locked, logged) through the provider editor
  perform public.admin_provider_edit(p_provider_id, 'set_core', jsonb_build_object('field', 'website', 'value', v_url));
  perform public.admin_provider_edit(p_provider_id, 'set_course_finder', jsonb_build_object('url', v_url));
  update pipeline.coverage_provider_discovery set site_source = 'manual', site_searched_at = now(), updated_at = now() where provider_id = p_provider_id;
  v_dom := lower(regexp_replace(substring(v_url from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
  if v_dom ~ '^[a-z0-9.-]+\.[a-z]{2,}$' then
    insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
    select p_provider_id, v_dom,
           jsonb_build_array(jsonb_build_object(
             're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                   || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
             'rep', '\&')),
           true, 'Generic recipe: any page on the provider''s own site, from a website entered by a person; used only when the reader proves the page is the course''s (Decision 222, 2 Oct 2026)', now()
     where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
    insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
    select c.id, c.provider_id, case when c.course_code ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now()
      from catalogue.courses c
     where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
       and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
       and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
    on conflict (course_id) do nothing;
  end if;
  return public.admin_provider_websites('{}'::jsonb);
end $f$;
revoke all on function public.admin_provider_website_set(uuid, text) from public, anon;
grant execute on function public.admin_provider_website_set(uuid, text) to authenticated;
