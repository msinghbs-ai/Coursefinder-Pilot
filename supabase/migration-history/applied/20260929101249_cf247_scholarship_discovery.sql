-- CF-247 scholarship discovery (29 Sep 2026; lead direction: provider pages for the Study Australia-only scholarships,
-- then new scholarships from provider pages; nothing published).
--  Step 1: 200 active scholarships are held only from Study Australia (studyaustralia.gov.au), so Decision 139 cannot
--    publish them (no provider page). The worker (coverage-sweep mode scholarship_discover) lists each provider's own
--    scholarship pages (site map first, one Firecrawl map with search "scholarship" only when the site map gives none),
--    matches held scholarships to a page by exact name in the page address or title (strong matches only), and falls
--    back to one Firecrawl web search "<exact name>" site:<domain> per unmatched scholarship. A matched page becomes the
--    scholarship's page for the existing reader, which now confirms the page names the scholarship before anything is
--    applied (read_status 'name_mismatch' otherwise, nothing applied). When a matched page is confirmed, the provider
--    page becomes the record's source (the Study Australia address and identifier are kept in the change log / identifiers).
--  Step 2: unheld candidate pages at Australian universities (university groups first) are read directly (no Firecrawl)
--    and a page becomes a NEW unpublished scholarship only through security.scholarship_admit_from_provider_page_v1:
--    single named scholarship detail page, provider's own domain, explicitly open to international students, currently
--    offered, not already held (same name or same page at the provider). The normal sweep apply then runs on it.
--  Firecrawl for this work is capped at 3,000 credits (purposes sch_map, sch_search, sch_scrape).
--  Publication is untouched: security.scholarship_publish_batch_v1 stays a hand-run step by the lead.

-- ---------------------------------------------------------------------------------------------------------------
-- tables
create table if not exists pipeline.scholarship_discovery_providers (
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  website text not null, site_origin text, priority int not null, reason text not null,
  status text not null default 'pending', method text, url_count int, kept_count int, matched_count int,
  attempts int not null default 0, leased_until timestamptz, discovered_at timestamptz, last_error text,
  updated_at timestamptz not null default now());
create table if not exists pipeline.scholarship_page_candidates (
  id bigint generated always as identity primary key,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  url text not null, url_norm text not null, title text, source text not null check (source in ('sitemap','map','search')),
  found_at timestamptz not null default now(),
  matched_scholarship_id uuid references scholarship.scholarships(id) on delete set null, match_basis text, matched_at timestamptz,
  read_status text, http_status int, fetched_via text, final_url text, read_at timestamptz, attempts int not null default 0,
  leased_until timestamptz, next_read_at timestamptz not null default now(), storage_path text, content_hash text, facts jsonb,
  admit_status text, admit_reasons text[], admitted_scholarship_id uuid references scholarship.scholarships(id) on delete set null, admitted_at timestamptz,
  unique (provider_id, url_norm));
create index if not exists scholarship_page_candidates_read_idx on pipeline.scholarship_page_candidates (next_read_at) where matched_scholarship_id is null and admit_status is null;
create table if not exists pipeline.scholarship_page_searches (
  scholarship_id uuid primary key references scholarship.scholarships(id) on delete cascade,
  query text, status text not null default 'leased', results jsonb, matched_url text, searched_at timestamptz not null default now());
create table if not exists pipeline.scholarship_admission_log (
  id bigint generated always as identity primary key, candidate_id bigint, scholarship_id uuid, provider_id uuid,
  action text not null, detail jsonb, at timestamptz not null default now());
alter table pipeline.scholarship_discovery_providers enable row level security;
alter table pipeline.scholarship_page_candidates enable row level security;
alter table pipeline.scholarship_page_searches enable row level security;
alter table pipeline.scholarship_admission_log enable row level security;
alter table pipeline.scholarship_pages add column if not exists url_source text not null default 'original';
alter table pipeline.scholarship_pages add column if not exists candidate_id bigint;
alter table pipeline.scholarship_pages add column if not exists name_check jsonb;

-- helpers
create or replace function security.url_base_host(p_url text)
returns text language sql immutable set search_path to 'pg_catalog' as $f$
  select nullif(array_to_string((string_to_array(h, '.'))[greatest(1, cardinality(string_to_array(h, '.'))-2):], '.'), '')
    from (select regexp_replace(lower(coalesce(substring(p_url from '^[a-zA-Z]+://([^/:?#]+)'), p_url)), '^www\.', '') h) x
