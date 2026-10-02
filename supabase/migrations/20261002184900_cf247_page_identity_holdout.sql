-- CF-247 (2 Oct 2026). AI page-identity check (plan section 5, step 4): a candidate model that decides whether a stored
-- course page is the page for a given course when the deterministic identity rule cannot tell (no code on the page, a
-- heading that differs from the register title). It is QUALIFIED HERE ONLY; nothing is switched on. Switching it on is a
-- separate step for the Platform Admin.
-- Frozen holdout "pid-h1", gold taken from the course code printed on the page (objective, no hand reading):
--   right pairings (gold true):  a page that prints the course's CRICOS code, whose heading is not the register title,
--                                paired with that course; 120 cases, one per university;
--   wrong pairings (gold false): a page that prints its own course's CRICOS code, paired with the most similar OTHER
--                                course at the same university (shares title words, different title once brackets and
--                                "(International)" are removed); 120 cases from 120 other universities.
-- The model is shown the page with every CRICOS-style code masked, so it must decide from names and levels, as it will
-- on pages with no code. A wrong pairing whose own course code is printed on the page (one page for two courses) is
-- left out of the score by the runner. Pass rule: at least 95% of right pairings accepted and zero wrong pairings accepted.
create table if not exists pipeline.coverage_identity_cases (
  gold_set text not null,
  case_no int not null,
  course_id uuid not null,
  page_course_id uuid not null,
  evidence_id uuid not null,
  storage_path text not null,
  gold boolean not null,
  provider_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (gold_set, case_no)
);
alter table pipeline.coverage_identity_cases enable row level security;
revoke all on pipeline.coverage_identity_cases from public, anon, authenticated;

create table if not exists pipeline.coverage_identity_sets (
  gold_set text primary key,
  cases int not null,
  frozen_digest text not null,
  frozen_at timestamptz not null default now()
);
alter table pipeline.coverage_identity_sets enable row level security;
revoke all on pipeline.coverage_identity_sets from public, anon, authenticated;

create table if not exists pipeline.coverage_identity_results (
  id bigint generated always as identity primary key,
  run_label text not null,
  gold_set text not null,
  case_no int not null,
  model text not null,
  returned_model text,
  answer jsonb,
  checks jsonb,
  accepted boolean,
  gold boolean not null,
  cost_usd numeric,
  created_at timestamptz not null default now(),
  unique (run_label, case_no)
);
alter table pipeline.coverage_identity_results enable row level security;
revoke all on pipeline.coverage_identity_results from public, anon, authenticated;

do $h$
declare v_n int;
begin
  if exists (select 1 from pipeline.coverage_identity_sets where gold_set = 'pid-h1') then return; end if;
  -- right pairings: one page per university, the first 120 universities in a fixed hashed order
  insert into pipeline.coverage_identity_cases(gold_set, case_no, course_id, page_course_id, evidence_id, storage_path, gold, provider_id)
  with pages as (
    select p.course_id, p.provider_id, p.evidence_id, e.storage_path, md5(p.course_id::text || 'pid-h1') r
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id = p.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id = p.course_id and co.lifecycle_status = 'active'
     where p.read_status = 'read' and p.identity_basis = 'cricos_code'
       and lower(regexp_replace(coalesce(p.candidates->>'h1', ''), '[^a-zA-Z0-9]+', ' ', 'g')) <> lower(regexp_replace(co.canonical_title, '[^a-zA-Z0-9]+', ' ', 'g'))),
  prov as (select provider_id, row_number() over (order by md5(provider_id::text || 'pid-h1')) k from (select distinct provider_id from pages) x),
  one as (select distinct on (pg.provider_id) pg.* from pages pg order by pg.provider_id, pg.r)
  select 'pid-h1', row_number() over (order by v.k), o.course_id, o.course_id, o.evidence_id, o.storage_path, true, o.provider_id
    from prov v join one o using (provider_id) where v.k <= 120;
  -- wrong pairings: universities 121 onwards; the page's own course replaced by the most similar other course there
  insert into pipeline.coverage_identity_cases(gold_set, case_no, course_id, page_course_id, evidence_id, storage_path, gold, provider_id)
  with pages as (
    select p.course_id, p.provider_id, p.evidence_id, e.storage_path, co.canonical_title t, security.coverage_text_tokens(co.canonical_title) tok, md5(p.course_id::text || 'pid-h1') r
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id = p.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id = p.course_id and co.lifecycle_status = 'active'
     where p.read_status = 'read' and p.identity_basis = 'cricos_code'
       and lower(regexp_replace(coalesce(p.candidates->>'h1', ''), '[^a-zA-Z0-9]+', ' ', 'g')) <> lower(regexp_replace(co.canonical_title, '[^a-zA-Z0-9]+', ' ', 'g'))),
  prov as (select provider_id, row_number() over (order by md5(provider_id::text || 'pid-h1')) k from (select distinct provider_id from pages) x),
  one as (select distinct on (pg.provider_id) pg.* from pages pg order by pg.provider_id, pg.r),
  pairs as (
    select v.k, x.course_id, x.provider_id, x.evidence_id, x.storage_path, o.other_id
      from prov v join one x using (provider_id)
      cross join lateral (
        select co.id other_id from catalogue.courses co
         where co.provider_id = x.provider_id and co.lifecycle_status = 'active' and co.id <> x.course_id
           and regexp_replace(lower(regexp_replace(co.canonical_title, '\s*\([^)]*\)\s*', ' ', 'g')), '[^a-z0-9]+', ' ', 'g')
            <> regexp_replace(lower(regexp_replace(x.t, '\s*\([^)]*\)\s*', ' ', 'g')), '[^a-z0-9]+', ' ', 'g')
           and cardinality(array(select unnest(security.coverage_text_tokens(co.canonical_title)) intersect select unnest(x.tok))) >= 1
         order by cardinality(array(select unnest(security.coverage_text_tokens(co.canonical_title)) intersect select unnest(x.tok))) desc, co.id limit 1) o
     where v.k > 120 order by v.k limit 120)
  select 'pid-h1', 120 + row_number() over (order by k), other_id, course_id, evidence_id, storage_path, false, provider_id from pairs;
  select count(*) into v_n from pipeline.coverage_identity_cases where gold_set = 'pid-h1';
  insert into pipeline.coverage_identity_sets(gold_set, cases, frozen_digest)
  select 'pid-h1', v_n, md5(string_agg(case_no || ':' || course_id || ':' || evidence_id || ':' || gold, ',' order by case_no))
    from pipeline.coverage_identity_cases where gold_set = 'pid-h1';
