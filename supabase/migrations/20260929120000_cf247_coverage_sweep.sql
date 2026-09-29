-- CF-247 complete-coverage sweep (Platform Admin direction 29 Sep 2026: complete coverage in days, ongoing).
-- Three stages, none of which writes to the catalogue:
--   1. discover  one Firecrawl map per provider website (1 credit per call, whatever the number of URLs) lists the
--                site's pages; course-like pages are kept in pipeline.coverage_provider_urls.
--   2. bind      in the database, each active course is matched to one page of its own provider: the CRICOS course
--                code in the address or page title, or a close title match with a clear lead over the next page.
--   3. read      each bound page is fetched once (direct first, Firecrawl only when refused), identity is checked
--                (CRICOS course code on the page, or the exact course title in the page title/heading), the page is
--                kept as evidence and tuition, English and intake candidates are recorded.
-- Admission of candidates into the catalogue is a separate, approved rule. Firecrawl calls are recorded in
-- pipeline.coverage_vendor_usage and counted by the existing monthly budget guard (patched below).

create table if not exists pipeline.coverage_provider_discovery(
  provider_id uuid primary key references catalogue.providers(id), website text, status text not null default 'pending',
  method text, url_count int, kept_count int, attempts int not null default 0, last_error text,
  leased_until timestamptz, mapped_at timestamptz, next_due_at timestamptz, updated_at timestamptz not null default now());
create table if not exists pipeline.coverage_provider_urls(
  provider_id uuid not null, url text not null, title text, tokens text[] not null default '{}', title_tokens text[] not null default '{}', source text not null,
  first_seen_at timestamptz not null default now(), last_seen_at timestamptz not null default now(), primary key(provider_id,url));
create table if not exists pipeline.coverage_course_pages(
  course_id uuid primary key references catalogue.courses(id), provider_id uuid not null, url text, score numeric, runner_up numeric,
  basis text, status text not null, bound_at timestamptz not null default now(),
  read_status text, read_at timestamptz, http_status int, fetched_via text, identity_basis text, evidence_id uuid,
  candidates jsonb, leased_until timestamptz, read_attempts int not null default 0, next_read_at timestamptz);
create index if not exists coverage_course_pages_read on pipeline.coverage_course_pages(status, read_status, next_read_at);
create table if not exists pipeline.coverage_vendor_usage(
  id bigserial primary key, acquisition_provider_id uuid not null, units numeric not null, purpose text not null,
  provider_id uuid, url text, at timestamptz not null default now());
alter table pipeline.coverage_provider_discovery enable row level security;
alter table pipeline.coverage_provider_urls enable row level security;
alter table pipeline.coverage_course_pages enable row level security;
alter table pipeline.coverage_vendor_usage enable row level security;
revoke all on pipeline.coverage_provider_discovery, pipeline.coverage_provider_urls, pipeline.coverage_course_pages, pipeline.coverage_vendor_usage from public, anon, authenticated;

-- Seed: every Australian provider with an active course; those without a website are recorded as such.
insert into pipeline.coverage_provider_discovery(provider_id, website, status)
select p.id, nullif(btrim(p.website),''), case when nullif(btrim(p.website),'') is null then 'no_website' else 'pending' end
  from catalogue.providers p join ref.countries k on k.id=p.country_id
 where k.iso_alpha2='AU' and exists(select 1 from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active')
on conflict (provider_id) do nothing;

-- Budget guard counts sweep usage too (checksum-guarded patch of the monthly Firecrawl guard).
do $patch$
declare v_def text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid='security.layer2_provider_budget_status(uuid,numeric)'::regprocedure)<>'36722a43045cd3ac44b31fddb7708c57' then
    raise exception 'security.layer2_provider_budget_status changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('security.layer2_provider_budget_status(uuid,numeric)'::regprocedure);
  v_old:=$o$started_at<date_trunc('month',now())+interval '1 month';$o$;
  v_new:=$n$started_at<date_trunc('month',now())+interval '1 month'; v_used:=v_used+coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.acquisition_provider_id=p_provider_id and u.at>=date_trunc('month',now()) and u.at<date_trunc('month',now())+interval '1 month'),0);$n$;
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'budget anchor not found exactly once'; end if;
  execute replace(v_def,v_old,v_new);
