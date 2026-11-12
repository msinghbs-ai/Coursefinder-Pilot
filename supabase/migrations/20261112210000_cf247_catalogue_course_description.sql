-- CF-247 Course catalogue: the course description shown and filtered (Platform Admin 12 Nov 2026 20:50: "add ui Filter to see the updated course description and instead of
-- populated it should fill in the value as wrapped text").
--
--   * Every Course catalogue page item now carries description_text (the catalogue description itself) and description_updated_at (when the description reader
--     last wrote it: the latest filled description reading), added in security.course_list_with_extras_v1 for every path of courses_page.
--   * courses_page takes a new optional argument, description: populated (a description is held), missing (none), updated_24h or updated_7d (a description the
--     reader wrote in the last day or week). security.admin_course_page_fast sends a page with it to the filtered path; security.admin_course_page_fast_base applies it
--     (the fee and completeness sorts keep their legacy path only without it).
--
-- Live definitions this change edits (pg_proc.prosrc md5, read 12 Nov 2026), before -> after (the migration stops, and applies nothing, if a live body is neither):
--   security.admin_course_page_fast(jsonb)  c4d2eb53d5ffb893217f3e408dd01fd0 -> 19d7dde7292e5707a7e1bc110c6106d8
--   security.admin_course_page_fast_base(jsonb)  56bcf191ba8dd6da8f84c170c7c3c5f9 -> 94b2f188b20a1a222c8016491e0e9d8c
--   security.course_list_with_extras_v1(jsonb)  91e88067d293f13cf99a95fa2faa8f93 -> 9f187a3c1d9d43a9e8df84b8a309e443
-- Replaces: the three bodies above, in place (md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped or deleted. No table, setting, job or consumer-API object is added or changed (G3: courses_page is the admin screen's read). Forward recovery
-- (restores the three bodies byte for byte): supabase/held/catalogue_course_description_forward_recovery.sql

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change replaces (body md5 %)', p_sig, md5(v_src); end if;
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

select pg_temp.edit_all('security.admin_course_page_fast(jsonb)', 'c4d2eb53d5ffb893217f3e408dd01fd0', '19d7dde7292e5707a7e1bc110c6106d8',
  array[$o0$    and nullif(p_args->>'applicant','') is null
$o0$],
  array[$n0$    and nullif(p_args->>'applicant','') is null
    and nullif(p_args->>'description','') is null
$n0$]);

select pg_temp.edit_all('security.admin_course_page_fast_base(jsonb)', '56bcf191ba8dd6da8f84c170c7c3c5f9', '94b2f188b20a1a222c8016491e0e9d8c',
  array[$o0$  if v_sort in ('fee','completeness') then$o0$,
        $o1$        or (p_args->>'applicant'='unknown' and c.open_to_international is null))
$o1$],
  array[$n0$  -- 12 Nov 2026 (Platform Admin, Course catalogue): the Course description filter is applied in the bounded path below only
  if v_sort in ('fee','completeness') and nullif(p_args->>'description','') is null then$n0$,
        $n1$        or (p_args->>'applicant'='unknown' and c.open_to_international is null))
      -- 12 Nov 2026 (Platform Admin, Course catalogue): Course description filter: held or not, or written by the description reader in the last day or week
      and (nullif(p_args->>'description','') is null
        or (p_args->>'description'='populated' and nullif(btrim(c.description),'') is not null)
        or (p_args->>'description'='missing' and nullif(btrim(c.description),'') is null)
        or (p_args->>'description' in ('updated_24h','updated_7d') and nullif(btrim(c.description),'') is not null and c.id in (
          select e.course_id from pipeline.field_enrich_items e where e.field='description' and e.state='filled'
             and e.updated_at>=now()-case when p_args->>'description'='updated_24h' then interval '1 day' else interval '7 days' end)))  -- fixed: the filter's own windows, as the Freshness filter's
$n1$]);

select pg_temp.edit_all('security.course_list_with_extras_v1(jsonb)', '91e88067d293f13cf99a95fa2faa8f93', '9f187a3c1d9d43a9e8df84b8a309e443',
  array[$o0$jsonb_agg(it.v || coalesce(x.extras, '{}'::jsonb) order by it.o)$o0$,
        $o1$'')::uuid), '[]'::jsonb),$o1$],
  array[$n0$jsonb_agg(it.v || coalesce(x.extras, '{}'::jsonb) || coalesce(dsc.v, '{}'::jsonb) order by it.o)$n0$,
        $n1$'')::uuid
        -- 12 Nov 2026 (Platform Admin, Course catalogue): the description itself (shown as wrapped text) and when the description reader last wrote it
        left join lateral (select jsonb_build_object('description_text', c.description,
                                  'description_updated_at', (select max(e.updated_at) from pipeline.field_enrich_items e where e.course_id = c.id and e.field = 'description' and e.state = 'filled')) v
                             from catalogue.courses c where c.id = nullif(coalesce(it.v ->> 'id', it.v ->> 'course_id'), '')::uuid) dsc on true), '[]'::jsonb),$n1$]);

