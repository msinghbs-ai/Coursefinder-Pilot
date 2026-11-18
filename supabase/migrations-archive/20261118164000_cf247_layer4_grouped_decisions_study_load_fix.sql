-- CF-247 Layer 4 grouped decisions: the study-load groups read again (S2-Build, Platform Admin 18 Nov 2026 13:02; fix to migration 20261118162000).
--
-- What was read live (18 Nov 2026 14:25 AEDT, after Pilot #1277 deployed): admin_layer4_group_decide_read_v1 for kind boost_study_load failed
-- with "subquery uses ungrouped column r.answer": the per-group count of what the model said referred to the outer row. The AER groups were
-- unaffected (the migration's post-check read only them).
--
-- What it changes: security.layer4_decision_groups_v1 works out the study-load groups from the open readings first (provider, normalised
-- quote, model answer) and then groups them, so what the model said per group is an aggregate. The AER branch is unchanged. A post-check now
-- reads both kinds.
-- Nothing is dropped or deleted. G3 untouched.
-- Replaces: the study-load branch of security.layer4_decision_groups_v1 (migration 20261118162000).
-- Retires: nothing.

create or replace function security.layer4_decision_groups_v1(p_kind text)
returns table(group_key text, provider_id uuid, provider text, label text, refs text[], n int, detail jsonb)
language plpgsql stable security definer set search_path to '' as $f$
declare v_min int := security.pipeline_num_v1('layer4.group_min_items', 2)::int;
begin
  if p_kind = 'aer_review' then
    return query
    with p as (select i.id, i.created_at, i.proposed_value->>'url' url, co.provider_id
                 from pipeline.layer4_review_items i
                 join pipeline.layer4_item_readiness x on x.item_id = i.id
                 join catalogue.courses co on co.id = i.entity_id
                where i.status = 'pending' and i.field_code = 'course_entry_first_read'
                  and security.aer_e13_class_v1(x.gate) = 'shared_page' and nullif(i.proposed_value->>'url', '') is not null),
         l as (select distinct on (a.review_item_id) a.review_item_id, a.reason_code
                 from pipeline.aer_machine_admissions a join p on p.id = a.review_item_id
                where a.withdrawn_at is null order by a.review_item_id, a.id desc),
         ok as (select p.* from p left join l on l.review_item_id = p.id
                 where coalesce(l.reason_code, '') not in ('audit_sample', 'identity_not_admitted', 'no_bound_page'))  -- never grouped
    select 'aer:' || ok.provider_id || ':' || md5(ok.url), ok.provider_id, min(coalesce(pr.display_name, pr.canonical_name)), ok.url,
           array_agg(ok.id::text order by ok.created_at, ok.id), count(*)::int,
           jsonb_build_object('why', 'The stored page is shared with other programmes; one confirmation of what it says for each programme settles the group',
                              'oldest', min(ok.created_at))
      from ok join catalogue.providers pr on pr.id = ok.provider_id
     group by ok.provider_id, ok.url
    having count(*) >= v_min
     order by count(*) desc, min(ok.created_at);
  elsif p_kind = 'boost_study_load' then
    return query
    with o as (select r.id, r.provider_id, r.opened_at, btrim(r.answer->>'quote') quote, lower(btrim(r.answer->>'quote')) q,
                      coalesce(r.answer->>'study_load', 'none') said
                 from pipeline.boost_study_load_reviews r
                where r.status = 'open' and nullif(btrim(r.answer->>'quote'), '') is not null),
         s as (select o.provider_id, o.q, o.said, count(*) c from o group by 1, 2, 3)
    select 'sl:' || o.provider_id || ':' || md5(o.q), o.provider_id, min(coalesce(pr.display_name, pr.canonical_name)), min(o.quote),
           array_agg(o.id::text order by o.opened_at, o.id), count(*)::int,
           jsonb_build_object('model_said', (select coalesce(jsonb_object_agg(s.said, s.c), '{}'::jsonb) from s where s.provider_id = o.provider_id and s.q = o.q),
                              'oldest', min(o.opened_at))
      from o join catalogue.providers pr on pr.id = o.provider_id
     group by o.provider_id, o.q
    having count(*) >= v_min
     order by count(*) desc, min(o.opened_at);
  end if;
end $f$;
comment on function security.layer4_decision_groups_v1(text) is
  'CF-247 18 Nov 2026 (Platform Admin 13:02): groups for a grouped Layer 4 decision: AER items held only for a shared stored page (provider and page; audit samples, identity and page problems never grouped) and refused Boost study loads (provider and quote).';
revoke all on function security.layer4_decision_groups_v1(text) from public, anon, authenticated;

do $e$
begin
  perform count(*) from security.layer4_decision_groups_v1('boost_study_load');
  perform count(*) from security.layer4_decision_groups_v1('aer_review');
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
end $e$;
