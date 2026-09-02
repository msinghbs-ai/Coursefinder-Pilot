begin;
CREATE OR REPLACE FUNCTION public.svc_ranking_ingest_apply(p_system_code text, p_edition_year integer, p_source_url text, p_methodology_url text, p_source_artifact_id uuid, p_source_fingerprint text, p_source_revision text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking', 'catalogue', 'ref', 'pipeline', 'public'
AS $function$
declare
 v_system_id uuid; v_edition_id uuid; v_mapped integer:=0; v_unmapped integer:=0; v_equiv_fanout integer:=0;
 v_row jsonb; v_pub_id uuid; v_provider_id uuid; v_country text; v_name text;
 v_rank_display text; v_rank_exact integer; v_rank_low integer; v_rank_high integer;
 v_score numeric; v_score_display text; v_score_low numeric; v_score_high numeric; v_status text;
 v_observation_id uuid; v_alias_type text; v_candidate_ids uuid[]; v_equiv_ids uuid[]; v_pid uuid; v_indicator record;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service role required' using errcode='42501'; end if;
 if jsonb_typeof(coalesce(p_rows,'[]'::jsonb))<>'array' then raise exception 'rows must be array' using errcode='22023'; end if;
 select id into v_system_id from ranking.systems where code=p_system_code and active;
 if v_system_id is null then raise exception 'unsupported ranking system' using errcode='22023'; end if;
 v_alias_type:=p_system_code||'_publisher_name';

 insert into ranking.editions(system_id,edition_year,methodology_url,source_url,source_artifact_id,retrieved_at,source_fingerprint,source_revision,access_status,licensing_note,status)
 values(v_system_id,p_edition_year,nullif(p_methodology_url,''),p_source_url,p_source_artifact_id,now(),p_source_fingerprint,coalesce(nullif(p_source_revision,''),'initial'),'licensed_upload','Authorised publisher artifact registered through governed Layer 1 Evidence flow','accepted')
 on conflict(system_id,edition_year,source_revision) do update set methodology_url=excluded.methodology_url,source_url=excluded.source_url,source_artifact_id=excluded.source_artifact_id,retrieved_at=excluded.retrieved_at,source_fingerprint=excluded.source_fingerprint,access_status='licensed_upload',status='accepted',updated_at=now()
 returning id into v_edition_id;

 for v_row in select value from jsonb_array_elements(p_rows) loop
  v_name:=nullif(btrim(v_row->>'institution_name'),''); if v_name is null then continue; end if;
  v_country:=nullif(btrim(v_row->>'country_text'),'');
  v_rank_display:=nullif(btrim(v_row->>'rank_display'),'');
  v_rank_exact:=nullif(v_row->>'rank_exact','')::integer; v_rank_low:=nullif(v_row->>'rank_low','')::integer; v_rank_high:=nullif(v_row->>'rank_high','')::integer;
  v_score:=nullif(v_row->>'overall_score','')::numeric; v_score_display:=nullif(btrim(v_row->>'overall_score_display'),'');
  v_score_low:=nullif(v_row->>'overall_score_low','')::numeric; v_score_high:=nullif(v_row->>'overall_score_high','')::numeric;
  v_status:=coalesce(nullif(v_row->>'rank_status',''),'unknown');

  select id into v_pub_id from ranking.publisher_institutions where system_id=v_system_id and lower(institution_name)=lower(v_name) and lower(coalesce(country_text,''))=lower(coalesce(v_country,'')) limit 1;
  if v_pub_id is null then
   insert into ranking.publisher_institutions(system_id,publisher_institution_id,profile_url,institution_name,country_text,location_text,first_seen_edition,last_seen_edition)
   values(v_system_id,nullif(v_row->>'publisher_institution_id',''),nullif(v_row->>'profile_url',''),v_name,v_country,nullif(v_row->>'location_text',''),p_edition_year,p_edition_year)
   returning id into v_pub_id;
  else
   update ranking.publisher_institutions set publisher_institution_id=coalesce(publisher_institution_id,nullif(v_row->>'publisher_institution_id','')),profile_url=coalesce(profile_url,nullif(v_row->>'profile_url','')),first_seen_edition=least(coalesce(first_seen_edition,p_edition_year),p_edition_year),last_seen_edition=greatest(coalesce(last_seen_edition,p_edition_year),p_edition_year),updated_at=now() where id=v_pub_id;
  end if;

  v_provider_id:=null; v_equiv_ids:=null;
  select pm.provider_id into v_provider_id from ranking.provider_mappings pm where pm.publisher_institution_id=v_pub_id and pm.status='accepted' and pm.valid_to is null order by pm.valid_from desc limit 1;

  if v_provider_id is null then
   select array_agg(distinct pa.provider_id order by pa.provider_id) into v_candidate_ids
   from catalogue.provider_aliases pa join catalogue.providers p on p.id=pa.provider_id left join ref.countries c on c.id=p.country_id
   where lower(pa.alias)=lower(v_name) and (pa.alias_type=v_alias_type or pa.alias_type='ranking_publisher_name' or pa.alias_type like '%_wur_publisher_name') and pa.valid_to is null
     and (v_country is null or lower(c.name)=lower(v_country) or lower(c.iso_alpha2::text)=lower(v_country) or lower(c.iso_alpha3::text)=lower(v_country));
   if coalesce(array_length(v_candidate_ids,1),0)=1 then v_provider_id:=v_candidate_ids[1]; end if;
  end if;

  if v_provider_id is null then
   select array_agg(p.id order by p.id) into v_candidate_ids
   from catalogue.providers p left join ref.countries c on c.id=p.country_id
   where lower(regexp_replace(coalesce(p.display_name,p.canonical_name),'[^a-z0-9]+','','g'))=
         lower(regexp_replace(v_name,'[^a-z0-9]+','','g'))
     and (v_country is null or lower(c.name)=lower(v_country) or lower(c.iso_alpha2::text)=lower(v_country) or lower(c.iso_alpha3::text)=lower(v_country));
   if coalesce(array_length(v_candidate_ids,1),0)>=1 then
     v_provider_id:=v_candidate_ids[1];
     v_equiv_ids:=v_candidate_ids;
   end if;
  end if;

  if v_provider_id is not null and v_equiv_ids is null then
    v_equiv_ids:=public.svc_statistical_equivalent_provider_ids(v_provider_id);
  end if;

  if v_provider_id is not null and not exists(select 1 from ranking.provider_mappings pm where pm.publisher_institution_id=v_pub_id and pm.provider_id=v_provider_id and pm.status='accepted' and pm.valid_to is null) then
   insert into ranking.provider_mappings(publisher_institution_id,provider_id,mapping_method,confidence,status,evidence_artifact_id,reviewed_at,note)
   values(v_pub_id,v_provider_id,
     case when coalesce(array_length(v_equiv_ids,1),0)>1 then 'exact_equivalent_provider_fanout'
          when exists(select 1 from catalogue.provider_aliases pa where pa.provider_id=v_provider_id and lower(pa.alias)=lower(v_name) and (pa.alias_type=v_alias_type or pa.alias_type='ranking_publisher_name' or pa.alias_type like '%_wur_publisher_name') and pa.valid_to is null) then 'accepted_alias_country'
          else 'exact_canonical_name_country' end,
     1.0,'accepted',p_source_artifact_id,now(),
     case when coalesce(array_length(v_equiv_ids,1),0)>1 then 'Deterministic statistical-equivalence exception: exact provider name and/or identifier duplicates fan out; no identity merge performed.'
          else 'Deterministic unique Provider reconciliation during governed ranking ingestion' end);
  end if;

  insert into ranking.observations(edition_id,publisher_institution_id,provider_id,rank_display,rank_exact,rank_low,rank_high,is_tied,rank_status,overall_score,overall_score_display,overall_score_low,overall_score_high,source_row_ordinal,source_row_payload,evidence_artifact_id)
  values(v_edition_id,v_pub_id,v_provider_id,v_rank_display,v_rank_exact,v_rank_low,v_rank_high,coalesce((v_row->>'is_tied')::boolean,false),v_status,v_score,v_score_display,v_score_low,v_score_high,nullif(v_row->>'source_row_ordinal','')::integer,v_row,p_source_artifact_id)
  on conflict(edition_id,publisher_institution_id) do update set provider_id=excluded.provider_id,rank_display=excluded.rank_display,rank_exact=excluded.rank_exact,rank_low=excluded.rank_low,rank_high=excluded.rank_high,is_tied=excluded.is_tied,rank_status=excluded.rank_status,overall_score=excluded.overall_score,overall_score_display=excluded.overall_score_display,overall_score_low=excluded.overall_score_low,overall_score_high=excluded.overall_score_high,source_row_ordinal=excluded.source_row_ordinal,source_row_payload=excluded.source_row_payload,evidence_artifact_id=excluded.evidence_artifact_id
  returning id into v_observation_id;

  delete from ranking.observation_provider_links where observation_id=v_observation_id;
  if v_provider_id is not null then
    foreach v_pid in array coalesce(v_equiv_ids,array[v_provider_id]::uuid[]) loop
      insert into ranking.observation_provider_links(observation_id,provider_id,link_method,is_primary)
      values(v_observation_id,v_pid,case when v_pid=v_provider_id then 'primary_exact' else 'equivalent_exact_name_or_identifier' end,v_pid=v_provider_id)
      on conflict do nothing;
    end loop;
    v_equiv_fanout:=v_equiv_fanout+greatest(coalesce(array_length(v_equiv_ids,1),1)-1,0);
  end if;

  if jsonb_typeof(v_row->'indicators')='object' then
   for v_indicator in select key,value from jsonb_each(v_row->'indicators') loop
    insert into ranking.indicator_observations(observation_id,indicator_code,indicator_label,value_numeric,value_display,unit,methodology_version)
    values(v_observation_id,v_indicator.key,nullif(v_indicator.value->>'label',''),
      case when jsonb_typeof(v_indicator.value)='object' then nullif(v_indicator.value->>'value_numeric','')::numeric else nullif(trim(both '"' from v_indicator.value::text),'')::numeric end,
      case when jsonb_typeof(v_indicator.value)='object' then nullif(v_indicator.value->>'value_display','') else trim(both '"' from v_indicator.value::text) end,
      case when jsonb_typeof(v_indicator.value)='object' then nullif(v_indicator.value->>'unit','') else null end,
      case when jsonb_typeof(v_indicator.value)='object' then nullif(v_indicator.value->>'methodology_version','') else null end)
    on conflict(observation_id,indicator_code) do update set indicator_label=excluded.indicator_label,value_numeric=excluded.value_numeric,value_display=excluded.value_display,unit=excluded.unit,methodology_version=excluded.methodology_version;
   end loop;
  end if;

  if v_provider_id is null then v_unmapped:=v_unmapped+1; else v_mapped:=v_mapped+1; end if;
 end loop;

 update ranking.manual_imports
 set status=case when v_unmapped>0 then 'needs_review' else 'applied' end,
     parse_summary=jsonb_build_object('rows',jsonb_array_length(p_rows),'mapped',v_mapped,'unmapped',v_unmapped,'equivalent_provider_fanout_links',v_equiv_fanout),
     updated_at=now()
 where evidence_artifact_id=p_source_artifact_id;

 return jsonb_build_object('edition_id',v_edition_id,'rows',jsonb_array_length(p_rows),'mapped',v_mapped,'unmapped',v_unmapped,'equivalent_provider_fanout_links',v_equiv_fanout,
  'status',case when v_unmapped>0 then 'needs_review' else 'applied' end);
end $function$
;
create or replace function public.svc_ranking_reconciliation_preview_system(p_rows jsonb,p_country_code text,p_system_code text)
returns jsonb language sql security definer set search_path to 'pg_catalog','catalogue','ref' as $$
with input as (
 select row_number() over ()::int ordinal,nullif(btrim(x->>'institution_name'),'') institution_name,
  nullif(btrim(x->>'country_text'),'') country_text,nullif(btrim(x->>'rank_display'),'') rank_display
 from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) x
), target as (
 select * from input where institution_name is not null and lower(coalesce(country_text,'')) in (
  select lower(name) from ref.countries where iso_alpha2=p_country_code
  union all select lower(iso_alpha2::text) from ref.countries where iso_alpha2=p_country_code
  union all select lower(iso_alpha3::text) from ref.countries where iso_alpha2=p_country_code
 )
), matches as (
 select t.*,
  array(select distinct pa.provider_id from catalogue.provider_aliases pa
   join catalogue.providers p on p.id=pa.provider_id join ref.countries c on c.id=p.country_id
   where c.iso_alpha2=p_country_code and lower(pa.alias)=lower(t.institution_name) and pa.valid_to is null
    and (pa.alias_type='ranking_publisher_name' or pa.alias_type like '%_wur_publisher_name') order by pa.provider_id) alias_ids,
  array(select p.id from catalogue.providers p join ref.countries c on c.id=p.country_id
   where c.iso_alpha2=p_country_code and lower(regexp_replace(coalesce(p.display_name,p.canonical_name),'[^a-z0-9]+','','g'))=
   lower(regexp_replace(t.institution_name,'[^a-z0-9]+','','g')) order by p.id) exact_ids
 from target t
), classified as (
 select *,
  case when coalesce(array_length(alias_ids,1),0)=1 then alias_ids
       when coalesce(array_length(alias_ids,1),0)=0 then exact_ids else alias_ids end chosen_ids,
  case when coalesce(array_length(alias_ids,1),0)=1 then 'accepted_alias_country'
       when coalesce(array_length(alias_ids,1),0)>1 and coalesce(array_length(exact_ids,1),0)>0 then 'equivalent_exact_name_fanout'
       when coalesce(array_length(alias_ids,1),0)>1 then 'alias_ambiguous'
       when coalesce(array_length(exact_ids,1),0)=1 then 'exact_canonical_name_country'
       when coalesce(array_length(exact_ids,1),0)>1 then 'equivalent_exact_name_fanout'
       else 'unmatched' end mapping_method
 from matches
)
select jsonb_build_object(
 'system_code',p_system_code,'country_code',p_country_code,'country_rows',(select count(*) from target),
 'alias_unique',(select count(*) from classified where mapping_method='accepted_alias_country'),
 'exact_unique',(select count(*) from classified where mapping_method='exact_canonical_name_country'),
 'equivalent_fanout',(select count(*) from classified where mapping_method='equivalent_exact_name_fanout'),
 'mapped_unique',(select count(*) from classified where mapping_method in ('accepted_alias_country','exact_canonical_name_country','equivalent_exact_name_fanout')),
 'alias_ambiguous',(select count(*) from classified where mapping_method='alias_ambiguous'),
 'exact_ambiguous',0,
 'unmatched',(select count(*) from classified where mapping_method='unmatched'),
 'mapped_rate',round(coalesce((select count(*)::numeric from classified where mapping_method in ('accepted_alias_country','exact_canonical_name_country','equivalent_exact_name_fanout'))/nullif((select count(*) from target),0),0)*100,2),
 'unmatched_sample',coalesce((select jsonb_agg(jsonb_build_object('institution_name',institution_name,'rank_display',rank_display) order by ordinal) from (select * from classified where mapping_method='unmatched' order by ordinal limit 50)s),'[]'::jsonb),
 'ambiguous_sample',coalesce((select jsonb_agg(jsonb_build_object('institution_name',institution_name,'rank_display',rank_display,'mapping_method',mapping_method,'candidate_provider_ids',to_jsonb(chosen_ids)) order by ordinal) from (select * from classified where mapping_method='alias_ambiguous' order by ordinal limit 50)s),'[]'::jsonb),
 'equivalent_sample',coalesce((select jsonb_agg(jsonb_build_object('institution_name',institution_name,'rank_display',rank_display,'mapping_method',mapping_method,'provider_ids',to_jsonb(exact_ids)) order by ordinal) from (select * from classified where mapping_method='equivalent_exact_name_fanout' order by ordinal limit 50)s),'[]'::jsonb)
) $$;
commit;
