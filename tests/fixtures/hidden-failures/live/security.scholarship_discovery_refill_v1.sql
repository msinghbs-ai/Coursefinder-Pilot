CREATE OR REPLACE FUNCTION security.scholarship_discovery_refill_v1(p_keep integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pending int; v_added int := 0; v_tier int; v_due int; v_skip int; v_round int; v_pilot jsonb;
begin
  perform security.provider_sch_search_auto_v1();  -- v2.15.271: directory-only providers switched Off
  select count(*) into v_pending from pipeline.scholarship_discovery_providers where status in ('pending', 'deferred');
  if v_pending < p_keep then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
    select q.provider_id, q.website, case when q.cc = 'AU' then 4 else 1 end, case when q.cc = 'AU' then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'
      from (select p.id provider_id, k.iso_alpha2 cc,
                   coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) website,
                   count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
               -- CF-247 scholarship recovery P1 (proposed, off): with non-university admission on, governed non-university providers overseas too
               and (k.iso_alpha2 = 'AU' or security.scholarship_admission_provider_ok_v1(p.id))
               and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
             group by p.id, p.website, k.iso_alpha2) q
     where q.website is not null
       -- v2.15.265: qualifying providers only, never a directory site; top-50, Australian 30+, overseas
       and security.fc_sch_eligible_v1(q.provider_id) and not security.third_party_host_v1(q.website)
       and not security.provider_sch_search_off_v1(q.provider_id)  -- v2.15.271
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
     order by security.fc_provider_tier_v1(q.provider_id), q.n desc, q.provider_id limit greatest(0, p_keep - v_pending)
    on conflict do nothing;
    get diagnostics v_added = row_count;
  end if;
  -- CF-247 scholarships beyond universities: the pilot providers are queued, due once after the list was saved, and their stored refused pages admitted again
  v_pilot := security.scholarship_pilot_start_v1();
  -- CF-247 scholarship recovery F1: the stored processing tier, a batch an hour
  v_tier := security.scholarship_discovery_tier_refresh_v1(security.pipeline_num_v1('batch.scholarship_tier_refresh', 500)::int);
  -- F3: providers mapped before the cadence existed are due the cadence after their last map
  update pipeline.scholarship_discovery_providers set next_discover_at = coalesce(discovered_at, now()) + make_interval(days => security.pipeline_num_v1('reread.scholarship_discovery_days', 30)::int)
   where status in ('mapped', 'empty') and next_discover_at is null;
  get diagnostics v_due = row_count;
  -- F1: the address skip rules on unread candidates; F9: round states
  v_skip := security.scholarship_candidate_skip_v1(null, security.pipeline_num_v1('batch.scholarship_candidate_skip', 5000)::int);
  v_round := security.scholarship_round_state_refresh_v1(security.pipeline_num_v1('batch.scholarship_round_state', 1000)::int);
  return jsonb_build_object('pending_before', v_pending, 'added', v_added, 'pilot', v_pilot, 'tiers', v_tier, 'cadence_set', v_due, 'skipped', v_skip, 'round_states', v_round);
end $function$
