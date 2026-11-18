-- CF-247 Destination: open-licence editions are approved and published without manual clicks; BOM climate statistics terms recorded
-- (S2-Build, Platform Admin 18 Nov 2026 13:07).
--
-- What was read live (18 Nov 2026 13:45 AEDT)
--   * destination.editions holds two editions for Australia: "ABS Regional population 2024-25" (city_profiles, published) and "BOM Climate
--     statistics for Australian locations (IDCJCM0037)" (city_profiles, draft, terms pending; Pilot #1256). No climate figure is loaded yet:
--     job destination-climate-load runs on the 2nd of the month and has not run. No RM1I living-cost, RM1C/RM1H study-rule or RM1D career
--     edition exists yet (those loads need their page evidence first), so there is nothing else to publish today.
--   * The Bureau of Meteorology's copyright page licenses Bureau content from the Commonwealth of Australia under Creative Commons
--     Attribution 4.0 International, with the Coat of Arms and the Bureau's logo excluded (bom.gov.au/copyright, read 18 Nov 2026).
--   * security.destination_edition_publish_v1 supersedes every other published edition of the same country and domain. Climate figures and
--     the ABS population figures are both city_profiles editions, so publishing the BOM edition would have marked the ABS edition superseded.
--
-- What it changes
--   1. The BOM edition's terms are recorded and approved (CC BY 4.0, attribution "Bureau of Meteorology, Commonwealth of Australia, CC BY
--      4.0"), as the Platform Admin directed on 18 Nov 2026 13:07, with an audit event. Its climate load is asked for now (Run now of job
--      destination-climate-load), so the figures arrive as attributed drafts.
--   2. security.destination_edition_publish_v1 supersedes only a published edition of the same country, domain and source owner (a BOM
--      edition replaces an earlier BOM edition, never the ABS one).
--   3. security.destination_open_licence_publish_v1 (rollup-scheduler target destination-open-licence-publish, hourly): for an edition whose
--      source owner is on the setting destination.open_licence_owners (Australian government open data under a standard public reuse
--      licence; QILT is not on it and stays gated until written permission is recorded) and whose terms are approved, it approves the draft
--      rows that carry a value and an attribution (city figures, career outcomes) or a quote and evidence (study rules), then publishes the
--      edition when it has approved rows. Each approval and publication is logged in pipeline.admin_control_events (area destination).
--      An edition whose terms are pending or restricted, or whose owner is not on the list, is never touched.
-- Nothing is dropped or deleted. G3 untouched: the destination tables are read by API v3 (open to additions until go-live, Decision 277),
-- and only row statuses change, never a shape.
-- Replaces: manual Approve all and Publish clicks for open-licence government editions (they stay available on Destination for any edition).
-- Retires: nothing.

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

-- 1. the open-licence owners (a setting, G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, unit, sort, reason, section, used_by) values
 ('pipeline', 'destination.open_licence_owners', 'Destination: open-licence owners published without a click',
  'Source owners whose editions are Australian government open data under a standard public reuse licence. When such an edition''s terms are approved, its attributed draft rows are approved and the edition is published by the hourly job (destination-open-licence-publish), with an audit entry. Leave an owner off this list (for example QILT) until written permission is recorded.',
  'list', '["Bureau of Meteorology", "Australian Bureau of Statistics", "Study Australia", "Study Tasmania", "Department of Home Affairs", "Fair Work Ombudsman", "Jobs and Skills Australia"]'::jsonb,
  'owners', 794, 'Platform Admin 18 Nov 2026 13:07 (S2-Build): public CC BY and government open-data editions publish without manual clicks; QILT stays gated', 'Destination', 'security.destination_open_licence_publish_v1')
on conflict (toolset_key, key) do nothing;

-- 2. publishing replaces only an edition of the same source owner
select pg_temp.cf_edit('security.destination_edition_publish_v1(uuid,uuid)'::regprocedure, '79cad4f1d0fcdf086020be381dd25961',
  'where x.country_id = v.country_id and x.domain = v.domain and x.status = ''published'' and x.id <> v.id',
  'where x.country_id = v.country_id and x.domain = v.domain and x.status = ''published'' and x.id <> v.id and x.source_owner is not distinct from v.source_owner',
  'x.source_owner is not distinct from v.source_owner');

-- 3. the hourly open-licence approval and publication
create or replace function security.destination_open_licence_publish_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_owners text[] := security.pipeline_list_v1('destination.open_licence_owners', '[]'::jsonb);
        e record; v_n int; v_res jsonb; v_out jsonb := '[]'::jsonb; v_rows int;
        v_why constant text := 'Open licence recorded (terms approved, owner on destination.open_licence_owners): approved automatically under the Platform Admin decision of 18 Nov 2026 13:07';
