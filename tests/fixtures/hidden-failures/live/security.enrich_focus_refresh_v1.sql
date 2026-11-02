CREATE OR REPLACE FUNCTION security.enrich_focus_refresh_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_top int := security.pipeline_num_v1('enrich.focus_top_n', 50)::int; v_n int;
begin
  insert into pipeline.enrich_focus_providers(provider_id, rank, gaps, in_focus, set_at)
  select g.provider_id, g.rk, g.gaps, g.rk <= v_top, now()
    from (select d.provider_id, (count(*) filter (where not d.has_english) + count(*) filter (where not d.has_intake))::int gaps,
                 row_number() over (order by count(*) filter (where not d.has_english) + count(*) filter (where not d.has_intake) desc, d.provider_id)::int rk
            from search.course_documents d
           where d.country_code = 'AU' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)
           group by d.provider_id) g
  on conflict (provider_id) do update set rank = excluded.rank, gaps = excluded.gaps, in_focus = excluded.in_focus, set_at = now();
  update pipeline.enrich_focus_providers f set in_focus = false, set_at = now()
   where f.in_focus and f.set_at < now();  -- providers not ranked in this refresh
  select count(*) into v_n from pipeline.enrich_focus_providers where in_focus;
  return v_n;
end $function$
