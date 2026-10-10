create or replace function scholarship.normalise_first_party_url(p_url text)
returns text language sql immutable as $$
  select nullif(lower(regexp_replace(split_part(replace(coalesce(p_url,''),'&amp;','&'),'#',1),'/+$','')),'');
$$;

create or replace function scholarship.normalise_title(p_text text)
returns text language sql immutable as $$
  select nullif(lower(regexp_replace(trim(coalesce(p_text,'')),'[^a-z0-9]+','','g')),'');
$$;

revoke all on function scholarship.normalise_first_party_url(text) from public,anon,authenticated;
revoke all on function scholarship.normalise_title(text) from public,anon,authenticated;
grant execute on function scholarship.normalise_first_party_url(text) to service_role;
grant execute on function scholarship.normalise_title(text) to service_role;

create or replace view pipeline.scholarship_verified_detail_reconciliation_candidates as
with base as (
  select sr.id as source_record_id,sr.source_id,src.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,
    c.iso_alpha2::text country_code,sr.evidence_id,sr.source_record_url,
    scholarship.normalise_first_party_url(sr.source_record_url) normalised_url,sr.payload,sr.status,sr.observed_at,sr.created_at,
    nullif(trim(sr.payload->>'name'),'') observed_name,scholarship.normalise_title(sr.payload->>'name') normalised_title,
    coalesce(nullif(sr.payload->>'confidence','')::numeric,0) confidence,
    row_number() over(partition by src.provider_id,scholarship.normalise_first_party_url(sr.source_record_url)
      order by sr.observed_at desc nulls last,sr.created_at desc,sr.id desc) url_recency_rank
  from pipeline.scholarship_source_records sr
  join pipeline.sources src on src.id=sr.source_id
  join catalogue.providers p on p.id=src.provider_id
  join ref.countries c on c.id=p.country_id
  where src.provider_id is not null and sr.evidence_id is not null and sr.status in ('captured','applied')
), classified as (
  select b.*,
    case
      when b.status='applied' then 'already_applied'
      when b.url_recency_rank>1 then 'duplicate_source'
      when coalesce(b.payload->>'identifier_scheme','')<>'first_party_detail_url' then 'not_first_party_detail'
      when lower(coalesce(b.payload->>'audience',''))<>'international' then 'not_international'
      when b.confidence<0.8 then 'low_confidence'
      when b.normalised_url is null or b.normalised_url !~ '^https?://' then 'invalid_url'
      when b.source_record_url ~* '[?&](query|collection|form|num_ranks|f\.)=' or b.source_record_url ~ '#!/' then 'catalogue_or_filter'
      when b.normalised_url ~* '/(scholarships|international-scholarships|global-scholarships-and-fellowships|scholarships-for-international-students)$' then 'catalogue_or_filter'
      when b.observed_name is null or length(b.observed_name)<8 then 'generic_or_navigation_title'
      when b.observed_name ~* '^(eligibility|faq|guidelines?|menu|go to top|skip to main content|find a scholarship|scholarships? for international students|international student scholarships|all scholarship opportunities for international students|global curtin scholarships|international scholarship detail|external scholarship opportunities|internal scholarship opportunities|government-funded scholarships|scholarships for commencing international students)$' then 'generic_or_navigation_title'
      when b.observed_name ~* 'is blocked$' then 'generic_or_navigation_title'
      else 'ready'
    end reconciliation_state
  from base b
)
select * from classified;

revoke all on pipeline.scholarship_verified_detail_reconciliation_candidates from public,anon,authenticated;
grant select on pipeline.scholarship_verified_detail_reconciliation_candidates to service_role;

