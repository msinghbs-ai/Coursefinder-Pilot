-- CF-247 Layer 4 › Inbox › Grid: grouped decisions with one reason (S2-Build, Platform Admin 18 Nov 2026 13:02, after the S2 - BOOST
-- audit in admin CURRENT-STATE 12:25 and Pilot #1267).
--
-- What was read live (18 Nov 2026 13:20 AEDT)
--   * AER course entry items waiting (course_entry_first_read): 2,578. By the completeness gate class (security.aer_e13_class_v1): dropped
--     printed requirements no row covers 1,551, complete 556, stored page shared with other programmes 237, row-level 130, row limit 104.
--     The 1,874 in the audit's "shared page" line counts the incomplete reads with them; an incomplete read is not a candidate for a grouped
--     approval (approving it would admit a read that dropped requirements printed on the page), so only the shared-page class is grouped:
--     237 items on 172 pages, 125 of them in 60 groups of two or more (provider and the same stored page). 2 of the 237 are audit samples.
--   * Refused Boost study loads waiting: 400; 252 of them fall in 48 groups of two or more with the same quote at the same provider
--     (largest 29); 22 have no quote.
--   * Decision ranks stay as they are: AER Approve and Reject are the Platform Admin's (rank 6); the study-load choices need a Pipeline
--     Operator (rank 4). A Curator sees the groups and what each would decide; the decision is taken at the rank the single item needs.
--
-- What it changes
--   1. security.layer4_decision_groups_v1(kind): the groups of a groupable kind, worked out on the server: AER items whose only hold is the
--      shared stored page, grouped by provider and page; refused study loads grouped by provider and the same quote. Never grouped: the 5%
--      AER audit sample (latest machine outcome audit_sample), an identity not admitted, no bound page, campus postcodes, host problems and
--      every other kind.
--   2. public.admin_layer4_group_decide_read_v1: the groups of a kind with their items, the choices allowed for a group and the rank each needs.
--   3. public.admin_layer4_group_decide_v1: one choice and one reason for every item of a group, typed confirmation ("APPROVE 4"), only when
--      the items sent are exactly the group as it stands now (a changed group is refused, so nothing stale is decided), at most
--      layer4.group_decide_max items. Each item is decided through public.admin_layer4_inbox, so every per-item rule, idempotency check and
--      audit row is the single decision's own; the group is logged in pipeline.layer4_mass_operations.
--   Decision A2 (AER items are never decided in a batch, 30 Oct 2026) is amended by the Platform Admin's direction of 18 Nov 2026 13:02 for
--   the shared-page groups only; layer4_batch_decide_v1 still refuses AER items.
-- Nothing is dropped or deleted. G3 untouched.
-- Replaces: one-at-a-time decisions for these two grouped cases (the single-item path is unchanged and still available).
-- Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer4.group_decide_max', 'Layer 4: items in one grouped decision at most',
  'A grouped decision on Layer 4 › Inbox › Grid decides every item of one group with one reason. Larger groups are refused; decide them in parts on By kind.',
  'number', '50'::jsonb, 2, 200, 'items', 795, 'Platform Admin 18 Nov 2026 13:02 (S2-Build): grouped bulk decisions on the Phase 5 grid', 'Layer 4', 'public.admin_layer4_group_decide_v1'),
 ('pipeline', 'layer4.group_min_items', 'Layer 4: items a group needs to be offered',
  'A group on Layer 4 › Inbox › Grid › Grouped decisions is offered only when it holds at least this many waiting items; smaller ones are decided one at a time.',
  'number', '2'::jsonb, 2, 50, 'items', 796, 'Platform Admin 18 Nov 2026 13:02 (S2-Build)', 'Layer 4', 'security.layer4_decision_groups_v1')
on conflict (toolset_key, key) do nothing;

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
    select 'sl:' || r.provider_id || ':' || md5(lower(btrim(r.answer->>'quote'))), r.provider_id, min(coalesce(pr.display_name, pr.canonical_name)),
           min(btrim(r.answer->>'quote')), array_agg(r.id::text order by r.opened_at, r.id), count(*)::int,
           jsonb_build_object('model_said', (select coalesce(jsonb_object_agg(z.v, z.c), '{}'::jsonb) from (select coalesce(r2.answer->>'study_load', 'none') v, count(*) c
                                              from pipeline.boost_study_load_reviews r2
                                             where r2.status = 'open' and r2.provider_id = r.provider_id and lower(btrim(r2.answer->>'quote')) = lower(btrim(r.answer->>'quote')) group by 1) z),
                              'oldest', min(r.opened_at))
      from pipeline.boost_study_load_reviews r join catalogue.providers pr on pr.id = r.provider_id
     where r.status = 'open' and nullif(btrim(r.answer->>'quote'), '') is not null
     group by r.provider_id, lower(btrim(r.answer->>'quote'))
    having count(*) >= v_min
     order by count(*) desc, min(r.opened_at);
  end if;
