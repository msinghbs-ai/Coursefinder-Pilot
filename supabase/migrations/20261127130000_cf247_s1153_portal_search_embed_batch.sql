-- CF-247 s1153 follow-up (S2-Build; Platform Admin 25 Nov 2026 17:13, portal search backfill): portal_search.embed_batch 150 -> 25.
-- Measured live 25 Nov 2026 18:51 to 19:55 AEDT: the backfill embedded 21,004 of 34,362 courses (1.6 million tokens, US$0.032), then every
-- public.svc_portal_search_embed_record call timed out (29 calls; "canceling statement due to statement timeout", after 16 to 27 s) because
-- writing 150 vectors into the growing HNSW index (search.course_embeddings_hnsw_idx) now takes longer than the service statement time-out.
-- 900 jobs reached their 3 tries and are marked failed; security.portal_search_enqueue_v1 queues their courses again (a failed job does not
-- block a new one), so nothing is lost. 25 vectors per call keeps each write well inside the time-out; the worker still loops batches for up
-- to 100 s per call. Changed through the settings pattern with its reason, inside the setting's range (20 to 500).
-- G1: no job. G2: a setting value, logged. G3: nothing the consumer API reads. Manual locks untouched. Nothing dropped.
-- Replaces: portal_search.embed_batch 150 (now 25).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the setting row

update pipeline.platform_toolset_settings set value = to_jsonb(25), updated_at = now(),
       reason = 'CF-247 s1153 follow-up: 150 vectors per write timed out once the vector index passed about 21,000 rows; 25 per write'
 where toolset_key = 'portal_search' and key = 'embed_batch' and value = to_jsonb(150);
insert into pipeline.admin_control_events (area, action, target, detail, actor)
values ('settings', 'migration', 'pipeline.platform_toolset_settings', jsonb_build_object('key', 'portal_search.embed_batch', 'before', 150, 'after', 25,
        'reason', 'vector writes of 150 timed out (29 calls, 25 Nov 2026 19:33 to 19:55 AEDT)', 'migration', '20261127130000'), security.system_actor_id());

do $p$
begin
  if security.portal_search_num_v1('embed_batch', 150) <> 25 then raise exception 'post-check: portal_search.embed_batch is not 25'; end if;
end $p$;