end $patch$;

create or replace function public.svc_coverage_firecrawl()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public','pipeline','security' as $f$
declare v_id uuid;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select id into v_id from pipeline.layer2_acquisition_providers where provider_key='firecrawl' and enabled;
  if v_id is null then return jsonb_build_object('enabled',false); end if;
  return public.layer2_provider_runtime_config(v_id);
end $f$;
revoke all on function public.svc_coverage_firecrawl() from public, anon, authenticated;
grant execute on function public.svc_coverage_firecrawl() to service_role;

create or replace function public.svc_coverage_usage(p_units numeric, p_purpose text, p_provider_id uuid, p_url text)
returns void language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id,units,purpose,provider_id,url)
  select id, p_units, p_purpose, p_provider_id, left(p_url,500) from pipeline.layer2_acquisition_providers where provider_key='firecrawl';
end $f$;
revoke all on function public.svc_coverage_usage(numeric,text,uuid,text) from public, anon, authenticated;
grant execute on function public.svc_coverage_usage(numeric,text,uuid,text) to service_role;

-- Stage 1 queue: largest providers first; a lease stops two runs taking the same provider.
create or replace function public.svc_coverage_discovery_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.coverage_provider_discovery d
     where (d.status='pending' or (d.status in ('mapped','failed') and d.next_due_at<=now())) and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
     order by (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc
     limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',provider_id,'website',website)),'[]'::jsonb) into v from upd;
  return v;
end $f$;
revoke all on function public.svc_coverage_discovery_next(int) from public, anon, authenticated;
grant execute on function public.svc_coverage_discovery_next(int) to service_role;

-- Words of a page's last address segment (the slug) and of its title before the site name; generic words dropped.
create or replace function security.coverage_text_tokens(p text) returns text[] language sql immutable as $f$
  select coalesce(array_agg(distinct t),'{}') from unnest(regexp_split_to_array(lower(coalesce(p,'')),'[^a-z0-9]+')) t
   where length(t)>1 and t not in ('of','and','in','the','with','for','www','html','htm','php','aspx','au','edu','com','study','course','courses',
     'program','programs','programme','international','students','student','detail','details','index','overview','home')
$f$;
create or replace function security.coverage_slug(p_url text) returns text language sql immutable as $f$
  select coalesce((regexp_match(regexp_replace(regexp_replace(p_url,'[?#].*$',''),'/+$',''),'/([^/]+)$'))[1],'')
$f$;

create or replace function public.svc_coverage_discovery_record(p_provider_id uuid, p_status text, p_method text, p_url_count int, p_urls jsonb, p_error text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v_n int:=0;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.coverage_provider_urls(provider_id,url,title,tokens,title_tokens,source)
  select p_provider_id, left(e->>'url',1000), left(e->>'title',300), security.coverage_text_tokens(security.coverage_slug(e->>'url')),
         security.coverage_text_tokens(regexp_replace(coalesce(e->>'title',''),'\s[|–—]\s.*$','')), coalesce(p_method,'map')
    from jsonb_array_elements(coalesce(p_urls,'[]'::jsonb)) e where coalesce(e->>'url','')~'^https?://'
  on conflict (provider_id,url) do update set title=coalesce(excluded.title,pipeline.coverage_provider_urls.title), tokens=excluded.tokens, title_tokens=excluded.title_tokens, last_seen_at=now();
  get diagnostics v_n=row_count;
  update pipeline.coverage_provider_discovery set status=p_status, method=p_method, url_count=p_url_count, kept_count=v_n, last_error=left(p_error,500),
         leased_until=null, mapped_at=case when p_status='mapped' then now() else mapped_at end,
         next_due_at=case when p_status='mapped' then now()+interval '30 days' when p_status='failed' then now()+interval '6 hours' else null end, updated_at=now()
   where provider_id=p_provider_id;
  if p_status='mapped' then perform security.coverage_bind_v1(p_provider_id); end if;
  return jsonb_build_object('kept',v_n);
end $f$;
revoke all on function public.svc_coverage_discovery_record(uuid,text,text,int,jsonb,text) from public, anon, authenticated;
grant execute on function public.svc_coverage_discovery_record(uuid,text,text,int,jsonb,text) to service_role;

-- Stage 2: bind courses to pages of their own provider. A page is bound when the CRICOS course code is in its
-- address or title, or when the words of its last address segment or its title match the course title closely
-- (two-sided overlap >= 0.8, so extra words lower the score) and lead the next page by at least 0.1. Close but unclear matches are kept as 'ambiguous'; a bound page is never overwritten by a weaker one.
create or replace function security.coverage_bind_v1(p_provider_id uuid)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','security' as $f$
declare v_bound int; v_amb int;
begin
  with c as (
    select co.id course_id, lower(co.course_code) code, security.coverage_text_tokens(co.canonical_title) tok
      from catalogue.courses co where co.provider_id=p_provider_id and co.lifecycle_status='active'),
  s as (
    select c.course_id, u.url,
           greatest(
             2.0*(select count(*) from unnest(c.tok) t where t=any(u.tokens))/nullif(cardinality(c.tok)+cardinality(u.tokens),0),
             2.0*(select count(*) from unnest(c.tok) t where t=any(u.title_tokens))/nullif(cardinality(c.tok)+cardinality(u.title_tokens),0)) sc0,
           c.code is not null and length(c.code)>=6 and (position(c.code in lower(u.url))>0 or position(c.code in lower(coalesce(u.title,'')))>0) by_code
      from c join pipeline.coverage_provider_urls u on u.provider_id=p_provider_id and (u.tokens && c.tok or u.title_tokens && c.tok
           or (c.code is not null and length(c.code)>=6 and (position(c.code in lower(u.url))>0 or position(c.code in lower(coalesce(u.title,'')))>0)))),
  s2 as (select course_id, url, case when by_code then 1.0 else coalesce(sc0,0) end sc, by_code from s),
  r as (select course_id, url, sc, by_code, row_number() over (partition by course_id order by sc desc, length(url)) rk,
               lead(sc) over (partition by course_id order by sc desc, length(url)) nxt from s2),
  best as (select course_id, url, sc, coalesce(nxt,0) nxt, by_code from r where rk=1 and sc>=0.6)
  insert into pipeline.coverage_course_pages(course_id,provider_id,url,score,runner_up,basis,status,bound_at,next_read_at)
  select course_id, p_provider_id, url, round(sc,3), round(nxt,3),
         case when by_code then 'cricos_code' else 'title_match' end,
         case when by_code or (sc>=0.8 and sc-nxt>=0.1) then 'bound' else 'ambiguous' end, now(), now()
    from best
  on conflict (course_id) do update set url=excluded.url, score=excluded.score, runner_up=excluded.runner_up, basis=excluded.basis,
         status=excluded.status, bound_at=now(), read_status=case when pipeline.coverage_course_pages.url is distinct from excluded.url then null else pipeline.coverage_course_pages.read_status end,
         next_read_at=case when pipeline.coverage_course_pages.url is distinct from excluded.url then now() else pipeline.coverage_course_pages.next_read_at end
   where not (pipeline.coverage_course_pages.status='bound' and excluded.status<>'bound');
  select count(*) filter (where status='bound'), count(*) filter (where status='ambiguous') into v_bound, v_amb from pipeline.coverage_course_pages where provider_id=p_provider_id;
  return jsonb_build_object('bound',v_bound,'ambiguous',v_amb);
end $f$;
revoke all on function security.coverage_bind_v1(uuid) from public, anon, authenticated;

-- Stage 3 queue: bound pages due for reading, spread across providers (at most 3 per provider per call).
create or replace function public.svc_coverage_read_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with due as (
    select p.course_id, p.provider_id, row_number() over (partition by p.provider_id order by p.next_read_at) rk
      from pipeline.coverage_course_pages p
     where p.status='bound' and coalesce(p.next_read_at,now())<=now() and coalesce(p.leased_until,'-infinity')<now() and p.read_attempts<3),
  pick as (select course_id from due where rk<=3 order by rk, random() limit greatest(1,least(coalesce(p_limit,20),60))),
  upd as (update pipeline.coverage_course_pages p set leased_until=now()+interval '10 minutes', read_attempts=p.read_attempts+1
            from pick where p.course_id=pick.course_id returning p.course_id, p.provider_id, p.url)
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'provider_id',u.provider_id,'url',u.url,'title',c.canonical_title,'code',c.course_code)),'[]'::jsonb)
    into v from upd u join catalogue.courses c on c.id=u.course_id;
  return v;
