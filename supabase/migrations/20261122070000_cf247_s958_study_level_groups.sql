-- CF-247 s958 (session S1-API-Frontend-Delivery, Lane 1 item 2, third part; India team review of 20 Nov 2026, REQ-100): the Study level filter
-- shows every level in one list, grouped as Pathway, Vocational, Undergraduate, Postgraduate and Other, with no technical codes and no
-- second page, on Courses and on Entry requirements.
--
-- The groups are data, not code: new table ref.study_level_groups holds the group of each study level (by ref.study_levels.code), its
-- display name and order. A level with no row reads as Other. A person changes a group by changing a row.
-- security.admin_catalogue_filter_page, kind level: up to 100 levels in one page (other kinds keep 10), each with its group (group,
--   group_order), the group name as the line under the level (was the code), ordered by group and then level.
-- public.admin_aer, action options: levels gain group and group_order.
-- Admin reads only; G3 checked before and after. Live on deploy. $0. G1: no job. G2: no operational value (100 is the size of a
-- reference list, marked fixed).
-- Parity: live head 20261122050000 read 22 Nov 2026 00:30 AEDT; this file is numbered strictly above it and above s957 (20261122060000).
-- Replaces: the Study level list paged ten at a time with codes.
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

create table if not exists ref.study_level_groups (
  level_code text primary key references ref.study_levels(code),
  group_code text not null check (group_code ~ '^[a-z_]+$'),
  group_name text not null,
  group_order integer not null,
  updated_at timestamptz not null default now(),
  reason text not null
);
comment on table ref.study_level_groups is 'CF-247 s958 (REQ-100): the group each study level is shown under in the Study level filters (Courses, Entry requirements): Pathway, Vocational, Undergraduate, Postgraduate, Other. A level with no row reads as Other. Changed by row, with a reason.';
alter table ref.study_level_groups enable row level security;
revoke all on table ref.study_level_groups from anon, authenticated;

insert into ref.study_level_groups (level_code, group_code, group_name, group_order, reason)
select l.code, g.group_code, g.group_name, g.group_order, 'CF-247 s958 (REQ-100, India team review 20 Nov 2026): first grouping'
  from ref.study_levels l
  join (values
    ('primary_school_studies', 'pathway', 'Pathway', 10), ('junior_secondary_studies', 'pathway', 'Pathway', 10),
    ('senior_secondary_certificate', 'pathway', 'Pathway', 10), ('foundation', 'pathway', 'Pathway', 10),
    ('certificate', 'vocational', 'Vocational', 20), ('certificate_i', 'vocational', 'Vocational', 20), ('certificate_ii', 'vocational', 'Vocational', 20),
    ('certificate_iii', 'vocational', 'Vocational', 20), ('certificate_iv', 'vocational', 'Vocational', 20), ('vocational_short_course', 'vocational', 'Vocational', 20),
    ('diploma', 'vocational', 'Vocational', 20), ('advanced_diploma', 'vocational', 'Vocational', 20),
    ('associate_degree', 'undergraduate', 'Undergraduate', 30), ('bachelor', 'undergraduate', 'Undergraduate', 30), ('bachelor_honours', 'undergraduate', 'Undergraduate', 30),
    ('graduate_certificate', 'postgraduate', 'Postgraduate', 40), ('graduate_diploma', 'postgraduate', 'Postgraduate', 40), ('masters', 'postgraduate', 'Postgraduate', 40),
    ('masters_coursework', 'postgraduate', 'Postgraduate', 40), ('masters_research', 'postgraduate', 'Postgraduate', 40), ('masters_extended', 'postgraduate', 'Postgraduate', 40),
    ('professional_degree', 'postgraduate', 'Postgraduate', 40), ('doctorate', 'postgraduate', 'Postgraduate', 40),
    ('non_aqf_award', 'other', 'Other', 90)
  ) g(level_code, group_code, group_name, group_order) on g.level_code = l.code
on conflict (level_code) do nothing;

create or replace function pg_temp.edit_re(p_sig text, p_before text, p_edits text[][]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g')) <> 1 then
      raise exception '%: edit % must apply exactly once (found %)', p_sig, i, (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g'));
    end if;
    v_def := regexp_replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  return p_sig || ': applied ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $f$;

select pg_temp.edit_re('security.admin_catalogue_filter_page(jsonb)', '244538bdc97f9e889de2f4fa8fdec716', array[
  array[$o$v_limit integer:=least\(greatest\(coalesce\(nullif\(p_args->>'limit',''\)::integer,10\),1\),10\);$o$,
        $n$v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),case when lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''))='level' then 100 else 10 end);$n$],
  array[$o$select distinct sl\.code value,sl\.name label,sl\.code meta,sl\.sort_order\s+from catalogue\.courses c\s+join ref\.study_levels sl on sl\.id=c\.study_level_id$o$,
        $n$select distinct sl.code value,sl.name label,coalesce(g.group_name,'Other') meta,sl.sort_order,coalesce(g.group_order,90) group_order
      from catalogue.courses c
      join ref.study_levels sl on sl.id=c.study_level_id
      left join ref.study_level_groups g on g.level_code=sl.code$n$],
  array[$o$page as \(select value,label,meta from q order by sort_order,lower\(label\),value limit v_limit offset v_offset\)\s+select coalesce\(\(select jsonb_agg\(jsonb_build_object\('value',value,'label',label,'meta',meta\)\) from page\),'\[\]'::jsonb\)$o$,
        $n$page as (select value,label,meta,group_order,sort_order from q order by group_order,sort_order,lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'group',meta,'group_order',group_order) order by group_order,sort_order,lower(label),value) from page),'[]'::jsonb)$n$]]);

select pg_temp.edit_re('public.admin_aer(text,jsonb)', '8aba9ae6ad9b8f21fd1996ae9d93aa82', array[
  array[$o$'levels', \(select coalesce\(jsonb_agg\(jsonb_build_object\('code', l0\.short_code, 'name', l0\.name\) order by l0\.sort_order\), '\[\]'::jsonb\) from ref\.study_levels l0\)$o$,
        $n$'levels', (select coalesce(jsonb_agg(jsonb_build_object('code', l0.short_code, 'name', l0.name, 'group', coalesce(g0.group_name, 'Other'), 'group_order', coalesce(g0.group_order, 90)) order by coalesce(g0.group_order, 90), l0.sort_order), '[]'::jsonb) from ref.study_levels l0 left join ref.study_level_groups g0 on g0.level_code = l0.code)$n$]]);

do $c$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if (select count(*) from ref.study_level_groups) < 24 then raise exception 'post-check: study level groups not filled'; end if;
  if position('ref.study_level_groups' in pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the level filter has no groups'; end if;
  if position('ref.study_level_groups' in pg_get_functiondef('public.admin_aer(text,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the entry levels have no groups'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
