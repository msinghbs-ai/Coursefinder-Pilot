CREATE OR REPLACE FUNCTION public.svc_ranking_reconciliation_preview(p_rows jsonb, p_country_code text DEFAULT 'AU'::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref'
AS $function$
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
  select t.*,
    array(
      select distinct pa.provider_id
      from catalogue.provider_aliases pa
      join catalogue.providers p on p.id=pa.provider_id
      join ref.countries c on c.id=p.country_id
      where c.iso_alpha2=p_country_code
        and lower(pa.alias)=lower(t.institution_name)
        and pa.alias_type='qs_wur_publisher_name'
        and pa.valid_to is null
      order by pa.provider_id
    ) alias_ids,
    array(
      select p.id
      from catalogue.providers p join ref.countries c on c.id=p.country_id
      where c.iso_alpha2=p_country_code
        and lower(coalesce(p.display_name,p.canonical_name))=lower(t.institution_name)
      order by p.id
    ) exact_ids
  from target t
),
classified as (
 select *,
   coalesce(array_length(alias_ids,1),0) alias_count,
   coalesce(array_length(exact_ids,1),0) exact_count,
   case when coalesce(array_length(alias_ids,1),0)=1 then alias_ids
        when coalesce(array_length(alias_ids,1),0)=0 then exact_ids
        else alias_ids end chosen_ids,
   case when coalesce(array_length(alias_ids,1),0)=1 then 'accepted_alias_country'
        when coalesce(array_length(alias_ids,1),0)>1 then 'alias_ambiguous'
        when coalesce(array_length(exact_ids,1),0)=1 then 'exact_canonical_name_country'
        when coalesce(array_length(exact_ids,1),0)>1 then 'exact_ambiguous'
        else 'unmatched' end mapping_method
 from matches
)
select jsonb_build_object(
  'country_code',p_country_code,
  'source_rows',jsonb_array_length(coalesce(p_rows,'[]'::jsonb)),
  'country_rows',(select count(*) from target),
  'alias_unique',(select count(*) from classified where mapping_method='accepted_alias_country'),
  'exact_unique',(select count(*) from classified where mapping_method='exact_canonical_name_country'),
  'mapped_unique',(select count(*) from classified where mapping_method in ('accepted_alias_country','exact_canonical_name_country')),
  'alias_ambiguous',(select count(*) from classified where mapping_method='alias_ambiguous'),
  'exact_ambiguous',(select count(*) from classified where mapping_method='exact_ambiguous'),
  'unmatched',(select count(*) from classified where mapping_method='unmatched'),
  'mapped_rate',round(coalesce((select count(*)::numeric from classified where mapping_method in ('accepted_alias_country','exact_canonical_name_country'))/nullif((select count(*) from target),0),0)*100,2),
  'unmatched_sample',coalesce((select jsonb_agg(jsonb_build_object('institution_name',institution_name,'rank_display',rank_display) order by ordinal) from (select * from classified where mapping_method='unmatched' order by ordinal limit 25) s),'[]'::jsonb),
  'ambiguous_sample',coalesce((select jsonb_agg(jsonb_build_object('institution_name',institution_name,'rank_display',rank_display,'mapping_method',mapping_method,'candidate_provider_ids',to_jsonb(chosen_ids)) order by ordinal) from (select * from classified where mapping_method in ('alias_ambiguous','exact_ambiguous') order by ordinal limit 25) s),'[]'::jsonb)
)
$function$
