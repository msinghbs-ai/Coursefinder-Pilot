-- CF-247 F-AER.01 follow-up to 20261111040000 / 20261111050000 (Integration Controller, 11 Nov 2026 00:1x AEDT): speed of the AER population.
-- Measured (production): security.aer_course_population_v1() took 4.3 s before the title rule (13,114 rows) and 15.7 s with it (15,165 rows), because the per-course rule
-- security.aer_title_identity_ok_v1 was evaluated once per bound course that the code bases do not admit. The population feeds the scheduled reader, aer_no_source_route_v1
-- and Data delivery (8 s API limit).
-- Change: security.aer_title_identity_courses_v1() (new, set-based, read only) answers the SAME rule for every course at once (the courses whose title-matched page passes);
-- the population uses it as one hashed set instead of one call per course (md5-guarded edit of the line added by 20261111040000). The per-course function stays for the
-- reader's record step and the machine check (one course at a time) and is the reference: a post-check compares the two on every course they consider.
-- Replaces: security.aer_course_population_v1 (same name; md5-guarded edit). Retires: nothing.

do $g$
begin
  if to_regprocedure('security.aer_title_identity_ok_v1(uuid)') is null then raise exception 'apply 20261111040000 first'; end if;
end $g$;

create or replace function security.aer_title_identity_courses_v1() returns table(course_id uuid)
language sql stable security definer set search_path to '' as $f$
  with s as (select security.pipeline_num_v1('aer.title_identity_on', 0) >= 1 on_,
                    coalesce(security.toolset_setting('pipeline', 'aer.eligible_countries'), '[]'::jsonb) cc,
                    coalesce(security.toolset_setting('pipeline', 'aer.title_identity_bases'), '[]'::jsonb) bases,
                    security.pipeline_num_v1('aer.title_identity_min_margin', 0.1) margin,
                    coalesce(security.l4_shared_hosts_v1(), '{}'::text[]) shared),
  b as (select distinct on (g.course_id) g.course_id, g.provider_id, g.url, g.score, g.runner_up, g.candidates, g.identity_basis
          from pipeline.coverage_course_pages g cross join s where s.on_ and g.status = 'bound' and s.bases ? coalesce(g.identity_basis, '')
         order by g.course_id, g.bound_at desc nulls last),
  c as (select b.*, x.canonical_title, l.code lvl, security.site_host_v1(b.url) host,
               coalesce(nullif(btrim(b.candidates->>'h1'), ''), nullif(btrim(split_part(coalesce(b.candidates->>'page_title', ''), ' | ', 1)), '')) h1
          from b join catalogue.courses x on x.id = b.course_id and x.lifecycle_status = 'active'
          join catalogue.providers p on p.id = x.provider_id left join ref.countries k on k.id = p.country_id
          join ref.study_levels l on l.id = x.study_level_id cross join s
         where s.cc ? coalesce(k.iso_alpha2, '')),
  h as (select pr.provider_id, security.provider_hosts_v1(pr.provider_id) hosts from (select distinct provider_id from c) pr),
  d as (select c.*, regexp_replace(lower(coalesce(c.canonical_title, '')), '[^a-z0-9]+', '', 'g') tn, regexp_replace(lower(coalesce(c.h1, '')), '[^a-z0-9]+', '', 'g') hn,
               case when c.lvl in ('bachelor', 'bachelor_honours') then '\mbachelor' when c.lvl like 'masters%' then '\mmaster'
                    when c.lvl = 'graduate_certificate' then '\mgraduate certificate' when c.lvl = 'graduate_diploma' then '\mgraduate diploma'
                    when c.lvl = 'advanced_diploma' then '\madvanced diploma' when c.lvl = 'diploma' then '\mdiploma' when c.lvl = 'associate_degree' then '\massociate degree'
                    when c.lvl = 'certificate_i' then '\mcertificate i\M' when c.lvl = 'certificate_ii' then '\mcertificate ii\M'
                    when c.lvl = 'certificate_iii' then '\mcertificate iii\M' when c.lvl = 'certificate_iv' then '\mcertificate iv\M'
                    when c.lvl = 'doctorate' then '\m(doctor|phd)' when c.lvl = 'foundation' then '\mfoundation' end kw -- fixed: the same credential words as security.aer_title_identity_ok_v1
          from c join h on h.provider_id = c.provider_id cross join s
         where c.host is not null and exists (select 1 from unnest(h.hosts) hh where c.host = hh or c.host like '%.' || hh)
           and not (c.host = any (s.shared))
           and (c.runner_up is null or coalesce(c.score, 0) - c.runner_up >= s.margin))
  select d.course_id from d
   where d.h1 is not null and length(d.tn) >= 6 -- fixed: as in security.aer_title_identity_ok_v1
     and (d.hn = d.tn or (right(d.hn, length(d.tn)) = d.tn and left(d.hn, length(d.hn) - length(d.tn)) ~ '^[a-z]{0,5}[0-9]{2,8}[a-z]{0,2}$')) -- fixed: as in security.aer_title_identity_ok_v1
     and d.kw is not null and lower(d.h1) ~ d.kw
     and not (d.lvl = 'diploma' and lower(d.h1) ~ '\m(graduate|advanced) diploma')
     and not exists (select 1 from pipeline.coverage_course_pages o where o.url = d.url and o.status = 'bound' and o.provider_id <> d.provider_id)
     and not exists (select 1 from pipeline.coverage_course_pages o join catalogue.courses oc on oc.id = o.course_id and oc.lifecycle_status = 'active'
                      where o.url = d.url and o.status = 'bound' and o.course_id <> d.course_id)
$f$;
comment on function security.aer_title_identity_courses_v1() is 'CF-247 F-AER.01 (read only, set-based): every course whose title-matched bound page passes the own-site title and study-level rule; the same rule as security.aer_title_identity_ok_v1, for the AER population.';
revoke all on function security.aer_title_identity_courses_v1() from public, anon, authenticated;

create or replace function pg_temp.edit_once(p_sig text, p_old text, p_new text) returns text language plpgsql as $e$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_cnt int;
begin
  v_cnt := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_cnt <> 1 then raise exception '%: the anchored text occurs % times', p_sig, v_cnt; end if;
  execute replace(v_def, p_old, p_new);
  return p_sig || ' -> ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $e$;

select pg_temp.edit_once('security.aer_course_population_v1(uuid)',
  $o$coalesce((security.aer_title_identity_ok_v1(c.id)->>'ok')::boolean, false)) -- 20261111040000$o$,
  $n$c.id in (select t.course_id from security.aer_title_identity_courses_v1() t)) -- 20261111040000 (set-based: 20261111060000)$n$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_title_identity_courses_v1', 'Layer 2', 'Set-based own-site title and level identity for the AER population', 'active', '{}', '20261111060000')
on conflict do nothing;

do $p$
declare v_a int; v_b int;
begin
  -- the two forms of the rule agree on every course the set form considers
  select count(*) into v_a from security.aer_title_identity_courses_v1();
  select count(*) into v_b from security.aer_title_identity_courses_v1() t where not coalesce((security.aer_title_identity_ok_v1(t.course_id)->>'ok')::boolean, false);
  if v_b > 0 then raise exception 'post-check: % of % courses pass the set rule but not the per-course rule', v_b, v_a; end if;
end $p$;