end $f$;
revoke all on function public.svc_coverage_read_next(int) from public, anon, authenticated;
grant execute on function public.svc_coverage_read_next(int) to service_role;

-- One sweep source per provider holds the page evidence (created on first use).
create or replace function security.coverage_sweep_source(p_provider_id uuid) returns uuid
language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline' as $f$
declare v uuid;
begin
  select id into v from pipeline.sources where source_type='provider_course_page_sweep' and provider_id=p_provider_id limit 1;
  if v is null then
    insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
    select 'provider_course_page_sweep', s.system_id, p.id, p.country_id, p.website,
           coalesce(p.display_name,p.canonical_name)||' course pages (coverage sweep)', 80, 'active',
           jsonb_build_object('facts',jsonb_build_array('official_course_url','international_fee','english_requirement','intake'),'decision','CF-247 complete coverage','admission','not admitted: candidates only')
      from catalogue.providers p cross join lateral (select system_id from pipeline.sources where source_type='provider_course_page' limit 1) s
     where p.id=p_provider_id returning id into v;
  end if;
  return v;
end $f$;
revoke all on function security.coverage_sweep_source(uuid) from public, anon, authenticated;

create or replace function public.svc_coverage_read_record(p_course_id uuid, p_read_status text, p_http_status int, p_fetched_via text,
  p_identity_basis text, p_storage_path text, p_sha256 text, p_candidates jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public','pipeline','security' as $f$
declare v_row pipeline.coverage_course_pages%rowtype; v_ev uuid; v_src uuid;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select * into v_row from pipeline.coverage_course_pages where course_id=p_course_id;
  if v_row.course_id is null then raise exception 'course page not bound'; end if;
  if p_storage_path is not null and p_sha256 ~ '^[0-9a-f]{64}$' then
    v_src:=security.coverage_sweep_source(v_row.provider_id);
    select id into v_ev from pipeline.evidence_artifacts where source_id=v_src and content_hash=p_sha256 and source_url=v_row.url limit 1;
    if v_ev is null then
      v_ev:=public.svc_coursefacts_register_evidence(v_src, v_row.url, p_storage_path, p_sha256, 'text/html',
        jsonb_build_object('layer',2,'kind','provider_course_page','worker','coverage-sweep','course_id',p_course_id,'identity_basis',p_identity_basis,'fetched_via',p_fetched_via,'gzip',true));
    end if;
  end if;
  update pipeline.coverage_course_pages set read_status=p_read_status, read_at=now(), http_status=p_http_status, fetched_via=p_fetched_via,
         identity_basis=p_identity_basis, evidence_id=coalesce(v_ev,evidence_id), candidates=p_candidates, leased_until=null,
         next_read_at=case when p_read_status in ('read','identity_mismatch') then now()+interval '90 days' else now()+interval '6 hours' end,
         status=case when p_read_status='identity_mismatch' then 'mismatch' else status end
   where course_id=p_course_id;
  return jsonb_build_object('evidence_id',v_ev);
end $f$;
revoke all on function public.svc_coverage_read_record(uuid,text,int,text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_coverage_read_record(uuid,text,int,text,text,text,text,jsonb) to service_role;
