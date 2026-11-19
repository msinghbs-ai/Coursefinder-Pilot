-- CF-247 / Decision 134 follow-up: applying the QILT SES 2025 edition was refused with "QILT observation lacks
-- verified source-to-CRICOS mapping". Two institutions in that file (Victoria University, Holmes Institute) are
-- one QILT institution with several CRICOS provider codes. The worker records one verified mapping per
-- institution and lists the verified equivalent providers in that mapping (metadata.equivalent_provider_ids),
-- then writes an observation for each of them. The apply guard only accepted the first provider.
-- The guard now also accepts a provider listed in the same verified mapping's equivalent set. Nothing else
-- changes: the mapping must still be verified, for the same source and institution. Checksum-guarded.
do $patch$
declare v_def text; v_old text; v_new text;
begin
  v_def:=pg_get_functiondef('pipeline.svc_qilt_apply_observations(jsonb)'::regprocedure);
  if md5(v_def)<>'51f88dce77bfa10894659e6362be0836' then
    raise exception 'pipeline.svc_qilt_apply_observations changed since review; not replaced'; end if;
  v_old:='and m.provider_id=(r->>''provider_id'')::uuid and m.status=''verified'') then';
  v_new:='and m.status=''verified'' and (m.provider_id=(r->>''provider_id'')::uuid or (coalesce((m.metadata->>''statistical_equivalence_fanout'')::boolean,false) and coalesce(m.metadata->''equivalent_provider_ids'',''[]''::jsonb) ? (r->>''provider_id'')))) then';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then
    raise exception 'mapping check anchor not found exactly once'; end if;
  execute replace(v_def,v_old,v_new);
end $patch$;
