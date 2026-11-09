-- HELD (not a migration): forward recovery for 20261110125000 (registry baseline provider-description-v2.1). Run only if the Platform Admin takes worker v0.60.0 back to the earlier prompt text.
-- It makes provider-description-v2 (body_md5 f539da5e1d69e8fde6a113459ceede75) current again and marks provider-description-v2.1 (ff2dd332522a1cc257d0895e8342ac84) rolled_back. No row is deleted or rewritten; the worker text must be put back with it
-- (spec s250 checks the registry against description.ts). Guarded: it stops, and changes nothing, unless the current row is v2.1 with that md5 and v2 is previous with its md5. Applying it again changes nothing.
do $r$
declare v_old record; v_new record;
begin
  select * into v_new from pipeline.ai_instruction_versions where code = 'provider-description' and version = 'provider-description-v2.1';
  select * into v_old from pipeline.ai_instruction_versions where code = 'provider-description' and version = 'provider-description-v2';
  if v_old.id is null or v_new.id is null then raise exception 'the provider-description registry rows are missing'; end if;
  if v_new.status = 'rolled_back' and v_old.status = 'current' then return; end if;
  if v_new.status <> 'current' or v_new.body_md5 <> 'ff2dd332522a1cc257d0895e8342ac84' or v_old.status <> 'previous' or v_old.body_md5 <> 'f539da5e1d69e8fde6a113459ceede75' then
    raise exception 'the provider-description registry is not in the state this recovery knows';
  end if;
  update pipeline.ai_instruction_versions set status = 'rolled_back' where id = v_new.id;
  update pipeline.ai_instruction_versions set status = 'current' where id = v_old.id;
end $r$;
