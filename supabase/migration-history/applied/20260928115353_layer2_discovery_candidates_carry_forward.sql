-- CF-247: Layer 2 course extraction had stopped. Decision 152 (26 Sep) created a new version of 3,057 Layer 2
-- profiles, changing only freshness_sla_hours. Discovered course URLs are stored per profile version and were
-- not carried to the new versions, so every current version had no URLs and scheduled extraction found nothing
-- to fetch (141 profiles, 7,301 discovered URLs, 565 selected).
-- 1. Carry discovered URLs forward to the Decision 152 versions (configuration identical apart from
--    freshness_sla_hours; checked per version). Each copy records the version it came from.
-- 2. From now on, a new version whose discovery settings (discovery_strategy, url_patterns) are unchanged
--    inherits its predecessor's discovered URLs, so a settings-only change cannot empty extraction again.
-- No catalogue, Search or consumer API change.

create or replace function pipeline.layer2_carry_forward_discovery_candidates(p_new_version uuid)
returns integer language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v_new pipeline.layer2_source_profile_versions; v_old pipeline.layer2_source_profile_versions; v_n integer:=0;
begin
  select * into v_new from pipeline.layer2_source_profile_versions where id=p_new_version;
  if not found then return 0; end if;
  select * into v_old from pipeline.layer2_source_profile_versions
   where profile_id=v_new.profile_id and version_no<v_new.version_no order by version_no desc limit 1;
  if not found then return 0; end if;
  if (v_new.configuration->'discovery_strategy') is distinct from (v_old.configuration->'discovery_strategy')
     or (v_new.configuration->'url_patterns') is distinct from (v_old.configuration->'url_patterns') then return 0; end if;
  if exists (select 1 from pipeline.layer2_course_discovery_candidates where source_profile_version_id=v_new.id) then return 0; end if;
  insert into pipeline.layer2_course_discovery_candidates(trial_course_id,course_id,source_profile_version_id,provider_attempt_id,evidence_id,
         discovered_url,discovered_title,discovered_regulatory_code,match_score,match_basis,status,selected,blocker,created_at)
  select c.trial_course_id,c.course_id,v_new.id,c.provider_attempt_id,c.evidence_id,c.discovered_url,c.discovered_title,c.discovered_regulatory_code,
         c.match_score,coalesce(c.match_basis,'{}'::jsonb)||jsonb_build_object('carried_forward_from_version',v_old.id,'carried_forward_at',now()),
         c.status,c.selected,c.blocker,c.created_at
    from pipeline.layer2_course_discovery_candidates c where c.source_profile_version_id=v_old.id;
  get diagnostics v_n=row_count;
  return v_n;
end $f$;
revoke all on function pipeline.layer2_carry_forward_discovery_candidates(uuid) from public, anon, authenticated;

create or replace function pipeline.trg_layer2_profile_version_carry_forward()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin perform pipeline.layer2_carry_forward_discovery_candidates(new.id); return null; end $f$;
drop trigger if exists trg_layer2_profile_version_carry_forward on pipeline.layer2_source_profile_versions;
create trigger trg_layer2_profile_version_carry_forward after insert on pipeline.layer2_source_profile_versions
  for each row execute function pipeline.trg_layer2_profile_version_carry_forward();

-- One-time repair of the Decision 152 versions (configuration identical apart from freshness_sla_hours).
do $repair$
declare r record; v_total integer:=0; v_profiles integer:=0; v_n integer;
begin
  for r in select v.id from pipeline.layer2_source_profile_versions v
            join lateral (select * from pipeline.layer2_source_profile_versions p where p.profile_id=v.profile_id and p.version_no<v.version_no order by version_no desc limit 1) pv on true
           where v.uat_ref='Decision-152-admission-lifecycle'
             and (v.configuration - 'freshness_sla_hours') = (pv.configuration - 'freshness_sla_hours')
  loop
    v_n:=pipeline.layer2_carry_forward_discovery_candidates(r.id);
    if v_n>0 then v_total:=v_total+v_n; v_profiles:=v_profiles+1; end if;
  end loop;
  raise notice 'carried % discovered URLs forward for % profiles', v_total, v_profiles;
  if v_total<>7301 or v_profiles<>141 then raise exception 'expected 7,301 URLs for 141 profiles, got % for %; nothing changed', v_total, v_profiles; end if;
end $repair$;
