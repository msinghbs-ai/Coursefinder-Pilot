-- CF-247 Scholarships: central register, country tagged, on Layer 1.
-- Platform Admin decisions 8 Oct 2026 (multiple choice): "Central register, country tagged";
-- "Record for govt, index for provider"; "AU, then NZ, then CA, monthly".
--
-- * scholarship.registers: one row per country register (code, country, role).
--   role 'record' = government awards are read from the register into scholarships;
--   role 'index'  = provider listings are kept as a completeness index that links to the
--   provider's own page, which stays the source of record (handed to the page reader).
-- * scholarship.register_listings: every listing seen on an index register, country tagged,
--   with its match to a held scholarship or its hand-off to the provider page reader.
-- * The two Australian registers become Layer 1 sources (source_system SCHOLARSHIP_REGISTER),
--   so they get the Layer 1 schedule choice, verification, variance gate and runs.
-- * The old hourly scholarship ETL feeds for the same two sources are switched off (the
--   Layer 1 schedule replaces them); their rows are kept.

create table if not exists scholarship.registers (
  code text primary key,
  country_code char(2) not null,
  name text not null,
  url text not null,
  role text not null check (role in ('record','index')),
  source_id uuid references pipeline.sources(id),
  reader text,
  status text not null default 'planned' check (status in ('planned','live','paused')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists scholarship.register_listings (
  register_code text not null references scholarship.registers(code),
  listing_id text not null,
  country_code char(2) not null,
  url text not null,
  name text not null,
  provider_ref text,
  provider_name text,
  provider_cricos text,
  provider_id uuid references catalogue.providers(id) on delete set null,
  level_text text,
  award_text text,
  closing_text text,
  nationality_text text,
  website_url text,
  content_hash text not null,
  scholarship_id uuid references scholarship.scholarships(id) on delete set null,
  match_basis text,
  candidate_id bigint,
  handoff_status text,
  detail_hash text,
  detail_read_at timestamptz,
  detail_error text,
  detail_evidence_id uuid,
  evidence_id uuid,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  departed_at timestamptz,
  last_run_id uuid,
  primary key (register_code, listing_id)
);
create index if not exists register_listings_provider_idx on scholarship.register_listings(provider_id);
create index if not exists register_listings_scholarship_idx on scholarship.register_listings(scholarship_id);

alter table scholarship.registers enable row level security;
alter table scholarship.register_listings enable row level security;
revoke all on scholarship.registers, scholarship.register_listings from public, anon, authenticated;

insert into scholarship.registers(code, country_code, name, url, role, source_id, reader, status, notes) values
 ('au_study_australia','AU','Study Australia scholarship search','https://search.studyaustralia.gov.au/scholarships','index','17a7d379-9448-41ca-bca5-bb7537ffff4b','scholarships-au-etl study_australia_register','live','Provider and funder scholarships listed by the Australian Government; index only (provider page is the source of record).'),
 ('au_dfat_australia_awards','AU','DFAT Australia Awards Scholarships','https://www.dfat.gov.au/people-to-people/australia-awards/australia-awards-scholarships','record','a9443687-678b-436f-9c16-62fcb800af14','scholarships-au-etl australia_awards','live','Government award read from DFAT pages into a scholarship record.'),
 ('nz_mfat_manaaki','NZ','Manaaki New Zealand Scholarships','https://www.nzscholarships.govt.nz/','record','717432c7-32f9-47c3-9111-7f75fd79c128',null,'planned','Next: New Zealand (Study with New Zealand scholarship pages and Manaaki).'),
 ('ca_gac_study_in_canada','CA','Study in Canada Scholarships (Global Affairs Canada)','https://www.educanada.ca/scholarships-bourses/can/institutions/study-in-canada-sep-etudes-au-canada-pct.aspx?lang=eng','record','b7215f99-cff6-4c92-8d94-349642c254eb',null,'planned','After New Zealand. EduCanada robots.txt blocks automated readers; permission or another official route needed.')
on conflict (code) do nothing;

-- Layer 1 registration of the two Australian registers (schedule is set by a Platform Admin
-- with admin_layer1_schedule after the first verified run; nothing runs automatically yet).
update pipeline.sources
   set metadata = metadata || jsonb_build_object('source_system','SCHOLARSHIP_REGISTER','register_code','au_study_australia','layer1_register',true),
       updated_at = now()
 where id = '17a7d379-9448-41ca-bca5-bb7537ffff4b';
update pipeline.sources
   set metadata = metadata || jsonb_build_object('source_system','SCHOLARSHIP_REGISTER','register_code','au_dfat_australia_awards','layer1_register',true),
       updated_at = now()
 where id = 'a9443687-678b-436f-9c16-62fcb800af14';

insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind,
       active, paused, verification_cadence_days, ingestion_cadence_days, auto_ingest, change_reason)
values
 ('17a7d379-9448-41ca-bca5-bb7537ffff4b','Australian Trade and Investment Commission (Study Australia)',array['studyaustralia.gov.au'],
  'Study Australia scholarship search listing pages (all pages)','scholarship listings',true,false,30,30,false,
  'CF-247 scholarships central register (Platform Admin decision 8 Oct 2026)'),
 ('a9443687-678b-436f-9c16-62fcb800af14','Department of Foreign Affairs and Trade',array['dfat.gov.au'],
  'DFAT Australia Awards Scholarships pages, dates page, policy handbook and OASIS','government awards',true,false,30,30,false,
  'CF-247 scholarships central register (Platform Admin decision 8 Oct 2026)')
on conflict (source_id) do nothing;

update pipeline.scholarship_etl_schedules
   set enabled = false, updated_at = now(),
       last_error = 'Replaced by the Layer 1 scholarship register schedule (CF-247, 8 Oct 2026)'
 where feed in ('study_australia','australia_awards');

-- Save one run's listings (chunks); the final chunk marks departures and matches.
create or replace function public.svc_scholarship_register_save(p_register text, p_run_id uuid, p_evidence_id uuid, p_listings jsonb, p_final boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_country char(2); v_created int := 0; v_updated int := 0; v_unchanged int := 0; v_departed int := 0; v_match jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select country_code into v_country from scholarship.registers where code = p_register;
  if v_country is null then raise exception 'unknown register %', p_register; end if;
  with src as (
    select x->>'id' listing_id, x->>'url' url, x->>'name' name, x->>'provider_ref' provider_ref, x->>'provider_name' provider_name,
           nullif(x->>'level','') level_text, nullif(x->>'award','') award_text, nullif(x->>'closing','') closing_text, nullif(x->>'nationality','') nationality_text,
           md5(concat_ws('|', x->>'name', x->>'provider_ref', x->>'provider_name', x->>'level', x->>'award', x->>'closing', x->>'nationality')) h
      from jsonb_array_elements(coalesce(p_listings,'[]'::jsonb)) x
     where coalesce(x->>'id','') <> '' and coalesce(x->>'name','') <> '' and coalesce(x->>'url','') <> ''
  ), up as (
    insert into scholarship.register_listings as l(register_code, listing_id, country_code, url, name, provider_ref, provider_name,
           level_text, award_text, closing_text, nationality_text, content_hash, evidence_id, last_run_id)
    select p_register, s.listing_id, v_country, s.url, s.name, s.provider_ref, s.provider_name, s.level_text, s.award_text, s.closing_text,
           s.nationality_text, s.h, p_evidence_id, p_run_id from src s
    on conflict (register_code, listing_id) do update
       set url = excluded.url, name = excluded.name, provider_ref = excluded.provider_ref, provider_name = excluded.provider_name,
           level_text = excluded.level_text, award_text = excluded.award_text, closing_text = excluded.closing_text, nationality_text = excluded.nationality_text,
           content_hash = excluded.content_hash, evidence_id = excluded.evidence_id, last_run_id = excluded.last_run_id,
           last_seen_at = now(), departed_at = null
    returning (xmax = 0) ins, (l.content_hash) h
  ) select count(*) filter (where ins), 0, count(*) filter (where not ins) into v_created, v_updated, v_unchanged from up;
  if p_final then
    update scholarship.register_listings set departed_at = now()
     where register_code = p_register and departed_at is null and last_run_id is distinct from p_run_id;
    get diagnostics v_departed = row_count;
    v_match := public.svc_scholarship_register_match(p_register);
  end if;
  return jsonb_build_object('created', v_created, 'seen_again', v_unchanged, 'departed', v_departed, 'match', v_match);
end $$;

-- Match listings to held scholarships: the listing id in a held source address, then the
-- provider's page address, then the same provider and the same name. Then hand unmatched
-- listings with a provider page on the provider's own site to the provider page reader.
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
    select t.provider_id, t.website_url, security.scholarship_url_norm(t.website_url), left(t.name, 300), 'register:' || p_register
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

-- Listings whose detail page (provider page link and provider) still needs reading; unmatched first.
create or replace function public.svc_scholarship_register_detail_next(p_register text, p_limit int default 40)
returns jsonb language sql security definer set search_path = '' as $$
  select case when current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then null else
  jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', x.listing_id, 'url', x.url, 'provider_ref', x.provider_ref,
                 'known_cricos', (select max(o.provider_cricos) from scholarship.register_listings o
                                   where o.register_code = x.register_code and o.provider_ref = x.provider_ref and o.provider_cricos is not null)))
               from (select l.* from scholarship.register_listings l
                      where l.register_code = p_register and l.departed_at is null
                        and (l.detail_read_at is null or l.detail_hash is distinct from l.content_hash)
                      order by (l.scholarship_id is not null), l.first_seen_at, l.listing_id
                      limit greatest(1, least(coalesce(p_limit, 40), 100))) x), '[]'::jsonb),
    'remaining', (select count(*) from scholarship.register_listings l
                   where l.register_code = p_register and l.departed_at is null
                     and (l.detail_read_at is null or l.detail_hash is distinct from l.content_hash))) end