$f$;
create or replace function security.url_on_provider_site(p_url text, p_site text)
returns boolean language sql immutable set search_path to 'pg_catalog','security' as $f$
  select coalesce(security.url_base_host(p_url) = security.url_base_host(p_site)
      or lower(substring(p_url from '^[a-zA-Z]+://([^/:?#]+)')) like '%.' || security.url_base_host(p_site), false)
$f$;
create or replace function security.scholarship_url_norm(p_url text)
returns text language sql immutable set search_path to 'pg_catalog' as $f$
  select regexp_replace(regexp_replace(lower(split_part(btrim(coalesce(p_url,'')),'#',1)),'^http://','https://'),'/+$','')
$f$;
create or replace function security.australian_university(p_provider_id uuid)
returns boolean language sql stable security definer set search_path to 'pg_catalog','catalogue','ref','security' as $f$
  select exists (select 1 from catalogue.providers p join ref.countries c on c.id=p.country_id
     where p.id=p_provider_id and c.iso_alpha2='AU' and p.lifecycle_status='active'
       and (jsonb_array_length(coalesce(security.provider_university_groups(p.id),'[]'))>0
            or (p.canonical_name ~* '\muniversity\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
$f$;
revoke all on function security.url_base_host(text), security.url_on_provider_site(text,text), security.scholarship_url_norm(text), security.australian_university(uuid) from public, anon, authenticated;

-- queue: providers holding Study Australia-only scholarships first, then Australian universities (groups first)
insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason)
select x.provider_id, x.website, x.priority, x.reason from (
  select distinct on (p.id) p.id provider_id, coalesce(d.website, p.website) website,
         case when exists (select 1 from scholarship.scholarships s where s.provider_id=p.id and s.lifecycle_status='active' and s.source_url ~* 'studyaustralia\.gov\.au')
              then case when jsonb_array_length(coalesce(security.provider_university_groups(p.id),'[]'))>0 then 0 when security.australian_university(p.id) then 1 else 2 end
              else case when jsonb_array_length(coalesce(security.provider_university_groups(p.id),'[]'))>0 then 3 else 4 end end priority,
         case when exists (select 1 from scholarship.scholarships s where s.provider_id=p.id and s.lifecycle_status='active' and s.source_url ~* 'studyaustralia\.gov\.au')
              then 'held_study_australia_only' when jsonb_array_length(coalesce(security.provider_university_groups(p.id),'[]'))>0 then 'university_group' else 'university' end reason
    from catalogue.providers p left join pipeline.coverage_provider_discovery d on d.provider_id=p.id
   where coalesce(d.website, p.website) is not null and p.lifecycle_status='active'
     and (exists (select 1 from scholarship.scholarships s where s.provider_id=p.id and s.lifecycle_status='active' and s.source_url ~* 'studyaustralia\.gov\.au')
          or (security.australian_university(p.id) and exists (select 1 from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active')))
) x
-- one university provider per site (two Victoria University records share vu.edu.au): keep the one with more courses
where x.reason='held_study_australia_only' or not exists (
  select 1 from catalogue.providers p2 left join pipeline.coverage_provider_discovery d2 on d2.provider_id=p2.id
   where p2.id<>x.provider_id and security.australian_university(p2.id) and security.url_base_host(coalesce(d2.website,p2.website))=security.url_base_host(x.website)
     and (select count(*) from catalogue.courses c where c.provider_id=p2.id and c.lifecycle_status='active') > (select count(*) from catalogue.courses c where c.provider_id=x.provider_id and c.lifecycle_status='active'))
on conflict (provider_id) do nothing;

-- Firecrawl used by this work (cap 3,000 credits, enforced in the worker)
create or replace function public.svc_scholarship_fc_used()
returns numeric language sql stable security definer set search_path to 'pg_catalog','pipeline' as $f$
  select coalesce(sum(units),0) from pipeline.coverage_vendor_usage where purpose in ('sch_map','sch_search','sch_scrape')
$f$;

-- held Study Australia-only scholarships of a provider that have no page yet
create or replace function security.scholarship_held_without_page(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','scholarship','pipeline' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',s.id,'name',s.name) order by s.name),'[]'::jsonb)
    from scholarship.scholarships s
   where s.provider_id=p_provider_id and s.lifecycle_status='active' and s.source_url ~* 'studyaustralia\.gov\.au'
     and not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id)
     and not exists (select 1 from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url')
$f$;
create or replace function security.provider_name_list(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','catalogue' as $f$
  select jsonb_build_array(p.canonical_name, p.display_name, p.short_name) from catalogue.providers p where p.id=p_provider_id
$f$;
revoke all on function security.scholarship_held_without_page(uuid), security.provider_name_list(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Step 1: a matched provider page becomes the scholarship's page (read and confirmed by the reader before use)
create or replace function security.scholarship_page_match_v1(p_scholarship_id uuid, p_url text, p_basis text, p_candidate_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','scholarship','pipeline','security' as $f$
declare s record; v_site text; v_norm text:=security.scholarship_url_norm(p_url);
begin
  select * into s from scholarship.scholarships where id=p_scholarship_id for update;
  if s.id is null or s.lifecycle_status<>'active' then return jsonb_build_object('matched',false,'reason','not active'); end if;
  if coalesce(s.source_url,'') !~* 'studyaustralia\.gov\.au' then return jsonb_build_object('matched',false,'reason','already has a provider source'); end if;
  -- a page already read for it stays, except a discovered page the reader rejected (it did not name the scholarship)
  if exists (select 1 from pipeline.scholarship_pages where scholarship_id=s.id and not (url_source='discovered' and read_status='name_mismatch'))
    then return jsonb_build_object('matched',false,'reason','already has a page'); end if;
  select coalesce(site_origin, website) into v_site from pipeline.scholarship_discovery_providers where provider_id=s.provider_id;
  if v_site is null or not security.url_on_provider_site(p_url, v_site) or p_url ~* 'studyaustralia\.gov\.au' then return jsonb_build_object('matched',false,'reason','not on the provider site'); end if;
  if exists (select 1 from pipeline.scholarship_pages sp where security.scholarship_url_norm(sp.url)=v_norm)
     or exists (select 1 from scholarship.scholarships x where x.id<>s.id and security.scholarship_url_norm(x.source_url)=v_norm)
     or exists (select 1 from scholarship.identifiers i where i.scheme='first_party_detail_url' and security.scholarship_url_norm(i.identifier_value)=v_norm)
    then return jsonb_build_object('matched',false,'reason','page already belongs to another scholarship'); end if;
  delete from pipeline.scholarship_pages where scholarship_id=s.id and url_source='discovered' and read_status='name_mismatch';
  insert into pipeline.scholarship_pages(scholarship_id,url,url_source,candidate_id,next_read_at) values (s.id,p_url,'discovered',p_candidate_id,now());
  if p_candidate_id is not null then
    update pipeline.scholarship_page_candidates set matched_scholarship_id=s.id, match_basis=p_basis, matched_at=now() where id=p_candidate_id;
  end if;
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
  values (s.id,'provider_page_matched',jsonb_build_object('source_url',s.source_url),jsonb_build_object('url',p_url,'basis',p_basis,'candidate_id',p_candidate_id));
  return jsonb_build_object('matched',true);
end $f$;
revoke all on function security.scholarship_page_match_v1(uuid,text,text,bigint) from public, anon, authenticated;

create or replace function public.svc_scholarship_discover_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.scholarship_discovery_providers d
     where d.status='pending' and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
     order by d.priority, d.provider_id limit greatest(1,least(coalesce(p_limit,3),6)) for update skip locked),
  upd as (update pipeline.scholarship_discovery_providers d set leased_until=now()+interval '5 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website, d.reason)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,'reason',u.reason,
           'names',security.provider_name_list(u.provider_id),'held',security.scholarship_held_without_page(u.provider_id))),'[]'::jsonb) into v from upd u;
  return v;
end $f$;

create or replace function public.svc_scholarship_discover_record(p_provider_id uuid, p_status text, p_site_origin text, p_method text, p_url_count int,
  p_candidates jsonb, p_matches jsonb, p_error text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v_kept int; v_matched int:=0; m jsonb; r jsonb; v_cid bigint;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.scholarship_page_candidates(provider_id,url,url_norm,title,source)
  select p_provider_id, c->>'url', security.scholarship_url_norm(c->>'url'), nullif(left(c->>'title',300),''), coalesce(c->>'source','sitemap')
    from jsonb_array_elements(coalesce(p_candidates,'[]')) c
   where coalesce(c->>'url','') ~* '^https?://' and security.url_on_provider_site(c->>'url', coalesce(p_site_origin,(select website from pipeline.scholarship_discovery_providers where provider_id=p_provider_id)))
  on conflict (provider_id,url_norm) do update set title=coalesce(pipeline.scholarship_page_candidates.title, excluded.title);
  select count(*) into v_kept from pipeline.scholarship_page_candidates where provider_id=p_provider_id;
  update pipeline.scholarship_discovery_providers set status=p_status, site_origin=coalesce(p_site_origin,site_origin), method=p_method, url_count=p_url_count,
         kept_count=v_kept, discovered_at=now(), leased_until=null, last_error=p_error, updated_at=now() where provider_id=p_provider_id;
  for m in select * from jsonb_array_elements(coalesce(p_matches,'[]')) loop
    select id into v_cid from pipeline.scholarship_page_candidates where provider_id=p_provider_id and url_norm=security.scholarship_url_norm(m->>'url');
    if v_cid is null then continue; end if;
    if (select provider_id from scholarship.scholarships where id=(m->>'scholarship_id')::uuid) is distinct from p_provider_id then continue; end if;
    r:=security.scholarship_page_match_v1((m->>'scholarship_id')::uuid, m->>'url', m->>'basis', v_cid);
    if (r->>'matched')::boolean then v_matched:=v_matched+1; end if;
  end loop;
  update pipeline.scholarship_discovery_providers set matched_count=coalesce(matched_count,0)+v_matched where provider_id=p_provider_id;
  return jsonb_build_object('kept',v_kept,'matched',v_matched);
end $f$;

-- one budget-guarded web search per held scholarship still without a page after discovery
create or replace function public.svc_scholarship_search_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','scholarship','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.id, s.name, s.provider_id, coalesce(d.site_origin,d.website) site from scholarship.scholarships s
      join pipeline.scholarship_discovery_providers d on d.provider_id=s.provider_id and d.status in ('mapped','empty','failed')
     where s.lifecycle_status='active' and s.source_url ~* 'studyaustralia\.gov\.au'
       and not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id and not (sp.url_source='discovered' and sp.read_status='name_mismatch'))
       and not exists (select 1 from pipeline.scholarship_page_searches q where q.scholarship_id=s.id)
     order by d.priority, s.provider_id, s.name limit greatest(1,least(coalesce(p_limit,5),20))),
  ins as (insert into pipeline.scholarship_page_searches(scholarship_id,status) select id,'leased' from pick on conflict do nothing returning scholarship_id)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',p.id,'name',p.name,'provider_id',p.provider_id,'site',p.site,'names',security.provider_name_list(p.provider_id))),'[]'::jsonb)
    into v from pick p join ins on ins.scholarship_id=p.id;
  return v;
end $f$;

create or replace function public.svc_scholarship_search_record(p_scholarship_id uuid, p_query text, p_status text, p_results jsonb, p_match jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','scholarship','security' as $f$
declare v_pid uuid; v_site text; v_cid bigint; r jsonb:=jsonb_build_object('matched',false);
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.provider_id, coalesce(d.site_origin,d.website) into v_pid, v_site from scholarship.scholarships s join pipeline.scholarship_discovery_providers d on d.provider_id=s.provider_id where s.id=p_scholarship_id;
  update pipeline.scholarship_page_searches set query=p_query, status=p_status, results=p_results, matched_url=p_match->>'url', searched_at=now() where scholarship_id=p_scholarship_id;
  insert into pipeline.scholarship_page_candidates(provider_id,url,url_norm,title,source)
  select v_pid, x->>'url', security.scholarship_url_norm(x->>'url'), nullif(left(x->>'title',300),''), 'search'
    from jsonb_array_elements(coalesce(p_results,'[]')) x where x->>'kept'='true' and security.url_on_provider_site(x->>'url', v_site)
  on conflict (provider_id,url_norm) do update set title=coalesce(pipeline.scholarship_page_candidates.title, excluded.title);
  if p_match ? 'url' then
    select id into v_cid from pipeline.scholarship_page_candidates where provider_id=v_pid and url_norm=security.scholarship_url_norm(p_match->>'url');
    if v_cid is not null then r:=security.scholarship_page_match_v1(p_scholarship_id, p_match->>'url', p_match->>'basis', v_cid); end if;
  end if;
  return r;
end $f$;

-- ---------------------------------------------------------------------------------------------------------------
-- Step 2: a NEW scholarship from an unheld provider page (one governed function)
create or replace function security.scholarship_admit_from_provider_page_v1(p_candidate_id bigint)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','scholarship','pipeline','catalogue','pim','security' as $f$
declare c record; d record; f jsonb; v_name text; v_url text; v_norm text; v_key text; v_id uuid; v_src uuid; v_ev uuid; v_dup uuid; v_dup_sa boolean; v_apply jsonb; r jsonb;
begin
  select * into c from pipeline.scholarship_page_candidates where id=p_candidate_id for update;
  if c.id is null then return jsonb_build_object('admitted',false,'reason','no candidate'); end if;
  if c.admitted_scholarship_id is not null or c.matched_scholarship_id is not null then return jsonb_build_object('admitted',false,'reason','already handled'); end if;
  select * into d from pipeline.scholarship_discovery_providers where provider_id=c.provider_id;
  f:=c.facts; v_name:=btrim(f->'admission'->>'name'); v_url:=coalesce(c.final_url,c.url); v_norm:=security.scholarship_url_norm(v_url);
  -- the rules, checked again here from the recorded page facts
  if c.read_status is distinct from 'read' or c.storage_path is null then r:=jsonb_build_object('admitted',false,'reason','page not read');
  elsif not security.australian_university(c.provider_id) then r:=jsonb_build_object('admitted',false,'reason','not an Australian university provider');
  elsif not security.url_on_provider_site(v_url, coalesce(d.site_origin,d.website)) or v_url ~* 'studyaustralia\.gov\.au' then r:=jsonb_build_object('admitted',false,'reason','not on the provider site');
  elsif coalesce(v_name,'')='' or length(v_name)<8 or v_name !~* '(scholarship|bursary|award|grant|fee (remission|reduction|waiver|discount)|tuition (discount|reduction|waiver))' then r:=jsonb_build_object('admitted',false,'reason','no named scholarship title');
  elsif coalesce((f->'admission'->>'detail_page')::boolean,false) is not true then r:=jsonb_build_object('admitted',false,'reason','not a single scholarship page');
  elsif coalesce((f->'admission'->>'international_explicit')::boolean,false) is not true or coalesce((f->>'international')::boolean,false) is not true then r:=jsonb_build_object('admitted',false,'reason','not explicitly open to international students');
  elsif coalesce((f->'admission'->>'offered')::boolean,false) is not true then r:=jsonb_build_object('admitted',false,'reason','not currently offered');
  elsif coalesce((f->'admission'->>'admit')::boolean,false) is not true then r:=jsonb_build_object('admitted',false,'reason','page rules not met');
  end if;
  if r is not null then
    update pipeline.scholarship_page_candidates set admit_status='rejected', admit_reasons=array[r->>'reason'] where id=c.id;
    insert into pipeline.scholarship_admission_log(candidate_id,provider_id,action,detail) values (c.id,c.provider_id,'rejected',r);
    return r;
  end if;
  -- already held: same page, or same name at this provider
  select s.id, s.source_url ~* 'studyaustralia\.gov\.au' into v_dup, v_dup_sa from scholarship.scholarships s
   where s.provider_id=c.provider_id and s.lifecycle_status='active'
     and (security.scholarship_url_norm(s.source_url)=v_norm or scholarship.normalise_title(s.name)=scholarship.normalise_title(v_name)
          or exists (select 1 from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url' and security.scholarship_url_norm(i.identifier_value) in (v_norm, c.url_norm))
          or exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id and security.scholarship_url_norm(sp.url) in (v_norm, c.url_norm)))
   order by (s.source_url ~* 'studyaustralia\.gov\.au') limit 1;
  if v_dup is not null then
    if v_dup_sa and not exists (select 1 from pipeline.scholarship_pages where scholarship_id=v_dup) then
      -- a held Study Australia-only scholarship named by this page's heading: step 1 match, read and confirmed by the reader
      r:=security.scholarship_page_match_v1(v_dup, c.url, 'page_heading', c.id);
      update pipeline.scholarship_page_candidates set admit_status='matched_held' where id=c.id;
      insert into pipeline.scholarship_admission_log(candidate_id,scholarship_id,provider_id,action,detail) values (c.id,v_dup,c.provider_id,'matched_held',r);
      return jsonb_build_object('admitted',false,'reason','held scholarship matched','scholarship_id',v_dup,'match',r);
    end if;
    update pipeline.scholarship_page_candidates set admit_status='duplicate', admit_reasons=array['already held'] where id=c.id;
    insert into pipeline.scholarship_admission_log(candidate_id,scholarship_id,provider_id,action,detail) values (c.id,v_dup,c.provider_id,'duplicate',jsonb_build_object('name',v_name));
    return jsonb_build_object('admitted',false,'reason','already held','scholarship_id',v_dup);
  end if;

  v_key:='scholarship:AU:first-party:'||replace(c.provider_id::text,'-','')||':'||md5(v_norm);
  v_id:=scholarship.deterministic_uuid(v_key);
  if exists (select 1 from scholarship.scholarships where id=v_id) then
    update pipeline.scholarship_page_candidates set admit_status='duplicate', admit_reasons=array['same stable key'] where id=c.id;
    return jsonb_build_object('admitted',false,'reason','same stable key','scholarship_id',v_id);
  end if;
  v_src:=security.coverage_sweep_source(c.provider_id);
  insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status) values (v_id,'scholarship',v_key,'active') on conflict (stable_key) do update set lifecycle_status='active', updated_at=now();
  insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
  values (v_id, v_src, 'scholarship_page', v_url, c.storage_path, c.content_hash, 'application/gzip',
          jsonb_build_object('worker','coverage-sweep scholarship_discover','decision','CF-247 scholarship discovery (Decision 139 sweep)','candidate_id',c.id,'extractor',f->>'extractor'), 1, 'scholarship:'||v_id)
  returning id into v_ev;
  insert into scholarship.scholarships(id,stable_key,provider_id,name,scholarship_type,audience,source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence,award_value_type,updated_at)
  values (v_id,v_key,c.provider_id,left(v_name,300),'provider_scholarship','international',v_url,'active','unpublished',v_src,v_ev,0.9,'text_only',now());
  insert into scholarship.identifiers(scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
  values (v_id,'first_party_detail_url',v_url,v_src,v_ev,true,'active') on conflict do nothing;
  insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,updated_at,metadata)
  values (c.provider_id,left(v_name,300),v_url,v_id,v_ev,'canonical_unpublished','verified_first_party',c.found_at,now(),now(),
          jsonb_build_object('admission','security.scholarship_admit_from_provider_page_v1','candidate_id',c.id,'candidate_source',c.source,'rule','single named scholarship detail page on the provider site, explicitly open to international students, currently offered'));
  insert into pipeline.scholarship_pages(scholarship_id,url,url_source,candidate_id,final_url,read_status,http_status,fetched_via,read_at,next_read_at,attempts,evidence_id,facts,name_check)
  values (v_id,v_url,'admitted',c.id,c.final_url,'read',c.http_status,c.fetched_via,c.read_at,now()+interval '90 days',0,v_ev,f,jsonb_build_object('ok',true,'basis','admitted_from_page_title','heading',v_name));
  update pipeline.scholarship_page_candidates set admit_status='admitted', admitted_scholarship_id=v_id, admitted_at=now() where id=c.id;
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (v_id,'admitted',null,jsonb_build_object('name',v_name,'url',v_url,'candidate_id',c.id),v_ev);
  v_apply:=security.scholarship_sweep_apply_v1(v_id);
  insert into pipeline.scholarship_admission_log(candidate_id,scholarship_id,provider_id,action,detail) values (c.id,v_id,c.provider_id,'admitted',jsonb_build_object('name',v_name,'url',v_url,'apply',v_apply));
  return jsonb_build_object('admitted',true,'scholarship_id',v_id,'apply',v_apply);
end $f$;
revoke all on function security.scholarship_admit_from_provider_page_v1(bigint) from public, anon, authenticated;

create or replace function public.svc_scholarship_candidate_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select c.id from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id
     where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
       and security.australian_university(c.provider_id)
     order by (d.priority not in (0,3)), (c.url ~* 'international') desc, c.found_at, c.id
     limit greatest(1,least(coalesce(p_limit,30),60)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $f$;

create or replace function public.svc_scholarship_candidate_record(p_candidate_id bigint, p_read_status text, p_http_status int, p_fetched_via text,
  p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare r jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_read_status='deferred' then -- out of time in this run: back to the queue unchanged
    update pipeline.scholarship_page_candidates set leased_until=null, attempts=greatest(0,attempts-1) where id=p_candidate_id;
    return jsonb_build_object('admitted',false,'deferred',true);
  end if;
  update pipeline.scholarship_page_candidates set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, storage_path=coalesce(p_storage_path,storage_path), content_hash=coalesce(p_sha256,content_hash), facts=coalesce(p_facts,facts),
         next_read_at=case when p_read_status in ('read','robots_disallowed','gone') then now()+interval '90 days' else now()+interval '6 hours' end,
         admit_status=case when p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true then 'rejected' else admit_status end,
         admit_reasons=case when p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true
                            then array(select jsonb_array_elements_text(coalesce(p_facts->'admission'->'reasons','[]'))) else admit_reasons end
   where id=p_candidate_id;
  if p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) then r:=security.scholarship_admit_from_provider_page_v1(p_candidate_id); end if;
  return coalesce(r, jsonb_build_object('admitted',false));
end $f$;

-- stored page paths for hand checks (worker mode scholarship_inspect; read only)
create or replace function public.svc_scholarship_inspect_paths(p_scholarship_ids uuid[], p_candidate_ids bigint[])
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline','scholarship' as $f$
  select jsonb_build_object(
    'scholarships', coalesce((select jsonb_agg(jsonb_build_object('scholarship_id',s.id,'name',s.name,'provider_id',s.provider_id,'url',coalesce(sp.final_url,sp.url),'storage_path',e.storage_path,'names',security.provider_name_list(s.provider_id)))
        from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id=s.id left join pipeline.evidence_artifacts e on e.id=sp.evidence_id
       where s.id=any(coalesce(p_scholarship_ids,'{}'))),'[]'::jsonb),
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('candidate_id',c.id,'provider_id',c.provider_id,'url',coalesce(c.final_url,c.url),'storage_path',c.storage_path))
        from pipeline.scholarship_page_candidates c where c.id=any(coalesce(p_candidate_ids,'{}'))),'[]'::jsonb))