begin
  perform pg_advisory_xact_lock(hashtext('cf247:destination-open-licence-publish'));  -- fixed: one run at a time
  for e in select x.* from destination.editions x
            where x.status in ('draft', 'in_review') and x.terms_status = 'approved' and x.source_owner = any (v_owners)
              and nullif(btrim(coalesce(x.attribution_text, '')), '') is not null
            order by x.created_at loop
    v_n := 0;
    if e.domain = 'city_profiles' then
      update destination.locality_metrics m set status = 'approved', status_reason = v_why, status_changed_at = now(), updated_at = now()
       where m.dataset_edition = e.edition_label and m.status = 'draft' and m.numeric_value is not null
         and nullif(btrim(coalesce(m.attribution_text, '')), '') is not null
         and exists (select 1 from destination.localities l join ref.countries c on c.iso_alpha2 = l.country_code where l.id = m.locality_id and c.id = e.country_id);
      get diagnostics v_n = row_count;
    elsif e.domain = 'career_outcomes' then
      update destination.career_outcomes o set status = 'approved', status_reason = v_why, status_changed_at = now()
       where o.edition_id = e.id and o.status = 'draft' and nullif(btrim(coalesce(o.attribution_text, '')), '') is not null;
      get diagnostics v_n = row_count;
    elsif e.domain = 'study_rules' then
      update destination.study_rules r set approval_status = 'approved', approved_at = now(), status_reason = v_why
       where r.edition_id = e.id and r.approval_status = 'draft' and r.evidence_id is not null and nullif(btrim(coalesce(r.quote_on_page, '')), '') is not null;
      get diagnostics v_n = row_count;
    end if;
    if v_n > 0 then
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('destination', 'open_licence_rows_approve', e.edition_label, jsonb_build_object('edition_id', e.id, 'domain', e.domain, 'approved', v_n, 'owner', e.source_owner, 'reason', v_why), null);
    end if;
    v_rows := coalesce((security.destination_edition_rows_v1(e.id)->>'rows_approved')::int, 0);
    if v_rows > 0 then
      v_res := security.destination_edition_publish_v1(e.id, e.approved_by);
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('destination', 'open_licence_publish', e.edition_label, jsonb_build_object('edition_id', e.id, 'domain', e.domain, 'owner', e.source_owner, 'result', v_res, 'reason', v_why), null);
    end if;
    v_out := v_out || jsonb_build_object('edition', e.edition_label, 'approved', v_n, 'rows_approved', v_rows, 'published', v_rows > 0);
  end loop;
  return jsonb_build_object('editions', v_out, 'owners', to_jsonb(v_owners));
end $f$;
comment on function security.destination_open_licence_publish_v1() is
  'CF-247 18 Nov 2026 (S2-Build, Platform Admin 13:07): approves attributed draft rows of open-licence government editions with approved terms (owner on destination.open_licence_owners) and publishes the edition; rollup-scheduler target destination-open-licence-publish.';
revoke all on function security.destination_open_licence_publish_v1() from public, anon, authenticated;

insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, enabled, mode, expected_ms, note)
values ('destination-open-licence-publish', null, 'select security.destination_open_licence_publish_v1()', md5('select security.destination_open_licence_publish_v1()'),
        '41 * * * *', 'A', 70, true, 'live', 1000,
        'CF-247 18 Nov 2026 (Platform Admin 13:07): new target, no legacy job; approves and publishes open-licence government destination editions')
on conflict (target_code) do nothing;

-- 4. the BOM climate statistics edition: terms recorded and approved, then its load asked for now
do $e$
declare v_ed uuid; v_admin constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin who gave the direction (13:07)
        v_res jsonb; v_run jsonb;
        v_attr constant text := 'Source: Bureau of Meteorology, Commonwealth of Australia. Climate statistics for Australian locations (IDCJCM0037), bom.gov.au/climate/averages. Licensed under Creative Commons Attribution 4.0 (CC BY 4.0); the Coat of Arms and the Bureau''s logo are excluded.';
begin
  select x.id into v_ed from destination.editions x where x.edition_label = 'BOM Climate statistics for Australian locations (IDCJCM0037)' and x.source_owner = 'Bureau of Meteorology';
  if v_ed is null then raise exception 'the BOM climate statistics edition is not held'; end if;
  update destination.editions set attribution_text = v_attr, last_checked_at = now() where id = v_ed;
  v_res := security.destination_edition_set_terms_v1(v_ed, 'approved', v_admin);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', 'edition_terms', 'BOM Climate statistics for Australian locations (IDCJCM0037)',
          jsonb_build_object('edition_id', v_ed, 'terms', 'approved', 'licence', 'CC BY 4.0', 'attribution', v_attr, 'checked', 'bom.gov.au/copyright, 18 Nov 2026',
                             'reason', 'Platform Admin 18 Nov 2026 13:07 (S2-Build): record and approve the Bureau of Meteorology CC BY 4.0 terms with full attribution', 'result', v_res,
                             'by', 'migration 20261118161000'), v_admin);
  begin
    v_run := security.destination_job_run_now_v1('destination-climate-load', 'Platform Admin 18 Nov 2026 13:07: load the BOM climate figures now so the edition can be published',
                                                 jsonb_build_object('idempotency_key', 'cf247-20261118161000-climate'), v_admin);
    raise notice 'climate load asked for: %', v_run;
  exception when others then
    raise notice 'the climate load could not be asked for now (%); it runs on its schedule', sqlerrm;
  end;
end $e$;

select security.destination_open_licence_publish_v1();

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, 'Layer 1', 'Destination', v.purpose, 'active', '20261118161000'
  from (values
    ('function', 'security.destination_open_licence_publish_v1', 'Approves attributed draft rows of open-licence government destination editions with approved terms and publishes them (rollup-scheduler target destination-open-licence-publish, hourly at :41)')) v(kind, name, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

-- post-checks
do $e$
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
  if (select status from destination.editions where edition_label = 'ABS Regional population 2024-25') <> 'published' then
    raise exception 'the ABS population edition must stay published';
  end if;
  if (select terms_status from destination.editions where edition_label = 'BOM Climate statistics for Australian locations (IDCJCM0037)') <> 'approved' then
    raise exception 'the BOM edition terms were not recorded';
  end if;
end $e$;
