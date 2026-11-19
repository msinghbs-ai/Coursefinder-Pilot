CREATE OR REPLACE FUNCTION security.provider_description_machine_gate_v1(p_provider uuid, p_text text, p_ctx jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p catalogue.providers%rowtype; v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account (Decision 263)
        v_bad text; v_blk jsonb; v_codes text[] := coalesce(array(select jsonb_array_elements_text(coalesce(p_ctx->'codes', '[]'::jsonb))), '{}');
begin
  if security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off', 'reason', 'Automatic admission is off; a person decides in Layer 4.'); end if;
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null or p.lifecycle_status <> 'active' or p.publication_status <> 'published' or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) or security.provider_lifecycle_held_v1(p.id) then
    return jsonb_build_object('ok', false, 'rule', 'provider_not_live', 'reason', 'The provider is not active and published, or its lifecycle is held.');
  end if;
  if not security.provider_description_scope_v1(p.id) then return jsonb_build_object('ok', false, 'rule', 'out_of_scope', 'reason', 'The provider is outside the description reader scope.'); end if;
  -- lock, description already held, cleared after a machine admission, earlier human rejection, withdrawn awaiting review, open identity finding, unusable name
  v_blk := security.provider_description_machine_blocked_v1(p.id);
  if v_blk is not null then return jsonb_build_object('ok', false, 'rule', v_blk->>'rule', 'reason', v_blk->>'reason'); end if;
  if nullif(btrim(p_text), '') is null then return jsonb_build_object('ok', false, 'rule', 'no_description', 'reason', 'There is no description text.'); end if;
  v_bad := security.pdesc_machine_text_check_ctx_v1(p.id, p_text, v_codes, coalesce(p_ctx->'sentences', '[]'::jsonb));
  if v_bad is not null then return jsonb_build_object('ok', false, 'rule', 'machine_text_' || split_part(v_bad, ':', 1), 'reason', 'The description has a word, figure or markup the automatic rule does not admit (' || v_bad || '); it is not published automatically.'); end if;
  return jsonb_build_object('ok', true, 'rule', 'pdesc-machine-v1', 'actor', v_sys);
end $function$