$$;

create or replace function public.svc_scholarship_register_detail_save(p_register text, p_evidence_id uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_saved int := 0; v_remaining bigint; v_match jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  update scholarship.register_listings l
     set website_url = case when nullif(x->>'error','') is null then nullif(x->>'website_url','') else l.website_url end,
         detail_error = nullif(left(x->>'error', 300),''),
         provider_cricos = coalesce(upper(nullif(x->>'provider_cricos','')), l.provider_cricos),
         provider_id = coalesce(public.svc_scholarship_resolve_au_provider(coalesce(upper(nullif(x->>'provider_cricos','')), l.provider_cricos)), l.provider_id),
         detail_read_at = now(), detail_hash = l.content_hash, detail_evidence_id = p_evidence_id
    from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
   where l.register_code = p_register and l.listing_id = x->>'id';
  get diagnostics v_saved = row_count;
  v_match := public.svc_scholarship_register_match(p_register);
  select count(*) into v_remaining from scholarship.register_listings l
   where l.register_code = p_register and l.departed_at is null and (l.detail_read_at is null or l.detail_hash is distinct from l.content_hash);
  return jsonb_build_object('saved', v_saved, 'remaining', v_remaining, 'match', v_match);
end $$;

-- Read for operators and admins (rank 5 and above): one row per register.
create or replace function public.admin_scholarship_registers()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 5 then raise exception 'insufficient role' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'code', r.code, 'country', r.country_code, 'name', r.name, 'role', r.role, 'status', r.status, 'url', r.url,
      'listings', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null),
      'matched', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null and l.scholarship_id is not null),
      'handed_to_page_reader', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null and l.handoff_status = 'handed_to_page_reader'),
      'off_provider_site', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null and l.handoff_status = 'provider_page_off_provider_site'),
      'provider_unknown', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null and l.scholarship_id is null and l.provider_id is null and l.detail_read_at is not null),
      'departed', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is not null),
      'records', (select count(*) from scholarship.scholarships s where s.source_id = r.source_id and s.lifecycle_status = 'active'),
      'last_seen_at', (select max(last_seen_at) from scholarship.register_listings l where l.register_code = r.code)
    ) order by r.country_code, r.code) from scholarship.registers r), '[]'::jsonb);
end $$;

revoke all on function public.svc_scholarship_register_save(text, uuid, uuid, jsonb, boolean) from public, anon, authenticated;
revoke all on function public.svc_scholarship_register_match(text) from public, anon, authenticated;
revoke all on function public.svc_scholarship_register_detail_next(text, int) from public, anon, authenticated;
revoke all on function public.svc_scholarship_register_detail_save(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_scholarship_register_save(text, uuid, uuid, jsonb, boolean) to service_role;
grant execute on function public.svc_scholarship_register_match(text) to service_role;
grant execute on function public.svc_scholarship_register_detail_next(text, int) to service_role;
grant execute on function public.svc_scholarship_register_detail_save(text, uuid, jsonb) to service_role;
revoke all on function public.admin_scholarship_registers() from public, anon;
grant execute on function public.admin_scholarship_registers() to authenticated;