end $f$;
comment on function security.layer4_decision_groups_v1(text) is
  'CF-247 18 Nov 2026 (Platform Admin 13:02): groups for a grouped Layer 4 decision: AER items held only for a shared stored page (provider and page; audit samples, identity and page problems never grouped) and refused Boost study loads (provider and quote).';
revoke all on function security.layer4_decision_groups_v1(text) from public, anon, authenticated;

create or replace function public.admin_layer4_group_decide_read_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_kind text := coalesce(nullif(p_args->>'kind', ''), 'aer_review'); v_rank int := coalesce(security.current_role_rank(), 0);
        v_choices jsonb;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator or above required' using errcode = '42501'; end if;
  if v_kind not in ('aer_review', 'boost_study_load') then raise exception 'this kind is decided one item at a time'; end if;
  v_choices := (select coalesce(jsonb_agg(jsonb_build_object('key', c->>'key', 'label', coalesce(c->>'label', c->>'key'), 'rank', coalesce((c->>'rank')::int, 4)) order by ord), '[]'::jsonb)  -- fixed: the Inbox's default rank for a value choice
                  from jsonb_array_elements(security.layer4_inbox_hooks_v1()->'kinds'->v_kind->'choices') with ordinality t(c, ord)
                 where c->>'key' = any (case v_kind when 'aer_review' then array['approve', 'reject'] else array['accept_full_time', 'accept_part_time', 'accept_both', 'not_stated', 'dismiss'] end));
  return jsonb_build_object('kind', v_kind, 'rank', v_rank, 'choices', v_choices,
    'max_items', security.pipeline_num_v1('layer4.group_decide_max', 50)::int,
    'groups', (select coalesce(jsonb_agg(jsonb_build_object('group_key', g.group_key, 'provider_id', g.provider_id, 'provider', g.provider, 'label', g.label,
                                 'refs', to_jsonb(g.refs), 'n', g.n, 'detail', g.detail)), '[]'::jsonb)
                 from security.layer4_decision_groups_v1(v_kind) g),
    'never_grouped', 'AER audit samples, identity not admitted, no bound page, incomplete reads, campus postcodes, host problems and every other kind are decided one at a time.');
end $f$;
comment on function public.admin_layer4_group_decide_read_v1(jsonb) is
  'CF-247 18 Nov 2026 (Platform Admin 13:02): Layer 4 › Inbox › Grid › Grouped decisions: the groups of a groupable kind, their items and the choices allowed.';
revoke all on function public.admin_layer4_group_decide_read_v1(jsonb) from public, anon;
grant execute on function public.admin_layer4_group_decide_read_v1(jsonb) to authenticated;

