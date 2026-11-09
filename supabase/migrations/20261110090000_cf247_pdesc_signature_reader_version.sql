-- CF-247 F-PDESC (Platform Admin, 9-10 Nov 2026, on-demand provider descriptions): the identity fix must be able to reach the AI step. A failure the earlier reader recorded no longer blocks the current reader, and a hold that came from that false refusal is offered again.
--
-- What was wrong (project fxcwkweaxjtknorudmwp, read-only evidence, 10 Nov 2026 about 06:25 AEDT):
--   * Since worker v0.59.15 (reader stamp provider-description-source-guard-v3) the University of Sydney read (14939e4a-09e4-4b3b-ab4d-2e1166148679, evidence cc325a2c, content hash a73149cc) passes the identity proof
--     (current_provider_name, registry_heading_name), and is then held with rule recovery_knowledge_unchanged_failure: "The existing governed AI budget refused the conservative per-call reservation; no AI call was made."
--     ai_calls 0, reserved_usd 0: the budget did not refuse anything. The reservation (public.svc_provider_description_reserve_v1) asks security.ops_learning_retry_check_v1 whether this provider and evidence signature
--     already failed, and the answer was yes.
--   * The failure it found is the earlier identity hold of the SAME page: reads 08dd15f1 (reader v1, 8 Nov) and f1b50c9e (reader v2, 9 Nov) were held provider_name_conflict, and the learning trigger
--     (security.provider_description_learning_trg_v1, after update of state) recorded each as a failed official_about attempt under security.provider_description_signature_v1(content_hash, model, prompt version).
--     That signature carries the page, the model, the prompt, the validation text and the validation settings, but NOT the reader that judged the page. So the identity reader changed (20261109185000 re-offers such holds
--     to the current reader), the page did not, the signature did not, and the old failure of the old reader blocked the new reader before it could call the AI. No AI call had ever been made for that page.
--   * It is not one provider. Of the latest finished reads, 41 are held provider_name_conflict by reader v2, 29 by reader v1 and 3 provider_subunit_source by reader v2; the running reader is v3
--     (pipeline.pdesc_reader_state, newest stamp, seen 9 Nov 19:17 UTC). Each of them is re-offered once to v3, and each would meet this refusal at the reservation. 206 reads are queued, 10 are reading, none of the queued has failure memory.
-- What this changes (two function bodies; no setting, job, table, column, trigger, grant or consumer object):
--   1 security.provider_description_signature_v1(text,text,text) also carries the reader that is running now, security.pdesc_reader_behaviour_v1() (the newest stamp a worker wrote, one primary-key row of
--   pipeline.pdesc_reader_state, kept by the triggers of 20261109185000). A failure recorded while reader X was running is found only by a check made while reader X is running; when the reader's behaviour changes, the
--   signature changes, and the same page may be tried once by the new reader. A failure recorded under the current reader still blocks an unchanged retry, exactly as now.
--   When there is no running reader (the state row is empty, the function returns null) nothing is added and the signature is exactly the one before this change.
--   2 security.provider_description_selection_v1(jsonb) (QA of this change, 10 Nov 2026: it did not unblock Sydney). The picker parked a held read of rule recovery_knowledge_unchanged_failure on its unchanged page
--     (unchanged_unsuitable_evidence, then retry_wait), even when that hold came from a refusal with no AI call. Sydney's read 14939e4a is exactly that (ai_calls 0, reserved_usd 0, hold made by the old signature check), so after change 1 the
--     reservation would allow it, but nothing ever queued it. Now such a read is not parked by those two tests when ALL of: it is held on rule recovery_knowledge_unchanged_failure; no AI call was made (ai_calls 0) and nothing is reserved (reserved_usd 0);
--     its page is still the stored page (same content hash); the retry memory no longer matches under the current signature (the same ops_learning_retry_check_v1 test the picker applies in its last branch); and no earlier read of the provider was
--     REJECTED on that page. It is then judged by every later test as before (identity proof, the recovery-memory test, scope, manual locks) and, if all pass, is eligible. It stays parked when: the page changed (retry_wait as now), the hold was a real AI
--     failure or another rule (the rule or ai_calls differ), the page was rejected (unchanged_unsuitable_evidence), or the memory still matches. If the re-read is refused again because the memory now matches, that hold is parked at once (the memory test
--     is the one this change adds), so a provider is offered again only when the signature (page, model, prompt, validation, reader) is new. policy_retry_parked, identity_reeval_rules, the recheck period (retry_wait), the manual locks and every cap
--     (queue_cap, queue_per_run, pending_max, pdesc.ai_usd_max, the daily guard, tries) are not changed.
-- One signature for the recorder and every checker (checked by grep of supabase/ and of the live pg_proc.prosrc on 10 Nov 2026): the function is called by
--   the recorder security.provider_description_learning_trg_v1 (live body md5 470dd2b0208e0fc6f46f1c95be55a72e), and the checkers public.svc_provider_description_reserve_v1 (8f1f3edfb97f848b4296d6be0333a35b),
--   public.svc_provider_description_next (504678d725b0131785f7e3541a6c3695, as 20261110040000 leaves it) and security.provider_description_selection_v1 (41c9e5ffaba74453c699fd84e9135648, as 20261110040000 leaves it).
--   Only the picker is edited here (change 2); all four call the one function, so recorder and checkers cannot disagree. The trigger fires after the reader's stamp trigger (pdesc_reader_stamp_upd sorts before provider_description_learning), so a failure
--   is recorded under the reader that wrote the read.
-- Cost: the function adds one primary-key read of a one-row table (about 0.001 ms; security.pdesc_reader_behaviour_v1 never scans the reads). The function already reads the validation text and the settings.
-- Alternative considered and NOT taken: stop the trigger recording the identity rules (provider_name_conflict, provider_name_not_proved, provider_subunit_source, wrong_host, provider_host_conflict) as learning failures, because no AI
--   call is made for them. It would not release the 313 failures already recorded (nothing is deleted), so Sydney and the 73 other identity holds would stay blocked; and it would leave a failure of any other kind under an older reader
--   blocking the newer one. The reader in the signature is the smaller and complete change.
-- Consequences, read and checked:
--   (a) Every recorded failure of official_about has a signature without the reader, so after this change none of the 313 failed outcomes matches a check (once, whatever the reader). That memory is only consulted AFTER the picker
--       has decided a provider is eligible: security.provider_description_selection_v1 still parks a held or rejected read on the same stored page (unchanged_unsuitable_evidence), waits pdesc.recheck_days (retry_wait), parks policy holds,
--       and offers identity holds only through pdesc.identity_reeval_rules; the lease still holds and skips on the queue cap, the concurrency, the scope and the manual locks; the reservation still refuses unchanged_rejected_evidence
--       by content hash, independent of the signature. So no provider is released that the picker does not offer. Spend is still bounded by pdesc.ai_usd_max (US$1 lifetime), the daily lane guard (guard_provider_description),
--       pdesc.queue_cap, pdesc.queue_per_run and pdesc.tries, in the reservation, which is unchanged. Read on 10 Nov 2026: lane spend US$0.0799, today US$0.0710.
--   (b) Nothing is deleted or changed in pipeline.ops_remedy_outcomes, pipeline.ops_remedy_knowledge or the reads. The old outcomes stay as the history of what each reader decided.
--   (c) A read held recovery_knowledge_unchanged_failure by the false refusal (Sydney, 14939e4a, provider 68022bdf) is offered again by the picker (change 2), once, because the signature is new; it is read from the stored page (no Firecrawl,
--       no new fetch) and meets the same identity proof, reservation and ceilings. A repeat read is not offered twice without a new failure signature: if the memory matches again the hold is parked as before.
--   (d) Deferred, not done here (QA note 2): the reader stamp is last-write-wins, and the recorder uses the running reader, not the stamp of the read it records. While two worker versions overlap, a failure of the older version can be recorded
--       under the newer stamp. It needs a second signature form that takes the stamp of the read (a new function or argument that the picker and lease would also call), which is not a few lines. Bound: one extra re-read per hold per flip, as 20261109185000
--       states. Owner: the release controller (to schedule as its own change after #980). Nothing in this change makes it worse.
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.provider_description_signature_v1(text,text,text) b48bbd5b345f2e7b9a1fc6df9958163b -> 2002daebe8768dc9504b8c53131472e0
--   security.provider_description_selection_v1(jsonb) 41c9e5ffaba74453c699fd84e9135648 -> 7f4a7aa8fea1b81bbf8c1742d749502e
-- Each edit is guarded: the migration stops, and nothing is applied, if a live body is neither the one it replaces nor the one it writes; applying it twice changes nothing. The text before is kept in supabase/held/pdesc_signature_reader_forward_recovery.sql.
-- Depends on 20261109185000 (security.pdesc_reader_behaviour_v1) and 20261110040000 (the picker text this change edits): this change refuses until both are applied.
-- Consumer API (G3): not touched (security.provider_description_signature_v1 is an internal recovery-memory function, not a website, Zoho or api object; no table or column the consumer API reads is changed).
-- No operational number is written into code (G2) and no setting or job is added (G1).
-- Replaces: the body of security.provider_description_signature_v1 (the signature without the running reader) and the parking of a no-AI recovery-knowledge refusal in security.provider_description_selection_v1; the earlier text is kept in supabase/held/pdesc_signature_reader_forward_recovery.sql
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_signature_v1(text,text,text)'), ('security.pdesc_reader_behaviour_v1()'), ('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'),
                                 ('security.ops_learning_retry_check_v1(text,text,text)'), ('security.provider_description_selection_v1(jsonb)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing (apply 20261109185000 first)', r.sig; end if;
  end loop;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.provider_description_signature_v1(text,text,text)', 'b48bbd5b345f2e7b9a1fc6df9958163b', '2002daebe8768dc9504b8c53131472e0',
array[
$old$pdesc.superlatives')),''))$old$],
array[
$new$pdesc.superlatives')),'')||coalesce('|'||security.pdesc_reader_behaviour_v1(),''))$new$]);

select pg_temp.edit_all('security.provider_description_selection_v1(jsonb)', '41c9e5ffaba74453c699fd84e9135648', '7f4a7aa8fea1b81bbf8c1742d749502e',
array[
$old$is distinct from coalesce(v_cur,'')) then 'unchanged_unsuitable_evidence'$old$,
$old$,false)) then 'retry_wait'$old$],
array[
$new$is distinct from coalesce(v_cur,'')) and not (r.state='held' and r.rule='recovery_knowledge_unchanged_failure' and coalesce(r.ai_calls,0)=0 and coalesce(r.reserved_usd,0)=0 and a.id is not null and r.content_hash=coalesce(a.content_hash,a.id::text) and coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',p.id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),(select model_identifier from pipeline.central_ai_settings where id=1),coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) and not exists(select 1 from pipeline.provider_description_reads z where z.provider_id=p.id and z.state='rejected' and z.content_hash=coalesce(a.content_hash,a.id::text))) then 'unchanged_unsuitable_evidence'$new$,
$new$,false)) and not (r.state='held' and r.rule='recovery_knowledge_unchanged_failure' and coalesce(r.ai_calls,0)=0 and coalesce(r.reserved_usd,0)=0 and a.id is not null and r.content_hash=coalesce(a.content_hash,a.id::text) and coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',p.id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),(select model_identifier from pipeline.central_ai_settings where id=1),coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) and not exists(select 1 from pipeline.provider_description_reads z where z.provider_id=p.id and z.state='rejected' and z.content_hash=coalesce(a.content_hash,a.id::text))) then 'retry_wait'$new$]);
