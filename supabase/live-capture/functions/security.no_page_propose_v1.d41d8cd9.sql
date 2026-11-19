CREATE OR REPLACE FUNCTION security.no_page_propose_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_sample int := security.pipeline_num_v1('bind.no_page_sample', 5)::int; v_item uuid; v_first int := 0; v_auto int := 0; v_conj int := 0;
        v_passes int := security.pipeline_num_v1('bind.no_page_after_passes', 2)::int; v_scope int; v_parent text;
begin
  v_scope := security.bind_match_scope_refresh_v1();
  if security.pipeline_num_v1('bind.no_page_on', 0) < 1 then return jsonb_build_object('on', false, 'scope', v_scope); end if;
  if to_regclass('pg_temp._np_cand') is not null then drop table pg_temp._np_cand; end if;  -- a second run in one transaction
  create temp table _np_cand on commit drop as
    with pv as (select u.provider_id, count(*) inv from pipeline.coverage_provider_urls u group by 1)
    select c.id course_id, c.provider_id, c.canonical_title t, c.course_code code, security.conjoint_shape_v1(c.canonical_title) conj, d.mapped_at inv_at,
           coalesce(pv.inv, 0) inv
      from catalogue.courses c join pipeline.coverage_provider_discovery d on d.provider_id = c.provider_id left join pv on pv.provider_id = c.provider_id
     where c.lifecycle_status = 'active'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       and not exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')
       and not exists (select 1 from pipeline.coverage_course_pages pp where pp.course_id = c.id and pp.status = 'bound')
       and not exists (select 1 from pipeline.course_no_page n where n.course_id = c.id and n.state <> 'reopened')
       and d.status = 'mapped' and d.mapped_at > now() - make_interval(days => security.pipeline_num_v1('bind.map_refresh_days', 30)::int)
       and (security.conjoint_shape_v1(c.canonical_title)
            or (select count(*) = v_passes and bool_and(q.state in ('none', 'no_candidates'))
                  from (select q2.state from pipeline.coverage_ai_match q2 where q2.course_id = c.id order by q2.created_at desc limit v_passes) q))
       and c.provider_id in (select x.provider_id from (
             select c2.provider_id, count(*) n from catalogue.courses c2 where c2.lifecycle_status = 'active'
               and not exists (select 1 from catalogue.course_links l2 where l2.course_id = c2.id and l2.link_type = 'official_course' and l2.status = 'active')
             group by 1 order by 2 desc limit security.pipeline_num_v1('bind.no_page_providers_per_run', 40)::int * 10) x);

  -- universities first (Platform Admin 25 Oct 22:34: "top tiered universities ... finish them first"), then by courses without a page
  for r in select cd.provider_id, cd.conj from _np_cand cd join catalogue.providers p on p.id = cd.provider_id left join ref.provider_types pt on pt.id = p.provider_type_id
            group by cd.provider_id, cd.conj, pt.code order by (pt.code = 'university') desc nulls last, count(*) desc loop
    -- at most bind.no_page_first_runs_per_run new first runs a run, so Layer 4 is never flooded (universities come first)
    if ((v_first + v_conj) >= security.pipeline_num_v1('bind.no_page_first_runs_per_run', 10)
        or (select count(*) from pipeline.layer4_review_items li where li.status = 'pending' and li.field_code in ('no_page_first_run', 'conjoint_rule_first_run'))
           >= security.pipeline_num_v1('bind.no_page_pending_max', 60))  -- SP-1.1: never more than this many waiting for a person
       and not exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = case when r.conj then 'conjoint' else 'no_page' end) then
      continue;
    end if;
    if r.conj then
      -- conjoint: one rule per provider, decided in Layer 4
      if not exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = 'conjoint') then
        select u.url into v_parent from pipeline.coverage_provider_urls u where u.provider_id = r.provider_id
           and u.url ~* '(conjoint|double[-_]?degree|combined[-_]?degree|dual[-_]?degree)' order by length(u.url) limit 1;
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('provider', r.provider_id, 'conjoint_rule_first_run', jsonb_build_object('conjoint_courses_without_page', (select count(*) from _np_cand x where x.provider_id = r.provider_id and x.conj)),
                jsonb_build_object('parent_url', v_parent, 'mode', case when v_parent is null then 'components' else 'parent_page' end,
                  'sample', (select jsonb_agg(jsonb_build_object('course_id', x.course_id, 'title', x.t, 'code', x.code)) from (select * from _np_cand x2 where x2.provider_id = r.provider_id and x2.conj order by x2.t limit v_sample) x)),
                jsonb_build_object('source', 'SP-1 conjoint rule', 'inventory', (select max(x.inv) from _np_cand x where x.provider_id = r.provider_id)), '{}'::jsonb, 'pending',
                'Conjoint or double degrees: decide once for this provider whether they share its conjoint page (edit to correct the page) or have none; approved, they leave the course search',
                'CF-CHG-20260915-247')
        returning id into v_item;
        insert into pipeline.no_page_trust(provider_id, kind, state, parent_url, review_item_id) values (r.provider_id, 'conjoint', 'first_run', v_parent, v_item);
        insert into pipeline.course_no_page(course_id, provider_id, kind, state, basis, inventory_at, review_item_id)
        select x.course_id, x.provider_id, 'conjoint', 'proposed', jsonb_build_object('rule', 'conjoint shape', 'parent_url', v_parent), x.inv_at, v_item
          from _np_cand x where x.provider_id = r.provider_id and x.conj
        on conflict (course_id) do nothing;
        v_conj := v_conj + 1;
      elsif exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = 'conjoint' and t.state = 'trusted') then
        insert into pipeline.course_no_page(course_id, provider_id, kind, state, basis, inventory_at, decided_at)
        select x.course_id, x.provider_id, 'conjoint', 'conjoint', jsonb_build_object('rule', 'conjoint shape, provider rule approved'), x.inv_at, now()
          from _np_cand x where x.provider_id = r.provider_id and x.conj
        on conflict (course_id) do update set state = 'conjoint', kind = 'conjoint', inventory_at = excluded.inventory_at, decided_at = now(), updated_at = now()
          where pipeline.course_no_page.state = 'reopened';
      end if;
    else
      if not exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = 'no_page') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('provider', r.provider_id, 'no_page_first_run', jsonb_build_object('courses_proposed', (select count(*) from _np_cand x where x.provider_id = r.provider_id and not x.conj)),
                jsonb_build_object('sample', (select jsonb_agg(jsonb_build_object('course_id', x.course_id, 'title', x.t, 'code', x.code)) from (select * from _np_cand x2 where x2.provider_id = r.provider_id and not x2.conj order by md5(x2.course_id::text) limit v_sample) x),
                                   'inventory_addresses', (select max(x.inv) from _np_cand x where x.provider_id = r.provider_id), 'inventory_at', (select max(x.inv_at) from _np_cand x where x.provider_id = r.provider_id),
                                   'how', 'Approve if none of the sample courses has its own page on the provider''s site. If any has one, edit and approve with {"has_page_course_ids": [...]} (and the page address in the note); the provider is trusted only at the 60% rule.'),
                jsonb_build_object('source', 'SP-1 no page published by the provider', 'ai_passes', v_passes), '{}'::jsonb, 'pending',
                'No page published by the provider: check the sample once; trusted at the 60% rule, then later cases are recorded without a person (re-opened by any page found later)',
                'CF-CHG-20260915-247')
        returning id into v_item;
        insert into pipeline.no_page_trust(provider_id, kind, state, review_item_id) values (r.provider_id, 'no_page', 'first_run', v_item);
        insert into pipeline.course_no_page(course_id, provider_id, kind, state, basis, inventory_at, review_item_id)
        select x.course_id, x.provider_id, 'no_page', 'proposed', jsonb_build_object('ai_passes', v_passes, 'inventory_addresses', x.inv, 'sample', true), x.inv_at, v_item
          from (select * from _np_cand x2 where x2.provider_id = r.provider_id and not x2.conj order by md5(x2.course_id::text) limit v_sample) x
        on conflict (course_id) do nothing;
        v_first := v_first + 1;
      elsif exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = 'no_page' and t.state = 'trusted') then
        insert into pipeline.course_no_page(course_id, provider_id, kind, state, basis, inventory_at, decided_at)
        select x.course_id, x.provider_id, 'no_page', 'confirmed_auto', jsonb_build_object('ai_passes', v_passes, 'inventory_addresses', x.inv, 'trusted_provider', true), x.inv_at, now()
          from _np_cand x where x.provider_id = r.provider_id and not x.conj
        on conflict (course_id) do update set state = 'confirmed_auto', kind = 'no_page', basis = excluded.basis, inventory_at = excluded.inventory_at, decided_at = now(), updated_at = now()
          where pipeline.course_no_page.state = 'reopened';
      end if;
    end if;
  end loop;
  select count(*) into v_auto from pipeline.course_no_page where state = 'confirmed_auto' and decided_at > now() - interval '5 minutes';  -- fixed: this run
  return jsonb_build_object('on', true, 'scope', v_scope, 'first_runs_no_page', v_first, 'first_runs_conjoint', v_conj, 'recorded_auto', v_auto);
end $function$
