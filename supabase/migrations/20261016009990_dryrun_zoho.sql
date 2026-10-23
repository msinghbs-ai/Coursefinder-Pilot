-- CF-247 (23 Oct 2026). Platform Admin 12:52 (Courses list, University of Auckland diplomas): "Still no city or fees on these."
-- Found: five of the twelve diplomas hold an international fee (Languages NZ$42,236 for 2027; Arts, Global Studies, Health Sciences,
-- Music), but the Courses list shows only the CRICOS registered tuition column, which New Zealand and Canada never have; the list
-- has no city column; and these diplomas have no campus, because the catalogue pages give their locations only as a data label
-- (["City","South Auckland"]) that the AI campus reading did not take.
-- 1 The Courses list also gives each course's international fee (provider tuition: amount, currency and year) and its campus cities.
-- 2 Read with AI asks the AI again even when the same page copy did not state a field before (a person asked; the reader may have
--   improved: worker v0.42.2 reads a campus or duration given only as a data label).
-- Replaces: nothing (security.admin_course_page_fast_base and security.admin_course_page_unfiltered_fast edited in place, md5-guarded,
--   fields added only; security.enrich_fields_slice_v1 and public.admin_course_read_now edited in place, md5-guarded)
-- Retires: nothing
create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

do $do$
declare r record;
begin
  for r in select * from (values ('security.admin_course_page_fast_base(jsonb)', '12f21dca758c75f6ffbc06f94fa12382'),
                                 ('security.admin_course_page_unfiltered_fast(jsonb)', 'aaae93e378dcbd66c9536858c6b4dce8')) v(sig, m) loop
    perform pg_temp.edit_once(r.sig, r.m, array[
      array[E'    ) fee on true\n',
            E'    ) fee on true\n'
            || E'    -- 23 Oct 2026 (Platform Admin 12:52): the international fee a provider publishes, and the campus cities\n'
            || E'    left join lateral (select cf.amount, cf.currency_code, cf.fee_year from catalogue.course_fees cf where cf.course_id=pg.id and cf.fee_type=''provider_current_tuition''\n'
            || E'      and cf.audience=''international'' and cf.status=''active'' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) ifee on true\n'
            || E'    left join lateral (select string_agg(distinct ca.city, '', '') city_names from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id\n'
            || E'      where cc.course_id=pg.id and nullif(btrim(ca.city),'''') is not null) gcity on true\n'],
      array['fee.amount fee_amount,fee.currency_code::text fee_currency,',
            'fee.amount fee_amount,fee.currency_code::text fee_currency,ifee.amount intl_fee_amount,ifee.currency_code::text intl_fee_currency,ifee.fee_year intl_fee_year,gcity.city_names,']]);
  end loop;
end $do$;

select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', 'b9a93c769a13a59994db058f217032d9', array[
  array[$o$        if it.course_id is not null and v_ev is not null and exists ($o$,
        $n$        if it.course_id is not null and v_ev is not null and not coalesce((j.args->>'read_now')::boolean, false) and exists ($n$]]);
select pg_temp.edit_once('public.admin_course_read_now(uuid,text)', '4ce5f962df7c7653857c716656a0707c', array[
  array[$o$jsonb_build_object('countries', '[]'::jsonb, 'provider_ids', jsonb_build_array(v_c.provider_id), 'course_ids'$o$,
        $n$jsonb_build_object('read_now', true, 'countries', '[]'::jsonb, 'provider_ids', jsonb_build_array(v_c.provider_id), 'course_ids'$n$]]);

select 'course list: international fee and campus cities; Read with AI asks again' ok;
do $t$ declare r jsonb; begin
  perform set_config('request.jwt.claims', '{"sub":"63ba56cb-48d4-4169-98c2-7c4d1f72925b","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', true);
  r := security.admin_course_page_fast_base('{"search":"Diploma in Languages","limit":5}'::jsonb);
  raise exception 'DRYRUN OK %', jsonb_build_object('items', (select jsonb_agg(jsonb_build_object('t', x->>'canonical_title', 'f', x->'intl_fee_amount', 'y', x->'intl_fee_year', 'c', x->'city_names')) from jsonb_array_elements(r->'items') x)); end $t$;
