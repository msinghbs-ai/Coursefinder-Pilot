-- CF-247 F-PDESC delivery (Platform Admin operating model v1.5, 10 Nov 2026): register the provider-description prompt that worker v0.60.0 runs.
-- Worker v0.60.0 (20261110120000 ships the database side) changed DESCRIPTION_SYSTEM (coverage-sweep/description.ts): one short paraphrase per quote, nothing added. The AI instruction registry
-- (pipeline.ai_instruction_versions, 20261104070000) records every live prompt with the md5 of the worker text it runs, and spec s250 fails a prompt edited in code without a new version.
-- Live registry (SELECT, 10 Nov 2026): code provider-description, version provider-description-v2, status current, body_md5 f539da5e1d69e8fde6a113459ceede75 (row 6). The new text hashes to ff2dd332522a1cc257d0895e8342ac84.
-- What this does (the supported path of 20261104070000: security.ai_instruction_register_v1 with the release marker cf247.release, as the baselines were registered; a version is never rewritten):
--   1 the row provider-description-v2 becomes previous (kept for rollback);
--   2 a new row provider-description-v2.1 is registered as current: same family, same pinned model (openai/gpt-4.1-mini), home worker coverage-sweep/description.ts DESCRIPTION_SYSTEM, body_md5 ff2dd332522a1cc257d0895e8342ac84, parent the earlier row.
-- The string 'provider-description-v2' stays what the worker records as a read's prompt_version (DESCRIPTION_PROMPT_VERSION; the SQL hard-codes it as the default in many places); only the registry label moves, so no read, signature or SQL default changes.
-- Guarded and idempotent: it stops, and changes nothing, if the current row is neither the earlier baseline (f539da5e...) nor the one this writes (ff2dd332...); applying it again changes nothing. The earlier row is never rewritten or deleted.
-- Nothing is a setting, job, table, column or consumer object (G1, G2, G3). No operational number is written into code (G2). Pinned model unchanged (a router or "auto" is refused by the registry).
-- Replaces: the registry baseline provider-description-v2 (status current becomes previous; the row is kept); recovery in supabase/held/pdesc_prompt_baseline_forward_recovery.sql
-- Retires: nothing

do $m$
declare v_old record; v_new record; v_id bigint;
begin
  if to_regclass('pipeline.ai_instruction_versions') is null or to_regprocedure('security.ai_instruction_register_v1(jsonb)') is null then
    raise exception 'required AI instruction registry is missing (apply 20261104070000 first)';
  end if;
  perform set_config('cf247.release', '20261110125000', true);
  select * into v_new from pipeline.ai_instruction_versions where code = 'provider-description' and version = 'provider-description-v2.1';
  if found then
    if v_new.body_md5 <> 'ff2dd332522a1cc257d0895e8342ac84' then raise exception 'provider-description-v2.1 is registered with other content (%)', v_new.body_md5; end if;
    return;   -- already applied (a rollback by the recovery leaves the row with status rolled_back, and this migration is then not applied again)
  end if;
  select * into v_old from pipeline.ai_instruction_versions where code = 'provider-description' and status = 'current';
  if not found or v_old.version <> 'provider-description-v2' or v_old.body_md5 <> 'f539da5e1d69e8fde6a113459ceede75' then
    raise exception 'the current provider-description baseline is not the one this change registers over (%, %)', v_old.version, v_old.body_md5;
  end if;
  update pipeline.ai_instruction_versions set status = 'previous' where id = v_old.id;
  v_id := (security.ai_instruction_register_v1(jsonb_build_object('family', v_old.family, 'code', 'provider-description', 'kind', 'prompt', 'version', 'provider-description-v2.1', 'status', 'current',
            'model', v_old.model_identifier, 'home', 'worker coverage-sweep/description.ts DESCRIPTION_SYSTEM', 'body_md5', 'ff2dd332522a1cc257d0895e8342ac84',
            'note', 'worker v0.60.0 (10 Nov 2026): one short paraphrase per quote in the quote''s own words, nothing added, the governed copy limit stated; reads still record prompt_version provider-description-v2')))->>'id';
  update pipeline.ai_instruction_versions set parent_id = v_old.id where id = v_id;
end $m$;
