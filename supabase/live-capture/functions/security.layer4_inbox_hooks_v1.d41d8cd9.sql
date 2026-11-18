CREATE OR REPLACE FUNCTION security.layer4_inbox_hooks_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 Layer 4 Inbox kind hooks (4 Nov 2026; contract admin docs/platform/ui-audit/2026-11-04-layer4-inbox-paging-contract.md): the kinds and
-- choices of the Inbox, the built-in ones (security.layer4_inbox_kinds_v1) with the registered hooks whose functions exist. A hook that is
-- missing, collides with a built-in kind or fails is left out and named, so the Inbox always loads.
declare v_kinds jsonb := security.layer4_inbox_kinds_v1(); v_builtin jsonb := security.layer4_inbox_kinds_v1(); h record; v_fn jsonb; v_id text; v_k jsonb; v_ch jsonb;
        v_hooks jsonb := '[]'; v_missing jsonb := '[]'; v_failed jsonb := '[]'; v_need text[];
begin
  if security.pipeline_num_v1('layer4.inbox_hooks_on', 1) <> 1 then
    return jsonb_build_object('kinds', v_kinds, 'hooks', v_hooks, 'missing', v_missing, 'failed', v_failed, 'on', false);
  end if;
  for h in select * from pipeline.layer4_inbox_kind_hooks x where x.enabled order by x.mode desc, x.kind loop
    v_id := h.kind || ':' || h.mode;
    v_fn := jsonb_build_object('kind_fn', security.layer4_inbox_hook_fn_v1(h.kind_fn), 'counts_fn', security.layer4_inbox_hook_fn_v1(h.counts_fn),
              'page_fn', security.layer4_inbox_hook_fn_v1(h.page_fn), 'detail_fn', security.layer4_inbox_hook_fn_v1(h.detail_fn), 'decide_fn', security.layer4_inbox_hook_fn_v1(h.decide_fn));
    if (h.mode = 'kind') = (v_builtin ? h.kind) then
      v_failed := v_failed || jsonb_build_array(jsonb_build_object('id', v_id, 'error', case when h.mode = 'kind' then 'a built-in kind has this key' else 'no built-in kind has this key' end));
      continue;
    end if;
    v_need := case when h.mode = 'kind' then array['kind_fn', 'counts_fn', 'page_fn', 'decide_fn'] else array['kind_fn', 'decide_fn'] end;
    if exists (select 1 from unnest(v_need) x where v_fn->>x is null) then
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('id', v_id, 'missing', to_jsonb(array(select x from unnest(v_need) x where v_fn->>x is null))));
      continue;
    end if;
    begin
      execute format('select %s()', v_fn->>'kind_fn') into v_k;
    exception when others then
      v_failed := v_failed || jsonb_build_array(jsonb_build_object('id', v_id, 'error', sqlerrm)); continue;
    end;
    v_ch := (select coalesce(jsonb_agg(c || jsonb_build_object('hook', v_id) order by o), '[]'::jsonb)
               from jsonb_array_elements(case when jsonb_typeof(v_k->'choices') = 'array' then v_k->'choices' else '[]'::jsonb end) with ordinality x(c, o)
              where c ? 'key' and c ? 'label'
                and (h.mode = 'kind' or not exists (select 1 from jsonb_array_elements(v_builtin->h.kind->'choices') b where b->>'key' = c->>'key')));
    if h.mode = 'kind' then
      v_kinds := v_kinds || jsonb_build_object(h.kind, jsonb_build_object('label', coalesce(v_k->>'label', h.kind), 'order', coalesce((v_k->>'order')::int, 99),
                   'choices', v_ch, 'hook', v_id, 'detail', v_fn->>'detail_fn' is not null));
    else
      v_kinds := jsonb_set(v_kinds, array[h.kind], (v_kinds->h.kind) || jsonb_build_object('choices', (v_kinds->h.kind->'choices') || v_ch, 'extension', v_id,
                   'detail', v_fn->>'detail_fn' is not null));
    end if;
    v_hooks := v_hooks || jsonb_build_array(jsonb_build_object('id', v_id, 'kind', h.kind, 'mode', h.mode,
                 'order', coalesce((v_kinds->h.kind->>'order')::int, 99)) || v_fn);
  end loop;
  return jsonb_build_object('kinds', v_kinds, 'hooks', v_hooks, 'missing', v_missing, 'failed', v_failed, 'on', true);
end $function$
