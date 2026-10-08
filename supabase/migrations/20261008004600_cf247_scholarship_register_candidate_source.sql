-- CF-247 Scholarships register fix: the provider page candidates table only accepts the sources
-- 'sitemap', 'map' and 'search', so the first Study Australia detail batch failed when the register
-- handed a page over (nothing was saved; the batch rolled back). Adds 'register' as a fourth source
-- and the hand-off uses it (the register code stays on the listing).
do $$ begin
  if md5(pg_get_functiondef('public.svc_scholarship_register_match(text)'::regprocedure)) <> 'ff5eb351f07c7f61df6e9bb12f9641e6' then
    raise exception 'svc_scholarship_register_match changed since 20261008004500; refusing to replace it';
  end if;
end $$;

alter table pipeline.scholarship_page_candidates drop constraint scholarship_page_candidates_source_check;
alter table pipeline.scholarship_page_candidates add constraint scholarship_page_candidates_source_check
  check (source = any (array['sitemap'::text, 'map'::text, 'search'::text, 'register'::text]));

create or replace function public.svc_scholarship_register_match(p_register text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id int := 0; v_page int := 0; v_name int := 0; v_handed int := 0; v_offsite int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  update scholarship.register_listings l set scholarship_id = s.id, match_basis = 'register_id_in_source_url'
    from scholarship.scholarships s
   where l.register_code = p_register and l.scholarship_id is null
     and strpos(s.source_url, l.listing_id) > 0;
  get diagnostics v_id = row_count;
  update scholarship.register_listings l set scholarship_id = m.sid, match_basis = 'provider_page_address'
    from (select distinct on (l2.listing_id) l2.listing_id, coalesce(p.scholarship_id, s.id) sid
            from scholarship.register_listings l2
            left join pipeline.scholarship_pages p on security.scholarship_url_norm(coalesce(p.final_url, p.url)) = security.scholarship_url_norm(l2.website_url)
            left join scholarship.scholarships s on security.scholarship_url_norm(s.source_url) = security.scholarship_url_norm(l2.website_url)
           where l2.register_code = p_register and l2.scholarship_id is null and l2.website_url is not null
             and coalesce(p.scholarship_id, s.id) is not null) m
   where l.register_code = p_register and l.listing_id = m.listing_id;
  get diagnostics v_page = row_count;
  update scholarship.register_listings l set scholarship_id = m.sid, match_basis = 'provider_and_name'
    from (select l2.listing_id, min(s.id::text)::uuid sid
            from scholarship.register_listings l2
            join scholarship.scholarships s on s.provider_id = l2.provider_id
             and lower(regexp_replace(s.name, '[^[:alnum:]]+', ' ', 'g')) = lower(regexp_replace(l2.name, '[^[:alnum:]]+', ' ', 'g'))
           where l2.register_code = p_register and l2.scholarship_id is null and l2.provider_id is not null
           group by l2.listing_id having count(distinct s.id) = 1) m
   where l.register_code = p_register and l.listing_id = m.listing_id;
  get diagnostics v_name = row_count;

  with todo as (
    select l.listing_id, l.provider_id, l.website_url, l.name,
           security.url_on_provider_sites(l.website_url, l.provider_id) on_site
      from scholarship.register_listings l
      join scholarship.registers r on r.code = l.register_code and r.role = 'index'
     where l.register_code = p_register and l.scholarship_id is null and l.departed_at is null
       and l.provider_id is not null and l.website_url ~* '^https?://' and l.candidate_id is null
  ), ins as (
    insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source)
    select t.provider_id, t.website_url, security.scholarship_url_norm(t.website_url), left(t.name, 300), 'register'
      from todo t where t.on_site
    on conflict (provider_id, url_norm) do update set title = coalesce(pipeline.scholarship_page_candidates.title, excluded.title)
    returning id, provider_id, url_norm
  ), mark as (
    update scholarship.register_listings l
       set candidate_id = i.id, handoff_status = 'handed_to_page_reader'
      from ins i
     where l.register_code = p_register and l.provider_id = i.provider_id
       and security.scholarship_url_norm(l.website_url) = i.url_norm and l.candidate_id is null
    returning 1
  ) select count(*) into v_handed from mark;
  update scholarship.register_listings l set handoff_status = 'provider_page_off_provider_site'
   where l.register_code = p_register and l.scholarship_id is null and l.candidate_id is null and l.provider_id is not null
     and l.website_url ~* '^https?://' and not security.url_on_provider_sites(l.website_url, l.provider_id)
     and l.handoff_status is distinct from 'provider_page_off_provider_site';
  get diagnostics v_offsite = row_count;
  update scholarship.register_listings l set handoff_status = 'matched'
   where l.register_code = p_register and l.scholarship_id is not null and l.handoff_status is distinct from 'matched';
  return jsonb_build_object('by_register_id', v_id, 'by_provider_page', v_page, 'by_provider_and_name', v_name,
                            'handed_to_page_reader', v_handed, 'off_provider_site', v_offsite);
end $$;
