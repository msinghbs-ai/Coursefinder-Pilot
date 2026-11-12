-- CF-247 Course catalogue: the course description shown and filtered (Platform Admin 12 Nov 2026 20:50: "add ui Filter to see the updated course description and instead of
-- populated it should fill in the value as wrapped text").
--
--   * Every Course catalogue page item now carries description_text (the catalogue description itself) and description_updated_at (when the description reader
--     wrote the text held now: the latest filled description reading whose text is the current description; null for a description set or edited by hand),
--     added in security.course_list_with_extras_v1 for every path of courses_page.
--   * courses_page takes a new optional argument, description: populated (a description is held), missing (none), updated_24h or updated_7d (the description held
--     now was written by the reader in the last day or week; live 12 Nov 2026: 189 ms for the week window over 18,503 description readings). security.admin_course_page_fast
--     sends a page with it to the filtered path; security.admin_course_page_fast_base applies it, and sorts by fee and completeness there too (QA of #1081;
--     security.course_completeness_v1, new, is the completeness score the list shows); the fee and completeness sorts keep their legacy path only without it.
--
-- Live definitions this change edits (pg_proc.prosrc md5, read 12 Nov 2026), before -> after (the migration stops, and applies nothing, if a live body is neither):
--   security.admin_course_page_fast(jsonb)  c4d2eb53d5ffb893217f3e408dd01fd0 -> 19d7dde7292e5707a7e1bc110c6106d8
--   security.admin_course_page_fast_base(jsonb)  56bcf191ba8dd6da8f84c170c7c3c5f9 -> 3b6e10e4212aebc944abaac866e50f7a
--   security.course_list_with_extras_v1(jsonb)  91e88067d293f13cf99a95fa2faa8f93 -> 2a0b931a4f8f3673f2dac447ee25dd2e
-- Replaces: the three bodies above, in place (md5-guarded edits)
-- Retires: nothing

-- the completeness score the Course catalogue shows (the same six signals as courses_page's completeness_score_v2), for its completeness sort
create or replace function security.course_completeness_v1(p_course uuid) returns numeric language sql stable set search_path = '' as $f$
  select round(((exists(select 1 from catalogue.course_registrations r where r.course_id = c.id))::int
          + (c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id = c.id))::int
          + (exists(select 1 from catalogue.course_fees cf where cf.course_id = c.id and coalesce(cf.status, 'active') = 'active'))::int
          + (exists(select 1 from catalogue.course_intakes ci where ci.course_id = c.id and coalesce(ci.status, 'active') = 'active'))::int
          + (exists(select 1 from catalogue.course_english_requirements er where er.course_id = c.id and coalesce(er.status, 'active') = 'active'))::int
          + (c.description is not null and length(trim(c.description)) > 0)::int) * 100.0 / 6.0, 2)
    from catalogue.courses c where c.id = p_course
$f$;
comment on function security.course_completeness_v1(uuid) is 'CF-247 Course catalogue (20261112210000): a course''s completeness score as courses_page shows it, for the completeness sort of the filtered path';
revoke all on function security.course_completeness_v1(uuid) from public;

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

select pg_temp.edit_all('security.admin_course_page_fast_base(jsonb)', '56bcf191ba8dd6da8f84c170c7c3c5f9', '3b6e10e4212aebc944abaac866e50f7a',
  array[$o0$  if v_sort in ('fee','completeness') then$o0$,
        $o1$        or (p_args->>'applicant'='unknown' and c.open_to_international is null))
$o1$,
        $o2$      case when v_sort='city' and v_dir='asc' then$o2$],
  array[$n0$  -- 12 Nov 2026 (Platform Admin, Course catalogue): the Course description filter is applied in the bounded path below only
  if v_sort in ('fee','completeness') and nullif(p_args->>'description','') is null then$n0$,
        $n1$        or (p_args->>'applicant'='unknown' and c.open_to_international is null))
      -- 12 Nov 2026 (Platform Admin, Course catalogue): Course description filter: held or not, or written by the description reader in the last day or week
      and (nullif(p_args->>'description','') is null
        or (p_args->>'description'='populated' and nullif(btrim(c.description),'') is not null)
        or (p_args->>'description'='missing' and nullif(btrim(c.description),'') is null)
        or (p_args->>'description' in ('updated_24h','updated_7d') and nullif(btrim(c.description),'') is not null and exists (
          -- the reading must be the text held now: a description edited by hand after the reading is not counted as written by the reader
          select 1 from pipeline.field_enrich_items e where e.course_id=c.id and e.field='description' and e.state='filled' and btrim(e.value->>'text')=btrim(c.description)
             and e.updated_at>=now()-case when p_args->>'description'='updated_24h' then interval '1 day' else interval '7 days' end)))  -- fixed: the filter's own windows, as the Freshness filter's
$n1$,
        $n2$      -- 12 Nov 2026 (QA of #1081): with the Course description filter the fee and completeness sorts run here too
      case when v_sort='fee' and v_dir='asc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='tuition' and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active' order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc limit 1) end asc nulls last,
      case when v_sort='fee' and v_dir='desc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='tuition' and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active' order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc limit 1) end desc nulls last,
      case when v_sort='completeness' then security.course_completeness_v1(numbered.id) end * case when v_dir='desc' then -1 else 1 end asc nulls last,
      case when v_sort='city' and v_dir='asc' then$n2$]);

select pg_temp.edit_all('security.course_list_with_extras_v1(jsonb)', '91e88067d293f13cf99a95fa2faa8f93', '2a0b931a4f8f3673f2dac447ee25dd2e',
  array[$o0$jsonb_agg(it.v || coalesce(x.extras, '{}'::jsonb) order by it.o)$o0$,
        $o1$'')::uuid), '[]'::jsonb),$o1$],
  array[$n0$jsonb_agg(it.v || coalesce(x.extras, '{}'::jsonb) || coalesce(dsc.v, '{}'::jsonb) order by it.o)$n0$,
        $n1$'')::uuid
        -- 12 Nov 2026 (Platform Admin, Course catalogue): the description itself (shown as wrapped text) and when the description reader last wrote it
        left join lateral (select jsonb_build_object('description_text', c.description,
                                  'description_updated_at', (select e.updated_at from pipeline.field_enrich_items e where e.course_id = c.id and e.field = 'description' and e.state = 'filled'
                                                               and btrim(e.value ->> 'text') = btrim(c.description) order by e.updated_at desc limit 1)) v
                             from catalogue.courses c where c.id = nullif(coalesce(it.v ->> 'id', it.v ->> 'course_id'), '')::uuid) dsc on true), '[]'::jsonb),$n1$]);