create or replace function public.admin_layer4_group_decide_v1(p_args jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_kind text := p_args->>'kind'; v_key text := p_args->>'group_key'; v_choice text := p_args->>'choice';
        v_reason text := btrim(coalesce(p_args->>'reason', '')); v_confirm text := btrim(coalesce(p_args->>'confirm', ''));
        v_sent text[] := array(select x from jsonb_array_elements_text(coalesce(p_args->'refs', '[]'::jsonb)) x order by x);
        v_rank int := coalesce(security.current_role_rank(), 0); v_need int; v_max int := security.pipeline_num_v1('layer4.group_decide_max', 50)::int;
        g record; v_ref text; v_r jsonb; v_out jsonb := '[]'::jsonb; v_ok int := 0; v_bad int := 0; v_op uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if v_kind not in ('aer_review', 'boost_study_load') then raise exception 'this kind is decided one item at a time'; end if;
  if v_choice is null or not (v_choice = any (case v_kind when 'aer_review' then array['approve', 'reject'] else array['accept_full_time', 'accept_part_time', 'accept_both', 'not_stated', 'dismiss'] end)) then
    raise exception 'this choice cannot be used for a group';
  end if;
  v_need := (select coalesce((c->>'rank')::int, 4) from jsonb_array_elements(security.layer4_inbox_hooks_v1()->'kinds'->v_kind->'choices') c where c->>'key' = v_choice);  -- fixed: the Inbox's default rank
  if v_rank < v_need then raise exception 'your role cannot make this choice (rank % needed, as for one item)', v_need using errcode = '42501'; end if;
  if length(v_reason) < 8 then raise exception 'give a reason of at least 8 characters (kept with every decision)'; end if;
  select * into g from security.layer4_decision_groups_v1(v_kind) x where x.group_key = v_key;
  if g.group_key is null then raise exception 'this group is no longer waiting; refresh'; end if;
  if (select array_agg(x order by x) from unnest(g.refs) x) is distinct from v_sent then
    raise exception 'the group has changed since it was shown (% now waiting); refresh and check it again', g.n;
  end if;
  if g.n > v_max then raise exception 'the group holds % items, more than % (layer4.group_decide_max); decide it in parts on By kind', g.n, v_max; end if;
  if v_confirm <> upper(v_choice) || ' ' || g.n then raise exception 'type % to confirm', upper(v_choice) || ' ' || g.n; end if;
  foreach v_ref in array g.refs loop
    begin
      v_r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'reason', v_reason || ' (grouped decision: ' || g.n || ' items, ' || g.label || ')'));
      if coalesce((v_r->>'ok')::boolean, true) then v_ok := v_ok + 1; else v_bad := v_bad + 1; end if;
      v_out := v_out || jsonb_build_object('ref', v_ref, 'ok', coalesce((v_r->>'ok')::boolean, true), 'returns', v_r->>'returns', 'request', v_r->>'request');
    exception when others then
      v_bad := v_bad + 1;
      v_out := v_out || jsonb_build_object('ref', v_ref, 'ok', false, 'error', left(sqlerrm, 300));
    end;
  end loop;
  insert into pipeline.layer4_mass_operations(target_kind, action, actor_id, group_key, reason, before_count, affected_count, result, change_control_ref)
  values ('review_batch', v_choice, auth.uid(),
          jsonb_build_object('grouped', true, 'kind', v_kind, 'group_key', v_key, 'provider_id', g.provider_id, 'label', g.label, 'refs', to_jsonb(g.refs),
                             'decision', 'Platform Admin 18 Nov 2026 13:02 (amends A2 for shared-page groups only)'),
          v_reason, g.n, v_ok, jsonb_build_object('items', v_out, 'decided', v_ok, 'not_decided', v_bad), 'CF-CHG-20260915-247')
  returning id into v_op;
  return jsonb_build_object('ok', v_bad = 0, 'decided', v_ok, 'not_decided', v_bad, 'items', v_out, 'mass_operation_id', v_op);
end $f$;
comment on function public.admin_layer4_group_decide_v1(jsonb) is
  'CF-247 18 Nov 2026 (Platform Admin 13:02): one choice and one reason for every item of a Layer 4 decision group, each decided through admin_layer4_inbox; the group is logged in layer4_mass_operations.';
revoke all on function public.admin_layer4_group_decide_v1(jsonb) from public, anon;
grant execute on function public.admin_layer4_group_decide_v1(jsonb) to authenticated;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, 'Layer 4', 'Layer 4 Inbox', v.purpose, 'active', '20261118162000'
  from (values
    ('function', 'security.layer4_decision_groups_v1', 'Groups for a grouped Layer 4 decision (AER shared-page items by provider and page; refused study loads by provider and quote)'),
    ('function', 'public.admin_layer4_group_decide_read_v1', 'Layer 4 › Inbox › Grid › Grouped decisions: groups, items and allowed choices'),
    ('function', 'public.admin_layer4_group_decide_v1', 'Layer 4 › Inbox › Grid › Grouped decisions: one choice and reason for a whole group, each item through admin_layer4_inbox')) v(kind, name, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

do $e$
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
  if exists (select 1 from security.layer4_decision_groups_v1('aer_review') g, unnest(g.refs) r
               join lateral (select a.reason_code from pipeline.aer_machine_admissions a where a.review_item_id = r::uuid and a.withdrawn_at is null order by a.id desc limit 1) l on true
              where l.reason_code = 'audit_sample') then
    raise exception 'an AER audit sample was grouped';
  end if;
end $e$;
