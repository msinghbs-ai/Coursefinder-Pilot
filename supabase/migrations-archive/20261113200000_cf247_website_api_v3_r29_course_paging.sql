-- CF-247 Website API v3, build brief WP-1.3: R29 scholarship linked-course paging (REQ-73). Decision 277: v3 only; v2 is only read.
-- v2 `scholarship` returns the first 200 linked courses and linked_courses_truncated (live 12 Nov 2026: 176 of 1,053 linked scholarships pass 200,
-- the largest 563; about 22,300 links not reachable). In v3:
--   scholarship  takes optional courses_page (1 or more) and courses_page_size (1–200). With neither, linked_courses is the v2 list (first 200,
--                same order) and linked_courses_truncated the v2 value. With either, linked_courses is that page, in the same order (course
--                title, then course id), and linked_courses_truncated says whether more come after it.
--                Always added: linked_courses_total (the linked courses the API can list), linked_courses_page, linked_courses_page_size.
--   Out of range or not whole numbers: 400 INVALID_INPUT. Everything else in the answer is unchanged (R24 status from WP-1.2 kept).
-- Replaces: public.website_v3_scholarship(text) (same name and signature; md5-guarded; now the paged form with no paging).
-- Retires: nothing.

do $guard$
begin
  if md5(pg_get_functiondef('public.website_v3_scholarship(text)'::regprocedure)) <> '9c7aa0d870747b27330d6594e6ba4dd8' then
    raise exception 'live public.website_v3_scholarship(text) differs from the WP-1.2 definition this change replaces (md5 %)',
      md5(pg_get_functiondef('public.website_v3_scholarship(text)'::regprocedure));
  end if;
end $guard$;

create or replace function public.website_v3_scholarship(p_scholarship_id text, p_courses jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_scholarship(p_scholarship_id); v_id uuid; v_total int; v_page int; v_size int; v_paged boolean;
        c jsonb := coalesce(p_courses, '{}'::jsonb);
begin
  v_paged := nullif(c->>'page', '') is not null or nullif(c->>'page_size', '') is not null;
  if v_paged then
    if coalesce(c->>'page', '1') !~ '^[0-9]+$' or coalesce(c->>'page_size', '200') !~ '^[0-9]+$' then
      raise exception 'INVALID_INPUT: courses_page and courses_page_size must be whole numbers' using errcode = '22023';
    end if;
    v_page := coalesce((c->>'page')::int, 1);
    v_size := coalesce((c->>'page_size')::int, 200);  -- fixed: API contract, no paging asked = the v2 first 200 (build brief WP-1.3)
    if v_page < 1 or v_size < 1 or v_size > 200 then  -- fixed: API contract range 1–200 (build brief WP-1.3)
      raise exception 'INVALID_INPUT: courses_page must be 1 or more and courses_page_size 1-200' using errcode = '22023';
    end if;
  else
    v_page := 1; v_size := 200;  -- fixed: API contract, the v2 first page
  end if;
  if jsonb_typeof(v->'item') is distinct from 'object' then return v; end if;  -- NOT_FOUND and errors pass through as v2
  select s.id into v_id from scholarship.scholarships s where s.stable_key = btrim(p_scholarship_id);
  select count(*) into v_total from scholarship.course_mappings m join search.course_documents d on d.course_id = m.course_id
   where m.scholarship_id = v_id and m.mapping_state = 'mapped';
  v := jsonb_set(v, '{item}', public.website_v3_scholarship_item(v->'item'));
  if v_paged then
    v := jsonb_set(v, '{item}', (v->'item') || jsonb_build_object(
      'linked_courses', coalesce((select jsonb_agg(x.j order by x.t, x.k) from (
          select d.course_title t, d.course_stable_key k, jsonb_build_object('course_id', d.course_stable_key, 'course_code', d.course_code, 'title', d.course_title,
                   'saving_per_year', fc.scholarship_saving_amount, 'saving_currency', fc.currency_code, 'saving_basis', fc.fee_basis) j
            from scholarship.course_mappings m
            join search.course_documents d on d.course_id = m.course_id
            left join lateral (select f.scholarship_saving_amount, f.currency_code, f.fee_basis from scholarship.course_financial_calculations f
                                where f.scholarship_id = v_id and f.course_id = d.course_id and f.calculation_status = 'calculated'
                                order by f.fee_year desc nulls last limit 1) fc on true
           where m.scholarship_id = v_id and m.mapping_state = 'mapped'
           order by d.course_title, d.course_stable_key
           offset (v_page - 1) * v_size limit v_size) x), '[]'::jsonb),
      'linked_courses_truncated', v_page * v_size < v_total));
  end if;
  return jsonb_set(v, '{item}', (v->'item') || jsonb_build_object('linked_courses_total', v_total, 'linked_courses_page', v_page, 'linked_courses_page_size', v_size));
end $$;

create or replace function public.website_v3_scholarship(p_scholarship_id text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.website_v3_scholarship(p_scholarship_id, null::jsonb)
$$;

comment on function public.website_v3_scholarship(text, jsonb) is
  'Website API v3 (Decision 277): website_v2_scholarship with nationality_eligibility_status (R24) and linked-course paging (R29: courses_page, courses_page_size; linked_courses_total).';
comment on function public.website_v3_scholarship(text) is 'Website API v3 (Decision 277): the scholarship with no paging asked (first 200 linked courses, as v2), R24 and linked_courses_total.';
revoke all on function public.website_v3_scholarship(text, jsonb) from public, anon, authenticated;
grant execute on function public.website_v3_scholarship(text, jsonb) to service_role;

do $post$ begin
  if public.website_v3_scholarship('none', '{"page": 2}'::jsonb)->'error'->>'code' is distinct from 'NOT_FOUND' then raise exception 'post-check: a missing scholarship must answer NOT_FOUND'; end if;
  begin
    perform public.website_v3_scholarship('none', '{"page_size": 201}'::jsonb);
    raise exception 'post-check: a page size over 200 must be refused';
  exception when sqlstate '22023' then null;
  end;
end $post$;
