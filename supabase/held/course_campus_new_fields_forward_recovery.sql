-- HELD forward recovery for migration 20261118073000_cf247_course_study_load_empty_reason_campus_primary_locality.sql. NOT a migration: run by hand only on the Platform Admin's decision.
-- Restores the four edited bodies byte for byte (each md5-guarded; applying it twice changes nothing). After it, courses_page ignores the Study load and Empty reason
-- filters and its items no longer carry the two fields, and campuses_page is read by security.admin_campus_page_fast again (no Primary or Locality).
-- security.admin_campuses_page_v2, the two indexes, the two registry rows and the ILEP note stay; nothing is dropped.
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this recovery restores from (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;


select pg_temp.edit_all('security.admin_course_page_fast(jsonb)', 'a5cd4a729e6ee42fb256982fb151728b', '19d7dde7292e5707a7e1bc110c6106d8',
  array[$n0$    and nullif(p_args->>'description','') is null
    and nullif(p_args->>'study_load','') is null
    and nullif(p_args->>'empty_reason','') is null
$n0$],
  array[$o0$    and nullif(p_args->>'description','') is null
$o0$]);

select pg_temp.edit_all('security.admin_course_page_fast_base(jsonb)', 'e0cddf8a334e13e1617709ea6ab25a53', '3b6e10e4212aebc944abaac866e50f7a',
  array[$n0$  -- 18 Nov 2026 (Platform Admin, Course catalogue): the Study load and Empty reason filters are applied in the bounded path below only
  if v_sort in ('fee','completeness') and nullif(p_args->>'description','') is null and nullif(p_args->>'study_load','') is null and nullif(p_args->>'empty_reason','') is null then$n0$,
        $n1$ end)))  -- fixed: the filter's own windows, as the Freshness filter's
      -- 18 Nov 2026 (Platform Admin, Course catalogue): Study load filter (none: not held) and Empty reason filter (any: a reason is recorded; none: no reason)
      and (nullif(p_args->>'study_load','') is null
        or (p_args->>'study_load'='none' and c.study_load is null)
        or c.study_load=p_args->>'study_load')
      and (nullif(p_args->>'empty_reason','') is null
        or (p_args->>'empty_reason'='any' and c.empty_reason_code is not null)
        or (p_args->>'empty_reason'='none' and c.empty_reason_code is null)
        or c.empty_reason_code=p_args->>'empty_reason')
$n1$],
  array[$o0$  if v_sort in ('fee','completeness') and nullif(p_args->>'description','') is null then$o0$,
        $o1$ end)))  -- fixed: the filter's own windows, as the Freshness filter's
$o1$]);

select pg_temp.edit_all('security.course_list_with_extras_v1(jsonb)', 'db3b7ed0edb7a7ad268be448cde863d9', '2a0b931a4f8f3673f2dac447ee25dd2e',
  array[$n0$left join lateral (select jsonb_build_object('study_load', c.study_load, 'empty_reason_code', c.empty_reason_code, 'description_text', c.description,$n0$],
  array[$o0$left join lateral (select jsonb_build_object('description_text', c.description,$o0$]);

select pg_temp.edit_all('public.admin_read(text,jsonb)', 'b6570ab86cecb6c4d2f843538c56bd1f', 'f4df73816871c19c233d0708f9d44ef6',
  array[$n0$ if p_operation='campuses_page' then return security.admin_campuses_page_v2(p_args); end if; -- 18 Nov 2026: Primary and Locality on the Campuses list$n0$],
  array[$o0$ if p_operation='campuses_page' then return security.admin_campus_page_fast(p_args); end if;$o0$]);

-- the earlier Campuses read is in use again
update pipeline.component_register set status = 'active', replaced_by = null, retire_after = null, note = 'restored by the held forward recovery of 20261118073000', updated_at = now()
 where kind = 'function' and name = 'security.admin_campus_page_fast(jsonb)' and status = 'retiring';
