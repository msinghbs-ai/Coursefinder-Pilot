-- CF-190 — structural terminal guard for obvious navigation/support catalogue observations.
create or replace function pipeline.scholarship_candidate_semantic_terminal_guard()
returns trigger language plpgsql security definer set search_path='pg_catalog','pipeline'
as $$
declare v_title text:=lower(trim(coalesce(new.observed_title,''))); v_url text:=lower(coalesce(nullif(new.detail_target_url,''),nullif(new.scholarship_url,''),''));
begin
  if v_title ~ '^(search|about us|learn more|scholarships? & grants|academic scholarships|external scholarships|scholarships and fees|financial aid for international students|domestic student scholarships|prestigious.*scholarships|home country sponsored scholarships)$'
     or v_url ~ '/search\.html([?#].*)?$' or v_url ~ '/about-us(\.html)?([?#].*)?$' or v_url ~ '/scholarships/domestic/?([?#].*)?$' or v_url ~ '/home-country-sponsored-scholarships/?([?#].*)?$' then
    new.classification:='support_or_navigation'; new.classification_reason:='CF-190 semantic terminal guard: navigation, collection, domestic or support page is not an individual international Scholarship'; new.classified_at:=now();
  elsif v_title ~ '^(scholarships?|scholarships? for international students|international scholarships?)$' and v_url ~ '/scholarships?/?([?#].*)?$' then
    new.classification:='catalogue_or_filter'; new.classification_reason:='CF-190 semantic terminal guard: Scholarship catalogue root retained as Evidence only'; new.classified_at:=now();
  end if;
  return new;
end $$;

drop trigger if exists trg_scholarship_candidate_semantic_terminal_guard on pipeline.layer2_scholarship_discovery_candidates;
create trigger trg_scholarship_candidate_semantic_terminal_guard before insert or update of observed_title,scholarship_url,detail_target_url,classification on pipeline.layer2_scholarship_discovery_candidates for each row execute function pipeline.scholarship_candidate_semantic_terminal_guard();
update pipeline.layer2_scholarship_discovery_candidates set classification=classification where status='discovered';
update pipeline.scholarship_source_records set status='unmapped',error_text='CF-190 generic/navigation/support page retained as Evidence; individual Scholarship reconciliation required' where status='captured' and lower(coalesce(payload->>'name','')) ~ '^(about us|academic scholarships|external scholarships|scholarships and fees|financial aid for international students|domestic student scholarships|scholarships & grants|prestigious.*scholarships|home country sponsored scholarships)$';
update pipeline.jobs j set status='succeeded',completed_at=coalesce(completed_at,now()),started_at=coalesce(started_at,created_at),result=coalesce(result,'{}'::jsonb)||jsonb_build_object('skipped',true,'reason','CF-190 semantic terminal guard','publication_changed',false,'canonical_mutation_authorised',false),error_text=null where j.domain='scholarship' and j.job_type='scholarship_scope_acquisition' and j.status in('queued','running') and nullif(j.payload->>'candidate_id','') is not null and exists(select 1 from pipeline.layer2_scholarship_discovery_candidates d where d.id=(j.payload->>'candidate_id')::uuid and d.classification in('support_or_navigation','catalogue_or_filter','external_or_out_of_scope'));
revoke all on function pipeline.scholarship_candidate_semantic_terminal_guard() from public,anon,authenticated;
grant execute on function pipeline.scholarship_candidate_semantic_terminal_guard() to service_role;
