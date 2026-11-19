CREATE OR REPLACE FUNCTION public.admin_layer4_inbox(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_hooks jsonb; v_kinds jsonb; v_kind text; v_ref text; v_choice text; v_reason text; v_value text; v_pid uuid;
        v_target int := security.pipeline_num_v1('layer4.target_days', 7)::int; v_actor text; v_lim int; v_off int; v_q text; v_r jsonb; v_c jsonb; v_det jsonb; v_out jsonb; v_ids uuid[]; v_event bigint;
        -- CF-247 Layer 4 Inbox performance (4 Nov 2026): counts, pages, lazy detail and kind hooks
        v_hc jsonb; v_prov uuid; v_fkind text; v_bkind text; v_has boolean; v_ao int; v_aat timestamptz; v_ak text; v_ar text; v_h jsonb; v_hp jsonb; v_hargs jsonb;
        v_total bigint := 0; v_before bigint := 0; v_hitems jsonb := '[]'; v_keys text[]; v_fn text; v_np bigint; v_ho int; v_cd_n int; v_cd_ok int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  v_actor := coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text);
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_lim := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200); v_off := greatest(coalesce((p_args->>'offset')::int, 0), 0);  -- fixed: page size bounds
  v_q := nullif(btrim(p_args->>'q'), '');
  v_hooks := security.layer4_inbox_hooks_v1(); v_kinds := v_hooks->'kinds';
  v_fkind := nullif(p_args->>'kind', '');
  -- a built-in kind is read from the item list; a registered kind from its hooks
  v_bkind := case when v_fkind is null or security.layer4_inbox_kinds_v1() ? v_fkind then v_fkind else '-' end;

  if p_action = 'summary' then
    -- counts only: no item is built (Platform Admin 4 Nov 2026 06:53 §1, bounded first queries)
    v_hc := security.layer4_inbox_hook_counts_v1(v_hooks, null);
    return (with b as (select * from security.layer4_inbox_counts_v1(v_target)),
                 h as (select x->>'kind' kind, (x->>'n')::bigint n, (x->>'oldest')::timestamptz oldest, (x->>'late')::bigint late, x->'by_provider' bp from jsonb_array_elements(v_hc->'items') x),
                 k as (select kind, sum(n)::bigint n, min(oldest) oldest, sum(late)::bigint late from b group by 1 union all select kind, n, oldest, late from h where n > 0)
      select jsonb_build_object('kinds', v_kinds, 'target_days', v_target, 'rank', v_rank,
        'by_kind', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object('n', k.n, 'oldest', k.oldest, 'late', k.late)), '{}'::jsonb) from k),
        'total', (select coalesce(sum(n), 0) from k),
        'universities', (select count(distinct p) from (select provider_id p from b where provider_id is not null
                                                        union select (y->>'provider_id')::uuid from h, jsonb_array_elements(h.bp) y where y->>'provider_id' is not null) u),
        'late', (select coalesce(sum(late), 0) from k),
        'paging', jsonb_build_object('items', security.pipeline_num_v1('layer4.inbox_page_size', 25)::int,
                                     'universities', security.pipeline_num_v1('layer4.inbox_universities_page_size', 25)::int,
                                     'detail_parallel', security.pipeline_num_v1('layer4.inbox_detail_parallel', 3)::int),
        'hooks_missing', v_hooks->'missing', 'hooks_failed', (v_hooks->'failed') || (v_hc->'failed')));

  elsif p_action = 'universities' then
    -- counts by university; names and course counts for the universities of this page only
    v_hc := case when v_bkind = '-' or v_fkind is null then security.layer4_inbox_hook_counts_v1(v_hooks, v_fkind) else '{"items": []}'::jsonb end;
    return (with c as (select b.kind, b.provider_id, b.n, b.oldest from security.layer4_inbox_counts_v1(v_target) b where v_bkind is distinct from '-' and (v_fkind is null or b.kind = v_fkind)
                       union all
                       select x->>'kind', (y->>'provider_id')::uuid, (y->>'n')::bigint, (y->>'oldest')::timestamptz
                         from jsonb_array_elements(v_hc->'items') x, jsonb_array_elements(x->'by_provider') y where coalesce((y->>'n')::bigint, 0) > 0),
                 g as (select c.provider_id, sum(c.n)::bigint n, min(c.oldest) oldest, min((v_kinds->c.kind->>'order')::int) first_order, jsonb_object_agg(c.kind, c.n) by_kind
                         from c group by 1),
                 u as (select g.*, coalesce(p.display_name, p.canonical_name, 'Platform') name, k.iso_alpha2::text country,
                              (select count(*) from catalogue.courses cc where cc.provider_id = g.provider_id and cc.lifecycle_status = 'active') courses
                         from g left join catalogue.providers p on p.id = g.provider_id left join ref.countries k on k.id = p.country_id
                        where (nullif(p_args->>'country', '') is null or k.iso_alpha2 = p_args->>'country')
                          and (v_q is null or coalesce(p.display_name, p.canonical_name, '') ilike '%' || v_q || '%'))
      select jsonb_build_object('total', (select count(*) from u), 'limit', v_lim, 'offset', v_off,
        'items', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'name', z.name, 'country', z.country, 'courses', z.courses, 'n', z.n, 'oldest', z.oldest,
                     'late', z.oldest < now() - make_interval(days => v_target), 'by_kind', z.by_kind)
                   order by z.first_order, z.courses desc nulls last, z.name)
            from (select * from u order by first_order, courses desc nulls last, name limit v_lim offset v_off) z), '[]'::jsonb)));

  elsif p_action = 'items' then
    if not (p_args ? 'provider_id' or p_args ? 'kind') then return jsonb_build_object('total', 0, 'items', '[]'::jsonb, 'before', 0, 'more', false); end if;
    v_prov := nullif(p_args->>'provider_id', '')::uuid;
    -- UR-04 (1 Nov 2026): a stable position (kind order, kind, created, ref) so every item is reached once, oldest first; kinds have their own order
    v_has := p_args ? 'after_ref';
    if v_has then v_ao := (p_args->>'after_o')::int; v_aat := (p_args->>'after_at')::timestamptz; v_ak := p_args->>'after_kind'; v_ar := p_args->>'after_ref'; end if;
    -- the built-in kinds: keys first (no detail), then the detail of this page's items only
    if v_bkind is distinct from '-' then
      with k as (select e.key kind, (e.value->>'order')::int o from jsonb_each(v_kinds) e),
           x as (select i.kind, i.ref, i.created_at, k.o, count(*) over () t,
                        count(*) filter (where v_has and (k.o, i.kind, i.created_at, i.ref) <= (v_ao, v_ak, v_aat, v_ar)) over () b
                   from security.layer4_inbox_items_v2(v_prov, v_bkind, null, false) i join k on k.kind = i.kind),
           pg as (select * from x where not v_has or (x.o, x.kind, x.created_at, x.ref) > (v_ao, v_ak, v_aat, v_ar) order by o, kind, created_at, ref limit v_lim + 1)
      select coalesce((select max(t) from x), 0), coalesce((select max(b) from x), 0), array(select pg.kind || ':' || pg.ref from pg) into v_total, v_before, v_keys;
    end if;
    -- registered kinds: their own pages and counts, merged in the same order
    for v_h in select x from jsonb_array_elements(v_hooks->'hooks') x where x->>'mode' = 'kind' and (v_fkind is null or x->>'kind' = v_fkind) loop
      v_ho := (v_h->>'order')::int;
      if v_hc is null then v_hc := security.layer4_inbox_hook_counts_v1(v_hooks, v_fkind); end if;
      v_np := coalesce((select case when v_prov is null then (x->>'n')::bigint
                                     else (select sum((y->>'n')::bigint) from jsonb_array_elements(x->'by_provider') y where (y->>'provider_id')::uuid = v_prov) end
                          from jsonb_array_elements(v_hc->'items') x where x->>'kind' = v_h->>'kind'), 0);
      v_total := v_total + v_np;
      if v_has and (v_ho, v_h->>'kind') < (v_ao, v_ak) then v_before := v_before + v_np; continue; end if;
      v_hargs := jsonb_strip_nulls(jsonb_build_object('provider_id', v_prov, 'limit', v_lim + 1));
      if v_has and (v_ho, v_h->>'kind') = (v_ao, v_ak) then v_hargs := v_hargs || jsonb_build_object('after_at', v_aat, 'after_ref', v_ar); end if;
      v_hp := security.layer4_inbox_hook_call_v1(v_h->>'page_fn', v_hargs, null);
      if v_hp ? 'error' or jsonb_typeof(v_hp->'items') is distinct from 'array' then continue; end if;
      if v_has and (v_ho, v_h->>'kind') = (v_ao, v_ak) then v_before := v_before + coalesce((v_hp->>'before')::bigint, 0); end if;
      v_hitems := v_hitems || coalesce((select jsonb_agg(i || jsonb_build_object('kind', v_h->>'kind', 'o', v_ho, '_s', lpad(n::text, 10, '0'),
                                                 'late', coalesce((i->>'late')::boolean, (i->>'created_at')::timestamptz < now() - make_interval(days => v_target)),
                                                 'detail', coalesce(i->'detail', '{}'::jsonb)) order by n)
                                          from jsonb_array_elements(v_hp->'items') with ordinality y(i, n) where i ? 'ref'), '[]'::jsonb);
    end loop;
    return (with b as (select i.kind, i.ref, i.provider_id, coalesce(p.display_name, p.canonical_name) provider, i.subject, i.why, i.suggestion, i.created_at, i.detail,
                              (v_kinds->i.kind->>'order')::int o
                         from security.layer4_inbox_items_v2(v_prov, v_bkind, v_keys, true) i left join catalogue.providers p on p.id = i.provider_id
                        where coalesce(array_length(v_keys, 1), 0) > 0),
                 m as (select b.o, b.kind, b.created_at, b.ref s, jsonb_build_object('kind', b.kind, 'ref', b.ref, 'provider_id', b.provider_id, 'provider', b.provider, 'subject', b.subject,
                              'why', b.why, 'suggestion', b.suggestion, 'created_at', b.created_at, 'late', b.created_at < now() - make_interval(days => v_target), 'detail', b.detail, 'o', b.o) j from b
                       union all
                       select (h->>'o')::int, h->>'kind', (h->>'created_at')::timestamptz, h->>'_s', (h - '_s') || jsonb_build_object('hook', true) from jsonb_array_elements(v_hitems) h),
                 pg as (select * from m order by o, kind, created_at, s limit v_lim)
      select jsonb_build_object('total', v_total, 'before', v_before, 'more', (select count(*) from m) > v_lim,
                                'items', coalesce((select jsonb_agg(pg.j order by pg.o, pg.kind, pg.created_at, pg.s) from pg), '[]'::jsonb)));

  elsif p_action = 'detail' then
    -- lazy detail of the items on screen (at most one page): the stored-copy facts of a built-in item and a hook's detail (kind or extension)
    return (with a as (select x->>'kind' kind, x->>'ref' ref from jsonb_array_elements(case when jsonb_typeof(p_args->'items') = 'array' then p_args->'items' else '[]'::jsonb end) x
                        where x ? 'kind' and x ? 'ref' limit v_lim),
                 b as (select i.kind, i.ref, i.detail from security.layer4_inbox_items_v2(null, null, array(select a.kind || ':' || a.ref from a where security.layer4_inbox_kinds_v1() ? a.kind), true) i
                        where exists (select 1 from a where security.layer4_inbox_kinds_v1() ? a.kind))
      select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object('kind', a.kind, 'ref', a.ref, 'detail', b.detail,
               'hook_detail', security.layer4_inbox_hook_call_v1((select h->>'detail_fn' from jsonb_array_elements(v_hooks->'hooks') h where h->>'kind' = a.kind limit 1), null, a.ref))), '[]'::jsonb))
        from a left join b on b.kind = a.kind and b.ref = a.ref);
  end if;

  -- CF-247 20 Oct 2026: the decisions taken here, newest first (replaces the old Review queue history)
  if p_action = 'decided' then
    return jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'kind', e.detail->>'kind', 'choice', e.detail->>'choice', 'value', e.detail->>'value',
             'reason', e.detail->>'reason', 'provider_id', e.detail->>'provider_id',
             'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id::text = e.detail->>'provider_id'),
             'by', (select u.email from auth.users u where u.id::text = e.actor::text)) order by e.id desc)
           from (select * from pipeline.admin_control_events x where x.area = 'layer4' and x.action = 'inbox_decide' order by x.id desc limit v_lim offset v_off) e), '[]'::jsonb));
  end if;
  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;
  v_kind := p_args->>'kind'; v_ref := p_args->>'ref'; v_choice := p_args->>'choice'; v_value := nullif(btrim(p_args->>'value'), '');
  v_c := (select c from jsonb_array_elements(v_kinds->v_kind->'choices') c where c->>'key' = v_choice);
  if v_c is null then raise exception 'unknown choice % for %', v_choice, v_kind; end if;
  if v_c ? 'link' then raise exception 'this choice opens another screen'; end if;
  if v_rank < coalesce((v_c->>'rank')::int, 4) then raise exception 'your role cannot make this choice' using errcode = '42501'; end if;  -- fixed: university and value choices need Pipeline Operator or above unless the choice names a higher rank
  -- a registered kind or recovery choice is decided by its own function, which checks the item, enforces its rules and writes its own audit row
  if v_c ? 'hook' then
    v_fn := (select h->>'decide_fn' from jsonb_array_elements(v_hooks->'hooks') h where h->>'id' = v_c->>'hook');
    if v_fn is null then raise exception 'this choice is not available yet'; end if;
    execute format('select %s($1, $2, $3, $4)', v_fn) into v_r using v_ref, v_choice, v_value, coalesce(nullif(btrim(p_args->>'reason'), ''), v_c->>'reason', '');
    -- CF-247 decision 12:24 §4: the reply carries its normalised acknowledgement, read from the records just written
    return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object('ok', coalesce((v_r->>'ok')::boolean, false), 'kind', v_kind, 'choice', v_choice, 'returns', coalesce(v_r->>'returns', v_c->>'returns'),
                              'result', v_r->'result', 'ref', v_ref, 'event_id', v_r->'event_id', 'request', v_r->'request', 'outcome', v_r->'outcome', 'hook', v_c->>'hook'));
  end if;
  v_reason := coalesce(nullif(btrim(p_args->>'reason'), ''), v_c->>'reason', '');
  if length(v_reason) < 4 then raise exception 'give a reason (kept with the decision)'; end if;
  if v_c->>'input' = 'url' and (v_value is null or v_value !~* '^https?://[^\s/]+\.[^\s]+$') then raise exception 'enter the full web address (https://…)'; end if;
  select i.provider_id, i.detail into v_pid, v_det from security.layer4_inbox_items_v2(null, v_kind, array[v_kind || ':' || v_ref], true) i;
  if v_det is null then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
  -- CF-247 mandate 16:32 §8: the same decision sent again returns the first; a retry on an unchanged stop is refused (both audited, never taken)
  v_det := v_det || jsonb_build_object('_guard', security.layer4_decide_guard_v1(v_kind, v_ref, v_choice, v_pid));
  if v_det->'_guard' is not null and jsonb_typeof(v_det->'_guard') = 'object' then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'inbox_refused', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'value', v_value, 'reason', v_reason, 'provider_id', v_pid,
            'result', v_det->'_guard'), auth.uid()) returning id into v_event;
    return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object('ok', false, 'kind', v_kind, 'choice', v_choice, 'ref', v_ref, 'event_id', v_event,
                                         'request', v_det->'_guard'->>'request', 'result', v_det->'_guard'));
  end if;
  v_det := v_det - '_guard';

  -- SS-016 fee check (1 Nov 2026): an address on a fee-check item was taken as a plain Approve and admitted the proposed fee (46 decisions
  -- on 30 Oct). A fee check is admitted or not; a different course page is set on the course record.
  if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition_validation' and v_choice = 'enter' then
    raise exception 'this is a fee check: admit the proposed fee or do not admit it. A different course page is set on the course record';
  end if;

  -- 24 Oct 2026 (hotfix D1): a course-link row that holds a fee (identity re-verification quarantine, fee floor) is not a link decision
  if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition' and v_choice in ('use', 'enter') then
    if v_choice = 'use' then raise exception 'this item holds a fee, not a new page: enter the course page''s address, or keep the page we hold'; end if;
    v_r := security.layer4_fee_item_rebind_v1(v_ref::uuid, v_value, v_reason);
  elsif v_kind in ('no_page_first_run', 'conjoint_first_run') then
    -- hotfix 26 Oct 2026: a university's first run (no page published / conjoint rule); applied by security.no_page_review_apply_v1
    if v_choice = 'has_page' then
      begin
        v_ids := array(select jsonb_array_elements_text(v_value::jsonb)::uuid);
      exception when others then raise exception 'tick the sample courses that have their own page';
      end;
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'tick the sample courses that have their own page'; end if;
      if exists (select 1 from unnest(v_ids) x(id) where not exists (select 1 from pipeline.course_no_page n where n.review_item_id = v_ref::uuid and n.course_id = x.id)) then
        raise exception 'a ticked course is not in this sample';
      end if;
    end if;
    v_r := public.layer4_review_decide(v_ref::uuid,
             case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end, v_reason,
             case v_choice when 'has_page' then jsonb_build_object('has_page_course_ids', to_jsonb(v_ids))
                           when 'parent' then jsonb_build_object('parent_url', v_value) end);
  elsif v_kind = 'aer_review' then
    -- CF-247 A1-A3 (Platform Admin 30 Oct 2026 06:53): one AER item at a time; Approve except sends the ticked rows to leave out
    if v_choice = 'approve_except' then
      begin
        v_ids := array(select jsonb_array_elements_text(v_value::jsonb)::uuid);
      exception when others then raise exception 'tick the rows to leave out';
      end;
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'tick the rows to leave out'; end if;
    end if;
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end, v_reason,
             case when v_choice = 'approve_except' then jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(v_ids)) end);
  elsif v_kind = 'provider_description' and v_choice in ('reread', 'approve_provider') and v_det->>'field_code' is distinct from 'course_description_first_read' then
    raise exception 'this choice is for course descriptions only';
  elsif v_kind = 'provider_description' and v_choice = 'reread' then
    -- s664 (CF-247 S1-Courses, Platform Admin 18 Nov 2026): the stored page is read again by the released 1-2 sentence reader; the course is not marked bad
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = left(coalesce(change_control_ref, '') || ' | superseded: re-read asked by a person (' || security.cdesc_prompt_version_v1() || ')', 400)
     where id = v_ref::uuid and status = 'pending';
    if not found then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (v_ref::uuid, 'course_description_first_read', 'course', (v_det->>'course_id')::uuid, 'decided_before', null,
            jsonb_build_object('by', 'layer4-reread', 'actor', v_actor, 'reason', v_reason, 'prompt_after', security.cdesc_prompt_version_v1(), 'evidence_id', v_det->>'evidence_id'), 'reconcile');
    if to_regclass('pipeline.layer4_item_readiness') is not null then
      execute 'update pipeline.layer4_item_readiness set item_status = ''superseded'', readiness = ''closed'', classified_at = now() where item_id = $1' using v_ref::uuid;
    end if;
    update pipeline.field_enrich_items e set reason = left('reread: a person asked in Layer 4 for a re-read with ' || security.cdesc_prompt_version_v1() || ' (' || v_reason || ')', 300), updated_at = now()
     where e.field = 'description' and e.course_id = (v_det->>'course_id')::uuid and e.state = 'skipped'
       and (e.id::text = v_det->'proposed'->>'item_id' or e.value->>'review_item_id' = v_ref);
    get diagnostics v_cd_n = row_count;
    v_r := jsonb_build_object('reread', true, 'readings_queued', v_cd_n, 'prompt', security.cdesc_prompt_version_v1());
  elsif v_kind = 'provider_description' and v_choice = 'approve_provider' then
    -- s664: every waiting course description of this provider read from the course's own bound page (its CRICOS or NZQA code, or its exact title) whose sentences all
    -- pass the live quote and sentence check; the count is returned first and admitted only when the person types the same count
    select coalesce(array_agg(q.id order by q.created_at, q.id), '{}') into v_ids
      from pipeline.layer4_review_items q
      join catalogue.courses cq on cq.id = q.entity_id and cq.provider_id = v_pid and cq.lifecycle_status = 'active' and nullif(btrim(cq.description), '') is null
      join pipeline.coverage_course_pages gq on gq.course_id = cq.id and gq.status = 'bound' and gq.provider_id = cq.provider_id and gq.evidence_id is not distinct from q.evidence_id
      join pipeline.field_enrich_items fq on fq.id::text = q.proposed_value->>'item_id' and fq.course_id = cq.id and fq.field = 'description' and fq.state = 'review'
     where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
       and q.proposed_value->>'source_url' is not distinct from gq.url
       and gq.identity_basis in ('cricos_code', 'nzqa_code', 'exact_title')
       and not exists (select 1 from pipeline.manual_locks lq where lq.entity = 'course' and lq.entity_id = cq.id and lq.field in ('description', 'course_description', 'all'))
       and coalesce((security.course_description_check_v1(cq.id, fq.value)->>'ok')::boolean, false);
    v_cd_n := coalesce(cardinality(v_ids), 0);
    if v_cd_n = 0 then raise exception 'no waiting course description of this provider passes the quote check on its own page'; end if;
    if v_value is null or v_value !~ '^\d+$' or v_value::int <> v_cd_n then
      return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object('ok', false, 'kind', v_kind, 'choice', v_choice, 'ref', v_ref, 'eligible', v_cd_n,
               'request', v_cd_n || ' waiting course description(s) of this provider pass the quote check on the course''s own page. Type ' || v_cd_n || ' in the box and choose again to approve them all.'));
    end if;
    v_cd_ok := 0;
    foreach v_prov in array v_ids loop
      begin
        v_hp := public.layer4_review_decide(v_prov, 'approve', left('[bulk provider, ' || v_cd_n || ' verified] ' || v_reason, 500), null);
        v_cd_ok := v_cd_ok + 1;
      exception when others then null; -- one item never stops the rest; it stays waiting
      end;
    end loop;
    v_r := jsonb_build_object('approved', v_cd_ok, 'eligible', v_cd_n);
  elsif v_kind = 'provider_description' then
    -- CF-247 P1 (Platform Admin 2 Nov 2026 10:28): a university description is approved as read or rejected, never edited
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'approve' then 'approve' else 'reject' end, v_reason, null);
  elsif v_kind = 'course_link' and v_choice = 'refuse' then
    -- mandate 3 Nov 2026 20:47 §5: refuse the proposed page without claiming a held page
    v_r := security.layer4_course_link_refuse_v1(v_ref::uuid, v_reason);
  elsif v_kind = 'course_page_needed' then
    -- Decision 179 (Platform Admin 3 Nov 2026 20:29): add the page, search again, or record that no page exists
    v_r := security.course_page_needed_decide_v1(v_ref::uuid, v_choice, v_value, v_reason);
  elsif v_kind = 'held_scholarship' and v_choice = 'duplicate' then
    -- handover 3 Nov 2026 Priority 2 item 8: close a held scholarship as a duplicate of a published one (the reviewer names it)
    v_r := security.scholarship_duplicate_close_v1(v_ref::bigint, v_value, v_reason);
  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'keep' then 'reject' when 'use' then 'approve' else 'edit_and_approve' end, v_reason,
                                       case when v_choice = 'enter' then to_jsonb(v_value) end);
  elsif v_kind = 'held_scholarship' then
    v_r := public.admin_scholarship_ai('review_decide', jsonb_build_object('review_id', v_ref::bigint, 'decision', case when v_choice = 'publish' then 'admit' else 'refuse' end,
                                                                         'extraction_id', v_det->'extraction_id', 'reason', v_reason));
  elsif v_kind = 'provider_departure' then  -- CF-247 20 Oct 2026: from the retired Review queue (Provider departures); Platform Admin
    if v_choice = 'merged' then
      select array_agg(p.id) into v_ids from catalogue.providers p
       where p.lifecycle_status = 'active' and p.id <> v_pid and p.country_id = (select q.country_id from catalogue.providers q where q.id = v_pid)
         and (lower(coalesce(p.display_name, p.canonical_name)) = lower(v_value)
              or p.id in (select r.provider_id from catalogue.provider_registrations r where upper(r.registration_code) = upper(v_value)));
      if coalesce(array_length(v_ids, 1), 0) <> 1 then raise exception 'enter the successor''s exact name or its CRICOS or NZQA code (% found)', coalesce(array_length(v_ids, 1), 0); end if;
    end if;
    v_r := public.layer4_provider_departure_decide(v_ref::bigint, v_choice, case when v_choice = 'merged' then v_ids[1] end, v_reason);
  elsif v_kind = 'counsellor_report' then  -- CF-247 20 Oct 2026: closed here (Coverage › Counsellor reports retired); Zoho reads the outcome back
    v_r := public.admin_counsellor_reports('close', jsonb_build_object('ids', jsonb_build_array(v_ref), 'outcome', case v_choice when 'report_fixed' then 'fixed' else 'not_changed' end, 'reason', v_reason));
  elsif v_choice = 'website' then
    v_r := public.admin_provider_website_set(v_pid, v_value);
    if v_kind in ('pages_not_found', 'site_down') then
      v_r := v_r || jsonb_build_object('released', security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: website changed to ' || v_value || '. ' || v_reason, jsonb_build_object('user_id', auth.uid()), false));
    end if;
  elsif v_choice in ('release', 'keep') then
    v_r := security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: ' || v_reason, jsonb_build_object('user_id', auth.uid()), false);
  elsif v_choice = 'wait' then
    update pipeline.enrichment_flags set flagged_at = now() where id = (v_det->>'flag_id')::bigint;  -- asked again after the waiting period
    v_r := jsonb_build_object('waiting', true);
  elsif v_choice = 'cricos_only' then
    v_r := public.admin_adapter_build('set_wave', jsonb_build_object('wave', 'cricos-only', 'provider_ids', jsonb_build_array(v_pid)));
  elsif v_choice = 'rebuild' then
    v_r := public.admin_adapter_build('build', jsonb_build_object('provider_ids', jsonb_build_array(v_pid), 'reason', 'Layer 4: ' || v_reason));
  elsif v_choice = 'retry' then
    v_r := public.admin_provider_onboarding('retry', jsonb_build_object('ids', jsonb_build_array((v_det->>'onboarding_id')::uuid), 'reason', 'Layer 4: ' || v_reason));
  elsif v_choice = 'archive' then
    v_r := public.admin_provider_archive(v_pid, 'Layer 4: ' || v_reason, false);
  elsif v_choice = 'archive_course' then
    v_r := public.admin_course_edit((v_det->>'course_id')::uuid, 'archive', jsonb_build_object('reason', 'Layer 4: ' || v_reason));
    perform security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: course archived. ' || v_reason, jsonb_build_object('user_id', auth.uid()), false);
  else
    raise exception 'choice % is not handled', v_choice;
  end if;
  -- CF-247 mandate 16:32 §8: whether the item is still waiting after the decision, so a decision that did not apply is never recorded as done
  if jsonb_typeof(v_r) = 'object' or v_r is null then
    v_r := coalesce(v_r, '{}'::jsonb) || jsonb_build_object('still_waiting', exists (select 1 from security.layer4_inbox_items_v2(null, v_kind, array[v_kind || ':' || v_ref], false)));
  end if;
  if coalesce(v_r->>'still_waiting', '') = 'false' then
    update pipeline.layer4_item_groups set state = 'closed', closed_at = now() where kind = v_kind and ref = v_ref and state = 'waiting';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'value', v_value, 'reason', v_reason, 'provider_id', v_pid, 'result', v_r), auth.uid())
  returning id into v_event;
  -- UR-06 (1 Nov 2026): the reply names the audit event and what the decision actually did, read back from its destination
  return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object('ok', true, 'kind', v_kind, 'choice', v_choice, 'returns', v_c->>'returns', 'result', v_r, 'ref', v_ref, 'event_id', v_event,
                            'outcome', security.layer4_decision_outcome_v1(v_kind, v_choice, v_r)));
end $function$