-- Guarded service. Canonical creation is unpublished-only; browser roles cannot execute directly.
create or replace function scholarship.reconcile_verified_detail_records(
  p_actor uuid,p_action text default 'preview',p_country_code text default 'AU',p_provider_id uuid default null,p_limit integer default 100
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','scholarship','pipeline','catalogue','pim','ref','auth'
as $$
declare
  v_action text:=lower(coalesce(p_action,'preview'));v_country text:=upper(coalesce(nullif(p_country_code,''),'AU'));v_limit int:=least(greatest(coalesce(p_limit,100),1),250);
  r record;v_existing uuid;v_title_count int;v_scholarship uuid;v_stable_key text;v_trace uuid;v_candidate uuid;
  v_created int:=0;v_linked int:=0;v_applied int:=0;v_review_marked int:=0;v_ready int:=0;v_new int:=0;v_existing_count int:=0;v_generic int:=0;v_duplicate int:=0;
  v_percentage numeric;v_award_type text;v_result jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if v_action not in ('preview','apply') then raise exception 'action must be preview or apply' using errcode='22023'; end if;
  select count(*) filter(where reconciliation_state='ready'),count(*) filter(where reconciliation_state in ('generic_or_navigation_title','catalogue_or_filter')),count(*) filter(where reconciliation_state='duplicate_source')
    into v_ready,v_generic,v_duplicate from pipeline.scholarship_verified_detail_reconciliation_candidates x
    where x.country_code=v_country and (p_provider_id is null or x.provider_id=p_provider_id);
  with ready as (
    select x.*,
      (select s.id from scholarship.scholarships s where s.provider_id=x.provider_id and scholarship.normalise_first_party_url(s.source_url)=x.normalised_url order by s.created_at asc limit 1) url_match,
      (select count(*) from scholarship.scholarships s where s.provider_id=x.provider_id and scholarship.normalise_title(s.name)=x.normalised_title) title_match_count
    from pipeline.scholarship_verified_detail_reconciliation_candidates x where x.country_code=v_country and x.reconciliation_state='ready' and (p_provider_id is null or x.provider_id=p_provider_id)
  )
  select count(*) filter(where url_match is not null or title_match_count=1),count(*) filter(where url_match is null and title_match_count=0) into v_existing_count,v_new from ready;
  if v_action='preview' then
    return jsonb_build_object('ok',true,'action','preview','country_code',v_country,'provider_id',p_provider_id,'ready',v_ready,'existing_matches',v_existing_count,'new_unpublished_roots',v_new,'generic_or_catalogue_review',v_generic,'duplicate_source_rows',v_duplicate,'publication_changed',false,'canonical_mutation_authorised',false);
  end if;
  update pipeline.layer2_scholarship_discovery_candidates d set classification='needs_review',classification_reason='CF-171 reconciliation gate: extracted source record is catalogue/filter/navigation rather than a verified individual Scholarship',classified_at=now()
  from pipeline.sources src,pipeline.scholarship_verified_detail_reconciliation_candidates x
  where d.source_id=src.id and src.provider_id=x.provider_id and x.country_code=v_country and (p_provider_id is null or x.provider_id=p_provider_id)
    and x.reconciliation_state in ('generic_or_navigation_title','catalogue_or_filter') and d.classification='detail_ready'
    and scholarship.normalise_first_party_url(coalesce(d.detail_target_url,d.scholarship_url))=x.normalised_url;
  get diagnostics v_review_marked=row_count;
  for r in select x.* from pipeline.scholarship_verified_detail_reconciliation_candidates x where x.country_code=v_country and x.reconciliation_state='ready' and (p_provider_id is null or x.provider_id=p_provider_id) order by x.provider_name,x.observed_name,x.source_record_id limit v_limit loop
    v_existing:=null;v_title_count:=0;v_scholarship:=null;v_trace:=null;v_candidate:=null;v_percentage:=null;v_award_type:='text_only';
    select s.id into v_existing from scholarship.scholarships s where s.provider_id=r.provider_id and scholarship.normalise_first_party_url(s.source_url)=r.normalised_url order by s.created_at asc limit 1;
    if v_existing is null then select count(*),min(s.id::text)::uuid into v_title_count,v_existing from scholarship.scholarships s where s.provider_id=r.provider_id and scholarship.normalise_title(s.name)=r.normalised_title; if v_title_count<>1 then v_existing:=null; end if; end if;
    if v_existing is not null then v_scholarship:=v_existing;v_linked:=v_linked+1;
    else
      v_stable_key:='scholarship:'||v_country||':first-party:'||replace(r.provider_id::text,'-','')||':'||md5(r.normalised_url);v_scholarship:=scholarship.deterministic_uuid(v_stable_key);
      insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status) values(v_scholarship,'scholarship',v_stable_key,'active') on conflict(stable_key) do update set lifecycle_status='active',updated_at=now();
      if coalesce(r.payload->>'award_value_text','') ~* '^\s*[0-9]+(\.[0-9]+)?\s*%\s*(tuition(\s+fee(s)?)?)?\s*$' then v_percentage:=substring(r.payload->>'award_value_text' from '([0-9]+(?:\.[0-9]+)?)')::numeric;v_award_type:='percentage'; end if;
      insert into scholarship.scholarships(id,stable_key,provider_id,name,scholarship_type,description,audience,award_value_text,application_required,application_close_date,academic_year,source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence,award_value_type,award_percentage,updated_at)
      values(v_scholarship,v_stable_key,r.provider_id,r.observed_name,coalesce(nullif(r.payload->>'scholarship_type',''),'provider_scholarship'),nullif(r.payload->>'description',''),'international',nullif(r.payload->>'award_value_text',''),true,
        case when coalesce(r.payload->>'application_close_date','') ~ '^\d{4}-\d{2}-\d{2}$' then (r.payload->>'application_close_date')::date else null end,
        case when coalesce(r.payload->>'academic_year','') ~ '^20\d{2}$' then (r.payload->>'academic_year')::int else null end,
        r.normalised_url,'active','unpublished',r.source_id,r.evidence_id,r.confidence,v_award_type,v_percentage,now()) on conflict(id) do nothing;v_created:=v_created+1;
    end if;
    select t.id into v_trace from pipeline.scholarship_acquisition_trace t where t.source_record_id=r.source_record_id or (t.provider_id=r.provider_id and scholarship.normalise_first_party_url(t.first_party_detail_url)=r.normalised_url) order by t.updated_at desc limit 1;
    select d.id into v_candidate from pipeline.layer2_scholarship_discovery_candidates d join pipeline.sources src on src.id=d.source_id where src.provider_id=r.provider_id and scholarship.normalise_first_party_url(coalesce(d.detail_target_url,d.scholarship_url))=r.normalised_url order by d.created_at desc limit 1;
    if v_trace is null then
      insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,discovery_candidate_id,source_record_id,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,updated_at,metadata)
      values(r.provider_id,r.observed_name,r.normalised_url,v_candidate,r.source_record_id,v_scholarship,r.evidence_id,'canonical_unpublished','verified_first_party',coalesce(r.observed_at,r.created_at,now()),now(),now(),jsonb_build_object('reconciliation','CF-171','actor',p_actor,'rule','verified individual first-party detail only')) returning id into v_trace;
    else
      update pipeline.scholarship_acquisition_trace set observed_title=coalesce(observed_title,r.observed_name),first_party_detail_url=coalesce(first_party_detail_url,r.normalised_url),discovery_candidate_id=coalesce(discovery_candidate_id,v_candidate),source_record_id=coalesce(source_record_id,r.source_record_id),scholarship_id=coalesce(scholarship_id,v_scholarship),verification_evidence_id=coalesce(verification_evidence_id,r.evidence_id),stage='canonical_unpublished',verification_status='verified_first_party',verified_at=coalesce(verified_at,now()),updated_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('reconciliation','CF-171','actor',p_actor) where id=v_trace;
    end if;
    update pipeline.scholarship_source_records set status='applied',applied_at=now(),error_text=null where id=r.source_record_id and status='captured';if found then v_applied:=v_applied+1;end if;
    if v_candidate is not null then update pipeline.layer2_scholarship_discovery_candidates set status='acquired' where id=v_candidate and status='discovered';end if;
  end loop;
  return jsonb_build_object('ok',true,'action','apply','country_code',v_country,'provider_id',p_provider_id,'processed',v_applied,'created_unpublished',v_created,'linked_existing',v_linked,'review_reclassified',v_review_marked,'publication_changed',false,'canonical_mutation_authorised',true,'rule','Only verified international first-party individual detail records can create unpublished canonical roots.');
end;$$;
revoke all on function scholarship.reconcile_verified_detail_records(uuid,text,text,uuid,integer) from public,anon,authenticated;
grant execute on function scholarship.reconcile_verified_detail_records(uuid,text,text,uuid,integer) to service_role;