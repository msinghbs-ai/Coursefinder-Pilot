set local statement_timeout='8s';
with res as (select x.* from (values ('adelaide_keep_held'),('canberra_no_year'),('sfu_no_term')) rr(p) cross join lateral (
  with rule as (select * from (select * from (values
  ('adelaide_keep_held'::text, 'de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid, 'keep'::text, '%CRICOS code is a different address%'::text, '^adelaide\.edu\.au/'::text, 'adelaideuni.edu.au/'::text, array['cricos_code']::text[]),
  ('canberra_no_year', '0e1532b8-de30-4761-87fe-460684608633'::uuid, 'use', '%CRICOS code is a different address%', '/20[0-9]{2}$', '', array['cricos_code']),
  ('sfu_no_term', 'd47b6006-396a-4785-b2ae-15186c3e7709'::uuid, 'use', '%CRICOS code is a different address%', '^(sfu\.ca/students/calendar/)20[0-9]{2}/(spring|summer|fall)/', '\1', array['field_award', 'exact_title', 'title_level', 'cricos_code'])
 ) x(code, provider_id, choice, reason_like, held_regex, proposed_replace, identity_bases)) r where r.code = rr.p),
  it as (
    select i.id item_id, i.entity_id course_id, i.claimed_at, i.assigned_to, i.status, i.before_value, i.layer2_state, i.escalation_reason,
           security.layer4_url_key_v1(case when jsonb_typeof(i.before_value) = 'array' then i.before_value->>0 end) held_key,
           case when jsonb_typeof(i.before_value) = 'array' then i.before_value->>0 end held_url,
           security.layer4_url_key_v1(coalesce(i.proposed_value->>'course_url', i.proposed_value->>'url')) prop_key,
           coalesce(i.proposed_value->>'course_url', i.proposed_value->>'url') prop_url,
           case when jsonb_typeof(i.before_value) = 'array' then jsonb_array_length(i.before_value) else 0 end n_held
      from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id join rule on c.provider_id = rule.provider_id
     where i.status = 'pending' and i.field_code = 'official_course_url' and i.escalation_reason ilike rule.reason_like),
  m as (
    select it.*, rule.code, rule.choice, rule.identity_bases,
           it.held_key ~ rule.held_regex and it.prop_key = regexp_replace(it.held_key, rule.held_regex, rule.proposed_replace) pattern_ok,
           case when rule.choice = 'keep' then it.held_url else it.prop_url end target_url,
           case when rule.choice = 'keep' then it.held_key else it.prop_key end target_key
      from it cross join rule),
  e as (
    select m.*, c.lifecycle_status, c.course_code, c.open_to_international, k.iso_alpha2 country,
           (select jsonb_build_object('id', ev.id, 'captured_at', ev.captured_at, 'course_id', ev.metadata->>'course_id', 'identity_basis', ev.metadata->>'identity_basis')
              from pipeline.evidence_artifacts ev
             where lower(ev.source_url) = any (array['https://' || m.target_key, 'https://' || m.target_key || '/', 'https://www.' || m.target_key, 'https://www.' || m.target_key || '/',
                                                     'http://' || m.target_key, 'http://' || m.target_key || '/', 'http://www.' || m.target_key, 'http://www.' || m.target_key || '/'])
             order by (ev.metadata->>'course_id' = m.course_id::text) desc, ev.captured_at desc nulls last limit 1) copy,
           (select array_agg(security.layer4_url_key_v1(l.url) order by l.url) from catalogue.course_links l
             where l.course_id = m.course_id and l.link_type = 'official_course' and l.status = 'active') active_keys,
           (select g.basis from pipeline.coverage_course_pages g where g.course_id = m.course_id) binding_basis,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field in ('official_url', 'course_url')) locked,
           exists (select 1 from pipeline.page_rejections r where r.course_id = m.course_id and security.layer4_url_key_v1(r.url) = m.target_key) target_refused
      from m join catalogue.courses c on c.id = m.course_id
      left join catalogue.providers p on p.id = c.provider_id left join ref.countries k on k.id = p.country_id),
  v as (
    select e.*, array_remove(array[
             case when e.claimed_at is not null or e.assigned_to is not null then 'claimed by a reviewer' end,
             case when e.n_held <> 1 then 'not exactly one page held (' || e.n_held || ')' end,
             case when not coalesce(e.pattern_ok, false) then 'addresses do not follow the approved pattern' end,
             case when e.lifecycle_status is distinct from 'active' then 'course not active' end,
             case when e.copy is null then 'no stored copy of the ' || case when e.choice = 'keep' then 'held' else 'proposed' end || ' page' end,
             case when e.copy is not null and e.copy->>'course_id' is distinct from e.course_id::text then 'stored copy was read for another course' end,
             case when e.copy is not null and not (coalesce(e.copy->>'identity_basis', '') = any (e.identity_bases)) then 'stored copy identity basis ' || coalesce(e.copy->>'identity_basis', 'none') || ' is not an exact-course basis' end,
             case when e.open_to_international is false then 'course not open to international students' end,
             case when e.country = 'AU' and coalesce(e.course_code, '') !~ '^[0-9]{6}[0-9A-Z]$' then 'no CRICOS code on the course record' end,
             case when e.active_keys is distinct from array[e.held_key] then 'active official page is no longer exactly the held page' end,
             case when e.binding_basis = 'manual' then 'page binding was set by hand' end,
             case when e.locked then 'manual lock on the official page' end,
             case when e.choice = 'use' and e.target_refused then 'the proposed page was refused for this course' end], null) reasons
      from e)
  select v.code, v.item_id, v.course_id, v.course_code, v.choice, v.held_url, v.prop_url, v.target_url, coalesce(cardinality(v.reasons), 0) = 0, v.reasons,
         jsonb_build_object('stored_copy', v.copy, 'active_pages', to_jsonb(v.active_keys), 'binding_basis', v.binding_basis, 'country', v.country, 'claimed_at', v.claimed_at)
    from v order by v.course_code, v.item_id

) x(code,item_id,course_id,course_code,choice,held_url,prop_url,target_url,pass,reasons,detail))
select code, item_id, course_code, pass, array_to_string(reasons, '; ') reasons, detail->'stored_copy'->>'identity_basis' basis from res order by code, pass, course_code;
