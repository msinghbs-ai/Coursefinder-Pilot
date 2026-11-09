-- SELECT-only (no writes): run once after migration 20261109200000 is applied, from a Supabase SQL session (project fxcwkweaxjtknorudmwp) as the
-- database owner. It signs in as a Platform Admin for the length of the statement only (set_config is local to it), then compares, for 64 requests spread
-- over every sort v2 accepts, both directions, three offsets, and the filters v2 accepts, what security.admin_providers_page_v2 answers with what
-- security.admin_providers_page_v3 answers: the same rows in the same order (full item JSON, after the four item keys v3 adds are removed), the same
-- total, limit, offset, sort and direction. The block always ends in an exception that carries the result, so nothing persists.
-- Expected: "mismatches":0 and every row "same":true. Replace the user id below with any current Platform Admin's auth.users id if needed.
do $eq$
declare
  v_a jsonb; v_r2 jsonb; v_r3 jsonb; v_same boolean; v_out jsonb := '[]'; v_bad int := 0; v_dir text;
  v_sorts text[] := array['provider','country','currency','subdivision','city','type','courses','adapter','verified'];
  v_s text; v_off int; v_args jsonb[] := '{}';
begin
  perform set_config('request.jwt.claim.sub', 'c2882478-8a06-4cb5-9856-407d29e2fadb', true);
  perform set_config('request.jwt.claims', '{"sub":"c2882478-8a06-4cb5-9856-407d29e2fadb","role":"authenticated"}', true);
  if security.current_role_rank() < 6 then raise exception 'sign in as a Platform Admin: rank is %', security.current_role_rank(); end if;
  foreach v_s in array v_sorts loop
    foreach v_dir in array array['asc','desc'] loop
      foreach v_off in array array[0, 50, 3000] loop
        v_args := v_args || jsonb_build_object('lifecycle_status','active','sort',v_s,'direction',v_dir,'offset',v_off,'limit',50);
      end loop;
    end loop;
  end loop;
  v_args := v_args || '{}'::jsonb || '{"limit":200,"offset":3000}'::jsonb
    || '{"lifecycle_status":"archived"}'::jsonb || '{"lifecycle_status":"active","query":"univ"}'::jsonb
    || '{"lifecycle_status":"active","country_code":"AU","publication_status":"published"}'::jsonb
    || '{"lifecycle_status":"active","country_code":"NZ"}'::jsonb || '{"lifecycle_status":"active","adapter":"any"}'::jsonb
    || '{"lifecycle_status":"active","adapter":"admitting","sort":"adapter"}'::jsonb || '{"lifecycle_status":"active","university_group":"go8"}'::jsonb
    || '{"sort":"courses","direction":"desc","limit":25,"offset":100}'::jsonb;
  foreach v_a in array v_args loop
    v_r2 := security.admin_providers_page_v2(
      least(greatest(coalesce(nullif(v_a->>'limit','')::int,50),1),200), greatest(coalesce(nullif(v_a->>'offset','')::int,0),0), nullif(v_a->>'query',''),
      nullif(v_a->>'country_code',''), nullif(v_a->>'subdivision_code',''), nullif(v_a->>'lifecycle_status',''), nullif(v_a->>'publication_status',''),
      coalesce(nullif(v_a->>'sort',''),'provider'), case when lower(coalesce(v_a->>'direction','asc'))='desc' then 'desc' else 'asc' end,
      nullif(v_a->>'university_group',''), nullif(v_a->>'adapter',''));
    v_r3 := security.admin_providers_page_v3(v_a);
    v_same := (v_r2->'items') = (select coalesce(jsonb_agg(i - 'registration' - 'scholarships' - 'entry_coverage' - 'pdesc' order by o), '[]'::jsonb) from jsonb_array_elements(v_r3->'items') with ordinality t(i,o))
      and v_r2->>'total' = v_r3->>'total' and v_r2->>'sort' = v_r3->>'sort' and v_r2->>'direction' = v_r3->>'direction' and v_r2->>'limit' = v_r3->>'limit' and v_r2->>'offset' = v_r3->>'offset';
    if not v_same then v_bad := v_bad + 1; end if;
    v_out := v_out || jsonb_build_object('args', v_a, 'same', v_same, 'total', v_r3->>'total', 'n', jsonb_array_length(v_r3->'items'));
  end loop;
  raise exception 'EQUIVALENCE {"requests":%, "mismatches":%, "rows":%}', jsonb_array_length(v_out), v_bad, v_out::text;
end $eq$;
