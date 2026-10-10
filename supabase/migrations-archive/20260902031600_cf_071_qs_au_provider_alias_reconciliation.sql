insert into catalogue.provider_aliases(provider_id,alias,alias_type,locale,source_id)
select v.provider_id,v.alias,v.alias_type,v.locale,v.source_id
from (values
('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2'::uuid,'The University of Melbourne','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('22657140-1cb0-4fa7-91df-90518ea8b35b'::uuid,'The University of New South Wales (UNSW Sydney)','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid,'Australian National University (ANU)','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('9d22a19e-c3f7-4012-b738-17bc0b481e7f'::uuid,'University of Technology Sydney','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('8e1adb6c-e069-43db-9584-bd054255e702'::uuid,'RMIT University','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('188103a5-1aba-4f99-bd3e-0416659086d3'::uuid,'Macquarie University (Sydney, Australia)','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid,'Deakin University','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('2c4f515c-c146-4e90-ba8a-294130aa1f40'::uuid,'Queensland University of Technology (QUT)','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('1822b40a-8b13-44dc-8c37-106ae31bb447'::uuid,'The University of Newcastle, Australia (UON)','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('719403bc-6957-4d21-af69-2b3b102df578'::uuid,'University of Tasmania','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6'::uuid,'Central Queensland University (CQUniversity Australia)','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('739948f6-6338-4ee9-8d0c-a8c8e953c29d'::uuid,'Bond University','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('fa0e0d13-838a-42ff-b6a3-9cea84bd80b2'::uuid,'University of New England Australia','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid),
('dce54a01-39c1-4bdf-877d-b67da3afc81e'::uuid,'The University of Notre Dame, Australia','qs_wur_publisher_name','en-AU','c7c6a456-4aaa-4e1c-9586-2b51de7c30de'::uuid)
) as v(provider_id,alias,alias_type,locale,source_id)
where not exists (
 select 1 from catalogue.provider_aliases pa
 where pa.provider_id=v.provider_id and lower(pa.alias)=lower(v.alias)
   and coalesce(pa.alias_type,'')=coalesce(v.alias_type,'')
   and pa.valid_to is null
);

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
$$;
revoke all on function public.svc_ranking_reconciliation_preview(jsonb,text) from public,anon,authenticated;
grant execute on function public.svc_ranking_reconciliation_preview(jsonb,text) to service_role;
