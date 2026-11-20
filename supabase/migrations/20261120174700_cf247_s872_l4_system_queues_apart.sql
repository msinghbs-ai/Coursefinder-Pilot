-- CF-247 S1-RM-Design s872 (Platform Admin 20 Nov 2026 17:13 AEDT, "universal minimum-effort Layer 4 overhaul across all 19 registered queues"):
-- Layer 4 Review's rule rail separates Human Action Required from System Queues (Auto-Recovering) in every queue, not only entry requirements (s870).
-- The job layer4-groups already files every waiting item: A settled by an existing rule, B technical recovery (the platform is recovering it),
-- C ready for a decision, D information only a person can give. The rule groups (security.layer4_rule_groups_v1, s837/s870) now key every A or B item
-- of any queue sys~<key> with recovery true (entry requirements keep their aerb: keys), so a person sees what they can decide apart from what the
-- platform is working on. Live 20 Nov 17:40 AEDT: site down 149, nothing ready 317, course links 24, onboarding failed 1, entry requirements 272.
-- Numbering: spec s872 (s836-s839 and s870-s871 are S1-RM-Design's and used; s840-s869 other lanes; s880 S1-Build); migration 20261120174700, above the
-- live head 20261120172000 and every migration in an open pull request (S1-RM-Design's 15:25 window ended at 20261120145500, which is used).
-- Objects (no new public function, table or view): security.layer4_rule_groups_v1 replaced (same signature; md5-guarded: 8e649c38, read live after s870).
-- G1: no job. G2: no value. G3: security.consumer_api_check_v1() read before and after (75 functions, 48 relations). Spend: none. Nothing dropped or deleted.
-- Replaces: the rule groups of s870 (only entry requirements kept apart).
-- Retires: nothing.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(replace(pg_get_functiondef('security.layer4_rule_groups_v1(text,jsonb,jsonb,integer)'::regprocedure), chr(13), '')) <> '8e649c381711b259f93382e5f4764f87' then
    raise exception 'pre-check: security.layer4_rule_groups_v1 changed since it was read';
  end if;
end $g$;

create or replace function security.layer4_rule_groups_v1(p_action text, p_args jsonb, p_kinds jsonb, p_target int)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare v_kind text := nullif(p_args->>'kind', ''); v_prov uuid := nullif(p_args->>'provider_id', '')::uuid;
        v_max int := security.pipeline_num_v1('layer4.rule_group_refs_max', 500)::int;
        v_batch int := security.pipeline_num_v1('layer4.rule_batch_max', 50)::int;
        v_refs text[]; v_aer jsonb := '[]'::jsonb; t0 timestamptz := clock_timestamp(); v_out jsonb; v_rank int; v_ids uuid[]; v_rr jsonb := '{}'::jsonb;
begin
  if p_action not in ('rule_groups', 'rule_group_items', 'aer_det_reread_check', 'aer_det_reread', 'aer_page_fetch') then raise exception 'INVALID_INPUT: unknown action' using errcode = '22023'; end if;
  -- s870 (Platform Admin 20 Nov 2026 16:28): a stale partial AER read is re-read from its stored copy by the deterministic reader ($0), or a course with no
  -- stored page goes on the Course page needed list. Checking is open to a Curator; acting is the Platform Admin's, as every AER decision (A3).
  if p_action in ('aer_det_reread_check', 'aer_det_reread', 'aer_page_fetch') then
    v_rank := security.current_role_rank();
    if p_action <> 'aer_det_reread_check' and v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if p_action <> 'aer_det_reread_check' and length(btrim(coalesce(p_args->>'reason', ''))) < 5 then raise exception 'INVALID_INPUT: a reason of at least 5 characters is needed' using errcode = '22023'; end if;
    v_ids := array(select y.x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p_args->'refs') = 'array' then p_args->'refs' else '[]'::jsonb end) with ordinality y(x, n)
                    where y.x ~ '^[0-9a-f-]{36}$' order by y.n limit v_batch);
    return security.aer_det_reread_v1(case p_action when 'aer_det_reread_check' then 'check' when 'aer_det_reread' then 'apply' else 'fetch' end, v_ids, btrim(coalesce(p_args->>'reason', '')),
             coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text, 'unknown'));
  end if;
  if v_kind is null then raise exception 'INVALID_INPUT: choose a kind' using errcode = '22023'; end if;
  -- a registered (hook) kind has its own page reader: the screen shows its list as before
  if not (security.layer4_inbox_kinds_v1() ? v_kind) then
    return jsonb_build_object('kind', v_kind, 'built_in', false, 'total', null, 'groups', '[]'::jsonb, 'items', '[]'::jsonb);
  end if;

  if p_action = 'rule_group_items' then
    v_refs := array(select y.x from jsonb_array_elements_text(case when jsonb_typeof(p_args->'refs') = 'array' then p_args->'refs' else '[]'::jsonb end) with ordinality y(x, n)
                     order by y.n limit v_batch);
    if v_kind = 'aer_review' then  -- s870: whether each card can be re-read from its stored copy ($0), and if not, why
      v_rr := coalesce(security.aer_det_reread_v1('check', array(select r::uuid from unnest(v_refs) r where r ~ '^[0-9a-f-]{36}$'), '', '')->'items', '{}'::jsonb);
    end if;
    return (with b as (select i.kind, i.ref, i.provider_id, coalesce(p.display_name, p.canonical_name) provider, i.subject, i.why, i.suggestion, i.created_at, i.detail
                         from security.layer4_inbox_items_v2(null, v_kind, array(select v_kind || ':' || r from unnest(v_refs) r), true) i
                         left join catalogue.providers p on p.id = i.provider_id
                        where coalesce(array_length(v_refs, 1), 0) > 0)
      select jsonb_build_object('kind', v_kind, 'built_in', true, 'asked', coalesce(array_length(v_refs, 1), 0), 'batch_max', v_batch,
               'items', coalesce(jsonb_agg(jsonb_build_object('kind', b.kind, 'ref', b.ref, 'provider_id', b.provider_id, 'provider', b.provider, 'subject', b.subject,
                          'why', b.why, 'suggestion', b.suggestion, 'created_at', b.created_at, 'late', b.created_at < now() - make_interval(days => p_target),
                          'detail', b.detail, 'o', (p_kinds->b.kind->>'order')::int) || case when v_rr ? b.ref then jsonb_build_object('reread', v_rr->b.ref) else '{}'::jsonb end
                        order by array_position(v_refs, b.ref)), '[]'::jsonb),
               'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int)
        from b);
  end if;

  if v_kind = 'aer_review' then v_aer := coalesce(security.layer4_aer_hold_reasons_v1('{}'::jsonb)->'reasons', '[]'::jsonb); end if;
  with i as (
         select r.ref, r.created_at, r.why,
                case when v_kind = 'provider_description' then coalesce(r.detail->'machine'->>'reason_code', r.detail->'proposed'->>'held_rule', '') end code,
                regexp_replace(regexp_replace(btrim(coalesce(r.why, '')), '([.;])\s.*$', '\1'), '[.;:]+$', '') clause,
                exists (select 1 from pipeline.layer4_item_groups x where x.kind = v_kind and x.ref = r.ref and x.grp in ('A', 'B') and x.state = 'waiting') sys  -- s872: settled by a rule or recovering by itself
           from security.layer4_inbox_items_v2(v_prov, v_kind, null, v_kind = 'provider_description') r),
       k as (
         select i.*,
                case when v_kind = 'provider_description' then 'cd:' || (case
                       when i.code = '' then 'first_provider_sample'
                       when i.code = 'policy_refused_word' then 'banned_word'
                       when i.code in ('identity_margin_thin', 'identity_not_allowed') then 'identity_margin_thin'
                       when i.code = 'binding_ambiguous' then 'binding_ambiguous'
                       when i.code = 'check_sentence_count' then 'sentence_count_over_2'
                       when i.code = 'check_length' then 'length'
                       when i.code like 'policy\_%' or i.code in ('check_unsupported_claim', 'check_unsupported_marketing') then 'boilerplate_detected'
                       when i.code in ('check_quote_not_on_page', 'check_unsupported_sentence', 'check_copied_sentence', 'source_recheck_failed') then 'quote_mismatch'
                       when i.code in ('evidence_moved', 'page_url_changed', 'reading_other_evidence') then 'evidence_moved'
                       when i.code = 'wrong_page_kind' then 'wrong_page_kind'
                       when i.code like 'duplicate\_%' or i.code = 'check_duplicate_other_course' then 'duplicate'
                       when i.code like 'rejected\_before%' or i.code = 'withdrawn_awaiting_person' then 'rejected_before'
                       else 'other' end)
                     when v_kind = 'aer_review' then (case when exists (select 1 from pipeline.layer4_item_groups x where x.kind = 'aer_review' and x.ref = i.ref and x.grp = 'B' and x.state = 'waiting')
                                                            then 'aerb:' else 'aer:' end) || coalesce(substring(i.why from 'did not admit this: ([a-z_]+)'), 'other')
                     else v_kind || ':' || lower(i.clause) end gkey,
                i.sys
           from i),
       k2 as (select (case when k.sys and v_kind <> 'aer_review' then 'sys~' else '' end) || k.gkey gkey, k.created_at, k.ref, k.clause from k),
       g as (
         select k.gkey, count(*) n, min(k.created_at) oldest, count(*) filter (where k.created_at < now() - make_interval(days => p_target)) late,
                (array_agg(k.clause order by k.created_at, k.ref))[1] clause,
                (array_agg(k.ref order by k.created_at, k.ref))[1:v_max] refs
           from k2 k group by k.gkey)
  select jsonb_build_object('kind', v_kind, 'built_in', true, 'provider_id', v_prov, 'total', coalesce(sum(g.n), 0), 'refs_max', v_max, 'batch_max', v_batch,
           'groups', coalesce(jsonb_agg(jsonb_build_object('key', g.gkey, 'n', g.n, 'oldest', g.oldest, 'late', g.late,
                       'label', case when v_kind = 'aer_review' then coalesce((select r->>'label' from jsonb_array_elements(v_aer) r where (r->>'code') = regexp_replace(g.gkey, '^aerb?:', '') limit 1),
                                                   initcap(replace(regexp_replace(g.gkey, '^aerb?:', ''), '_', ' ')))
                                     when v_kind = 'provider_description' then null else nullif(g.clause, '') end,
                       'refs', to_jsonb(g.refs), 'recovery', g.gkey like 'aerb:%' or g.gkey like 'sys~%') order by g.n desc, g.gkey), '[]'::jsonb),
           'as_at', now(), 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int)
    into v_out from g;
  return v_out;
end $function$;

revoke all on function security.layer4_rule_groups_v1(text, jsonb, jsonb, int) from public, anon, authenticated;
comment on function security.layer4_rule_groups_v1(text, jsonb, jsonb, int) is 'CF-247 s837/s870/s872: Layer 4 Review rule groups across the whole queue of one built-in kind (rule_groups), keyed apart when the item is settled by a rule or recovering by itself (sys~, aerb:); the cards of up to layer4.rule_batch_max refs (rule_group_items); the AER stored-copy re-read actions. Reached through public.admin_layer4_inbox.';

do $c$
declare v_g jsonb; v_sys int := 0; v_k text;
begin
  for v_k in select unnest(array['site_down', 'nothing_ready', 'course_link', 'aer_review']) loop
    v_g := security.layer4_rule_groups_v1('rule_groups', jsonb_build_object('kind', v_k), security.layer4_inbox_hooks_v1()->'kinds', 7);
    if (v_g->>'total')::int <> (select count(*) from security.layer4_inbox_items_v2(null, v_k, null, false)) then raise exception 'post-check: % groups do not add up to the queue', v_k; end if;
    v_sys := v_sys + coalesce((select sum((x->>'n')::int) from jsonb_array_elements(v_g->'groups') x where (x->>'recovery')::boolean), 0);
  end loop;
  raise notice 'CF-247 s872: % items in system groups across site_down, nothing_ready, course_link and aer_review', v_sys;
end $c$;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API changed: %', v;
  end if;
end $g$;