$f$;

revoke all on function public.svc_scholarship_fc_used(), public.svc_scholarship_discover_next(int), public.svc_scholarship_discover_record(uuid,text,text,text,int,jsonb,jsonb,text),
  public.svc_scholarship_search_next(int), public.svc_scholarship_search_record(uuid,text,text,jsonb,jsonb), public.svc_scholarship_candidate_next(int),
  public.svc_scholarship_candidate_record(bigint,text,int,text,text,text,text,jsonb), public.svc_scholarship_inspect_paths(uuid[],bigint[]) from public, anon, authenticated;
grant execute on function public.svc_scholarship_fc_used(), public.svc_scholarship_discover_next(int), public.svc_scholarship_discover_record(uuid,text,text,text,int,jsonb,jsonb,text),
  public.svc_scholarship_search_next(int), public.svc_scholarship_search_record(uuid,text,text,jsonb,jsonb), public.svc_scholarship_candidate_next(int),
  public.svc_scholarship_candidate_record(bigint,text,int,text,text,text,text,jsonb), public.svc_scholarship_inspect_paths(uuid[],bigint[]) to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Reader: provider names for the name check; a page that does not name the scholarship applies nothing.
do $patch$
declare v text; o text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.svc_scholarship_read_next(int)'::regprocedure)<>'70444e72e38db066510bedc1c0111e50' then
    raise exception 'svc_scholarship_read_next changed since review; not replaced'; end if;
  v:=pg_get_functiondef('public.svc_scholarship_read_next(int)'::regprocedure);
  o:=$o$'provider_id',s.provider_id))$o$;
  n:=$n$'provider_id',s.provider_id,'url_source',u.url_source,'names',security.provider_name_list(s.provider_id)))$n$;
  if position(o in v)=0 or position($o$returning p.scholarship_id, p.url)$o$ in v)=0 then raise exception 'read_next anchors not found'; end if;
  v:=replace(replace(v,o,n),$o$returning p.scholarship_id, p.url)$o$,$n$returning p.scholarship_id, p.url, p.url_source)$n$);
  v:=replace(v,$o$set search_path to 'pg_catalog','scholarship','pipeline'$o$,$n$set search_path to 'pg_catalog','scholarship','pipeline','security'$n$);
  v:=replace(v,$o$SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'$o$,$n$SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'$n$);
  execute v;

  if (select md5(prosrc) from pg_proc where oid='public.svc_scholarship_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure)<>'b896aabe12f044127f9d14141c112db5' then
    raise exception 'svc_scholarship_read_record changed since review; not replaced'; end if;
  v:=pg_get_functiondef('public.svc_scholarship_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure);
  o:=$o$read_at=now(), leased_until=null, evidence_id=coalesce(v_ev,evidence_id), facts=coalesce(p_facts,facts),$o$;
  n:=$n$read_at=now(), leased_until=null, evidence_id=case when p_read_status='read' then coalesce(v_ev,evidence_id) else evidence_id end,
         facts=case when p_read_status='read' then coalesce(p_facts,facts) else facts end,
         name_check=case when p_facts ? 'name_check' then p_facts->'name_check' else name_check end,$n$;
  if position(o in v)=0 then raise exception 'read_record facts anchor not found'; end if;
  v:=replace(v,o,n);
  o:=$o$when p_read_status in ('robots_disallowed','blocked') then now()+interval '30 days'$o$;
  n:=$n$when p_read_status in ('robots_disallowed','blocked','name_mismatch') then now()+interval '30 days'$n$;
  if position(o in v)=0 then raise exception 'read_record schedule anchor not found'; end if;
  v:=replace(v,o,n);
  -- evidence only for a page that names the scholarship
  o:=$o$  if p_storage_path is not null then$o$;
  n:=$n$  if p_storage_path is not null and p_read_status='read' then$n$;
  if position(o in v)=0 then raise exception 'read_record evidence anchor not found'; end if;
  v:=replace(v,o,n);
  o:=$o$  if p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;$o$;
  n:=$n$  if p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;
  -- a discovered page that does not name the scholarship: the match is released (logged) so another page can be tried
  if p_read_status='name_mismatch' then
    update pipeline.scholarship_page_candidates c set match_basis='rejected_name_mismatch', matched_scholarship_id=null
      from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id and sp.url_source='discovered' and c.id=sp.candidate_id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
    select p_scholarship_id,'provider_page_rejected',jsonb_build_object('url',sp.url,'url_source',sp.url_source),p_facts->'name_check' from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id;
  end if;$n$;
  if position(o in v)=0 then raise exception 'read_record apply anchor not found'; end if;
  v:=replace(v,o,n);
  execute v;

  -- apply: a confirmed discovered page becomes the provider source of a Study Australia-only record (Decision 139)
  if (select md5(prosrc) from pg_proc where oid='security.scholarship_sweep_apply_v1(uuid)'::regprocedure)<>'b45088b5e425da379aa4591d6e745dc7' then
    raise exception 'scholarship_sweep_apply_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.scholarship_sweep_apply_v1(uuid)'::regprocedure);
  o:=$o$  if coalesce(pg.final_url,pg.url) !~* 'studyaustralia\.gov\.au' and not exists$o$;
  n:=$n$  -- a discovered provider page, confirmed by the reader to name this scholarship, replaces the Study Australia source
  if pg.url_source='discovered' and coalesce(s.source_url,'') ~* 'studyaustralia\.gov\.au' and coalesce(pg.final_url,pg.url) !~* 'studyaustralia\.gov\.au'
     and coalesce((pg.name_check->>'ok')::boolean,false) then
    update scholarship.scholarships set source_url=pg.url, evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
    values (s.id,'source_url',jsonb_build_object('source_url',s.source_url,'evidence_id',s.evidence_id),jsonb_build_object('source_url',pg.url,'name_check',pg.name_check),pg.evidence_id);
    v_changes:=v_changes||'source_url'::text;
  end if;

  if coalesce(pg.final_url,pg.url) !~* 'studyaustralia\.gov\.au' and not exists$n$;
  if position(o in v)=0 then raise exception 'apply anchor not found'; end if;
  execute replace(v,o,n);
end $patch$;

-- Cron: discovery, the one-off searches and candidate reads, every 10 minutes (sitemaps and direct reads are free;
-- Firecrawl only inside the 3,000-credit cap). Publication is not scheduled.
select cron.schedule('scholarship-discover','*/10 * * * *',$$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"scholarship_discover","limit":3}'::jsonb)$$);