end $h$;

create or replace function public.svc_coverage_identity_cases(p_gold_set text, p_offset int, p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if (select frozen_digest from pipeline.coverage_identity_sets where gold_set = p_gold_set) is distinct from
     (select md5(string_agg(case_no || ':' || course_id || ':' || evidence_id || ':' || gold, ',' order by case_no)) from pipeline.coverage_identity_cases where gold_set = p_gold_set)
  then raise exception 'holdout % is not frozen or has changed', p_gold_set; end if;
  select coalesce(jsonb_agg(jsonb_build_object('case_no', c.case_no, 'storage_path', c.storage_path, 'gold', c.gold, 'title', co.canonical_title, 'code', co.course_code,
           'level', (select sl.name from ref.study_levels sl where sl.id = co.study_level_id), 'provider', coalesce(pr.display_name, pr.canonical_name),
           'country', security.coverage_country(c.provider_id)) order by c.case_no), '[]'::jsonb)
    into v from (select * from pipeline.coverage_identity_cases where gold_set = p_gold_set order by case_no offset greatest(p_offset, 0) limit greatest(1, least(p_limit, 120))) c
    join catalogue.courses co on co.id = c.course_id join catalogue.providers pr on pr.id = c.provider_id;
  return v;
end $f$;
revoke all on function public.svc_coverage_identity_cases(text, int, int) from public, anon, authenticated;
grant execute on function public.svc_coverage_identity_cases(text, int, int) to service_role;

create or replace function public.svc_coverage_identity_result(p_run_label text, p_gold_set text, p_case_no int, p_model text, p_returned text, p_answer jsonb, p_checks jsonb, p_accepted boolean, p_cost numeric)
returns void language plpgsql security definer set search_path to 'pg_catalog', 'pipeline' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.coverage_identity_results(run_label, gold_set, case_no, model, returned_model, answer, checks, accepted, gold, cost_usd)
  select p_run_label, p_gold_set, p_case_no, p_model, p_returned, p_answer, p_checks, p_accepted, c.gold, p_cost
    from pipeline.coverage_identity_cases c where c.gold_set = p_gold_set and c.case_no = p_case_no
  on conflict (run_label, case_no) do update set returned_model = excluded.returned_model, answer = excluded.answer, checks = excluded.checks, accepted = excluded.accepted, cost_usd = excluded.cost_usd, created_at = now();
end $f$;
revoke all on function public.svc_coverage_identity_result(text, text, int, text, text, jsonb, jsonb, boolean, numeric) from public, anon, authenticated;
grant execute on function public.svc_coverage_identity_result(text, text, int, text, text, jsonb, jsonb, boolean, numeric) to service_role;
