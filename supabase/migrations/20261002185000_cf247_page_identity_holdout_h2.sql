-- CF-247 (2 Oct 2026). AI page-identity check: second frozen holdout "pid-h2" for qualification. pid-h1 (migration
-- 20261002184900) was read while the deterministic checks were tuned (contract v1.0.1), so it is now the development set;
-- pid-h2 is built the same way from universities that pid-h1 did not use (no university appears in both sets) and has not been looked at. Pass rule unchanged: at least 95% of right
-- pairings accepted and zero wrong pairings accepted. Nothing is switched on.
do $h$
declare v_n int;
begin
  if exists (select 1 from pipeline.coverage_identity_sets where gold_set = 'pid-h2') then return; end if;
  -- right pairings: one page per university, the first 120 universities not used in pid-h1, in the same hashed order
  insert into pipeline.coverage_identity_cases(gold_set, case_no, course_id, page_course_id, evidence_id, storage_path, gold, provider_id)
  with pages as (
    select p.course_id, p.provider_id, p.evidence_id, e.storage_path, md5(p.course_id::text || 'pid-h1') r
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id = p.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id = p.course_id and co.lifecycle_status = 'active'
     where p.read_status = 'read' and p.identity_basis = 'cricos_code'
       and lower(regexp_replace(coalesce(p.candidates->>'h1', ''), '[^a-zA-Z0-9]+', ' ', 'g')) <> lower(regexp_replace(co.canonical_title, '[^a-zA-Z0-9]+', ' ', 'g'))),
  prov as (select provider_id, row_number() over (order by md5(provider_id::text || 'pid-h1')) k from (select distinct provider_id from pages) x
             where provider_id not in (select provider_id from pipeline.coverage_identity_cases where gold_set = 'pid-h1')),
  one as (select distinct on (pg.provider_id) pg.* from pages pg order by pg.provider_id, pg.r)
  select 'pid-h2', row_number() over (order by v.k), o.course_id, o.course_id, o.evidence_id, o.storage_path, true, o.provider_id
    from prov v join one o using (provider_id) where v.k <= 120;
  -- wrong pairings: the next universities not used in pid-h1; the page's own course replaced by the most similar other course there
  insert into pipeline.coverage_identity_cases(gold_set, case_no, course_id, page_course_id, evidence_id, storage_path, gold, provider_id)
  with pages as (
    select p.course_id, p.provider_id, p.evidence_id, e.storage_path, co.canonical_title t, security.coverage_text_tokens(co.canonical_title) tok, md5(p.course_id::text || 'pid-h1') r
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id = p.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id = p.course_id and co.lifecycle_status = 'active'
     where p.read_status = 'read' and p.identity_basis = 'cricos_code'
       and lower(regexp_replace(coalesce(p.candidates->>'h1', ''), '[^a-zA-Z0-9]+', ' ', 'g')) <> lower(regexp_replace(co.canonical_title, '[^a-zA-Z0-9]+', ' ', 'g'))),
  prov as (select provider_id, row_number() over (order by md5(provider_id::text || 'pid-h1')) k from (select distinct provider_id from pages) x
             where provider_id not in (select provider_id from pipeline.coverage_identity_cases where gold_set = 'pid-h1')),
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
  select 'pid-h2', 120 + row_number() over (order by k), other_id, course_id, evidence_id, storage_path, false, provider_id from pairs;
  select count(*) into v_n from pipeline.coverage_identity_cases where gold_set = 'pid-h2';
  insert into pipeline.coverage_identity_sets(gold_set, cases, frozen_digest)
  select 'pid-h2', v_n, md5(string_agg(case_no || ':' || course_id || ':' || evidence_id || ':' || gold, ',' order by case_no))
    from pipeline.coverage_identity_cases where gold_set = 'pid-h2';
end $h$;
