create or replace function public.svc_ranking_reconciliation_preview(
  p_rows jsonb,
  p_country_code text default 'AU'
)
returns jsonb
language sql
security definer
set search_path='pg_catalog','catalogue','ref'
as $$
with input as (
  select row_number() over ()::int ordinal,
    nullif(btrim(x->>'institution_name'),'') institution_name,
    nullif(btrim(x->>'country_text'),'') country_text,
    nullif(btrim(x->>'rank_display'),'') rank_display,
    x
  from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) x
),
target as (
  select * from input
  where institution_name is not null
    and lower(coalesce(country_text,'')) in (
      select lower(name) from ref.countries where iso_alpha2=p_country_code
      union all select lower(iso_alpha2::text) from ref.countries where iso_alpha2=p_country_code
      union all select lower(iso_alpha3::text) from ref.countries where iso_alpha2=p_country_code
    )
),
matches as (
  select t.*, array(
    select p.id
    from catalogue.providers p join ref.countries c on c.id=p.country_id
    where c.iso_alpha2=p_country_code
      and lower(coalesce(p.display_name,p.canonical_name))=lower(t.institution_name)
    order by p.id
  ) exact_ids
  from target t
),
classified as (
  select *,coalesce(array_length(exact_ids,1),0) exact_count from matches
)
select jsonb_build_object(
  'country_code',p_country_code,
  'source_rows',jsonb_array_length(coalesce(p_rows,'[]'::jsonb)),
  'country_rows',(select count(*) from target),
  'exact_unique',(select count(*) from classified where exact_count=1),
  'exact_ambiguous',(select count(*) from classified where exact_count>1),
  'unmatched',(select count(*) from classified where exact_count=0),
  'exact_rate',round(coalesce((select count(*)::numeric from classified where exact_count=1)/nullif((select count(*) from target),0),0)*100,2),
  'unmatched_sample',coalesce((select jsonb_agg(jsonb_build_object('institution_name',institution_name,'rank_display',rank_display) order by ordinal) from (select * from classified where exact_count=0 order by ordinal limit 25) s),'[]'::jsonb),
  'ambiguous_sample',coalesce((select jsonb_agg(jsonb_build_object('institution_name',institution_name,'rank_display',rank_display,'candidate_provider_ids',to_jsonb(exact_ids)) order by ordinal) from (select * from classified where exact_count>1 order by ordinal limit 25) s),'[]'::jsonb)
)
$$;
revoke all on function public.svc_ranking_reconciliation_preview(jsonb,text) from public,anon,authenticated;
grant execute on function public.svc_ranking_reconciliation_preview(jsonb,text) to service_role;