-- CF-247, 8 Oct 2026 (Platform Admin approved the Layers 1-4 adapter design; Phase 1 starts with the first standing review rule).
-- Rule 1, "source is not the provider's own site": a value admitted from a course page on a shared site (a host whose pages are bound to
-- courses of 3 or more providers, or one of the directory hosts the retention estimate lists) that is not the provider's own website goes to
-- Layer 4 review (a subdomain of the provider's own website counts as its own site), one item per course and field (intakes, English, official course page). Registers confirm that the course exists; finer
-- details are confirmed only on the provider's own course page. The value stays shown until a person decides; Approve keeps it as it is.
-- An item is not raised again for the same page evidence once a person has decided it. Runs daily; nothing is removed or blocked.
create table if not exists pipeline.layer4_rule_runs (
  id bigint generated always as identity primary key, rule text not null, at timestamptz not null default now(), raised jsonb not null);
alter table pipeline.layer4_rule_runs enable row level security;
revoke all on pipeline.layer4_rule_runs from public, anon, authenticated;

create or replace function security.l4_rule_unofficial_source_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_i int; v_e int; v_l int; v_hosts text[]; v_r jsonb;
begin
  select array(select distinct h from (
      select substring(pg.url from '^https?://(?:www\.)?([^/:?#]+)') h from pipeline.coverage_course_pages pg
       group by 1 having count(distinct pg.provider_id) >= 3
      union
      select jsonb_array_elements_text(coalesce((select e.detail->'hosts' from pipeline.retention_estimates e where e.category = 'directory_urls'), '[]'::jsonb))) x where h is not null)
    into v_hosts;

  create temporary table rule_pages on commit drop as
    select pg.course_id, pg.provider_id, pg.url, pg.evidence_id, substring(pg.url from '^https?://(?:www\.)?([^/:?#]+)') host
      from pipeline.coverage_course_pages pg join catalogue.providers p on p.id = pg.provider_id
     where pg.evidence_id is not null and substring(pg.url from '^https?://(?:www\.)?([^/:?#]+)') = any(v_hosts)
       and (p.website is null or not (
             substring(pg.url from '^https?://(?:www\.)?([^/:?#]+)') = substring(p.website from '^https?://(?:www\.)?([^/:?#]+)')
             or substring(pg.url from '^https?://(?:www\.)?([^/:?#]+)') like '%.' || substring(p.website from '^https?://(?:www\.)?([^/:?#]+)')));

  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref)
  select 'course', d.course_id, 'course_intake', d.evidence_id, jsonb_agg(distinct i.intake_label),
         jsonb_build_object('intakes', jsonb_agg(distinct jsonb_build_object('intake_label', i.intake_label, 'source_intake_key', null))), 'pending',
         format('Rule 1, source is not the provider''s own site: read from %s (%s), a site shared by several providers. The register confirms the course; confirm the intakes on the provider''s own course page. Approve keeps them as they are; the value stays shown until decided.', d.host, d.url),
         'CF-CHG-20260915-247'
    from rule_pages d join catalogue.course_intakes i on i.course_id = d.course_id and i.evidence_id = d.evidence_id and i.status = 'active'
   where not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = d.course_id and r.field_code = 'course_intake'
                       and (r.status = 'pending' or r.evidence_id = d.evidence_id))
   group by d.course_id, d.evidence_id, d.host, d.url;
  get diagnostics v_i = row_count;

  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref)
  select 'course', d.course_id, 'course_english', d.evidence_id, jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score)),
         jsonb_build_object('english_requirements', jsonb_agg(jsonb_build_object('notes', 'Shared-site page, kept after review', 'test_code', t.code, 'overall_score', e.overall_score, 'component_scores', coalesce(e.component_scores, '{}'::jsonb)))), 'pending',
         format('Rule 1, source is not the provider''s own site: read from %s (%s), a site shared by several providers. The register confirms the course; confirm the English requirement on the provider''s own course page. Approve keeps it as it is; the value stays shown until decided.', d.host, d.url),
         'CF-CHG-20260915-247'
    from rule_pages d join catalogue.course_english_requirements e on e.course_id = d.course_id and e.evidence_id = d.evidence_id and e.status = 'active'
    join ref.english_tests t on t.id = e.english_test_id
   where not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = d.course_id and r.field_code = 'course_english'
                       and (r.status = 'pending' or r.evidence_id = d.evidence_id))
   group by d.course_id, d.evidence_id, d.host, d.url;
  get diagnostics v_e = row_count;

  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref)
  select distinct on (d.course_id) 'course', d.course_id, 'official_course_url', d.evidence_id, jsonb_build_array(l.url), jsonb_build_object('course_url', l.url), 'pending',
         format('Rule 1, source is not the provider''s own site: the official course page on record is on %s, a site shared by several providers. Find the provider''s own course page and edit the address, or reject. The link stays shown until decided.', d.host),
         'CF-CHG-20260915-247'
    from rule_pages d join catalogue.course_links l on l.course_id = d.course_id and l.url = d.url and l.status = 'active'
   where not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = d.course_id and r.field_code = 'official_course_url'
                       and (r.status = 'pending' or r.evidence_id = d.evidence_id))
   order by d.course_id, l.is_primary desc;
  get diagnostics v_l = row_count;

  v_r := jsonb_build_object('hosts', to_jsonb(v_hosts), 'intake_items', v_i, 'english_items', v_e, 'course_link_items', v_l);
  insert into pipeline.layer4_rule_runs(rule, raised) values ('unofficial_source', v_r);
  return v_r;
end $f$;
revoke all on function security.l4_rule_unofficial_source_v1() from public, anon, authenticated;

select cron.schedule('l4-rule-unofficial-source', '17 3 * * *', 'select security.l4_rule_unofficial_source_v1()');
