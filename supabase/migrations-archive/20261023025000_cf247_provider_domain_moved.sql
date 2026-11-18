-- CF-247 (23 Oct 2026). NZ enrichment brief, Release 1 item 2 (Platform Admin 20:42; N5 at 20:52): when a provider's website moves
-- (the NZ polytechnic transition), its bound course pages and course-list sources move with it, keeping their identity proof and
-- evidence, and are read again first in line. Platform Admin only, logged. The same host is refused (nothing to move, nothing logged).
-- Replaces: nothing
-- Retires: nothing

create or replace function public.admin_provider_domain_moved(p_provider_id uuid, p_new_host text, p_reason text) returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare v_old text; v_new text := lower(btrim(coalesce(p_new_host, ''))); v_pages int := 0; v_lists int := 0; v_reason text := btrim(coalesce(p_reason, '')); v_rx text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if v_new !~ '^[a-z0-9.-]+\.[a-z]{2,}$' then raise exception 'give the new host only, for example www.example.ac.nz'; end if;
  select lower(regexp_replace(website, '^https?://([^/]+).*$', '\1')) into v_old from catalogue.providers where id = p_provider_id and website ~* '^https?://';
  if v_old is null then raise exception 'the provider has no website to move from'; end if;
  if v_old = v_new then raise exception 'the website already is %: nothing to move', v_old; end if;  -- N5: no-op refused, nothing logged
  v_rx := '^(https?://)' || regexp_replace(v_old, '\.', '\\.', 'g') || '(?=/|$)';
  update pipeline.coverage_course_pages g
     set url = regexp_replace(g.url, v_rx, '\1' || v_new, 'i'), next_read_at = now(), read_attempts = 0, leased_until = null
   where g.course_id in (select id from catalogue.courses where provider_id = p_provider_id)
     and g.status in ('bound', 'ambiguous') and g.url ~* v_rx;
  get diagnostics v_pages = row_count;
  update pipeline.provider_course_lists l
     set url = regexp_replace(l.url, v_rx, '\1' || v_new, 'i'), updated_at = now()
   where l.provider_id = p_provider_id and l.url ~* v_rx;
  get diagnostics v_lists = row_count;
  perform set_config('cf.manual_edit', 'on', true);
  update catalogue.providers set website = 'https://' || v_new, updated_at = now() where id = p_provider_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'provider_domain_moved', p_provider_id::text, jsonb_build_object('from', v_old, 'to', v_new, 'pages', v_pages, 'lists', v_lists, 'reason', v_reason), auth.uid());
  return jsonb_build_object('from', v_old, 'to', v_new, 'pages_moved', v_pages, 'lists_moved', v_lists);
end $f$;
revoke execute on function public.admin_provider_domain_moved(uuid, text, text) from public, anon;
grant execute on function public.admin_provider_domain_moved(uuid, text, text) to authenticated;
comment on function public.admin_provider_domain_moved(uuid, text, text) is 'CF-247 NZ brief item 2: moves a provider''s bound course pages and list sources to a new host (identity proof and evidence kept, pages read again first in line). Platform Admin, logged; the same host is refused.';

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_provider_domain_moved', 'Layer 1', 'Move a provider''s course pages to a new host after a website change (NZ transition)', 'active', '{}', '20261023025000')
on conflict (kind, name) do nothing;

select 'provider domain moved action' ok;
