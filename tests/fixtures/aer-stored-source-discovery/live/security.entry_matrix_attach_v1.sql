CREATE OR REPLACE FUNCTION security.entry_matrix_attach_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int := 0; v_max int := security.pipeline_num_v1('entry.attach_per_provider', 3)::int;
begin
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 then return 0; end if;
  insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
  select x.provider_id, x.url, x.title, x.rn, 'search'
    from (select s.provider_id, e->>'url' url, left(e->>'title', 200) title,
                 row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc, length(e->>'url')) rn
            from pipeline.provider_central_search s, jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
           where e->>'kind' = 'entry_requirements' and e->>'url' ~ '^https?://'
             and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
             and security.entry_matrix_enabled_v1(s.provider_id)) x
   where x.rn <= v_max
     and (select count(*) from pipeline.entry_matrix_sources m where m.provider_id = x.provider_id) < v_max
  on conflict (provider_id, url) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$
