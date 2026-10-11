-- CF-247 v2.15.250 (11 Oct 2026 23:40): AI admission was paused at 23:31 because Qwen3 30B proved "who it is for" with quotes that do
-- not say it; worker v0.20.2 now requires the quote itself to name international (or domestic) students. Pages read while admission
-- was off were recorded but not applied, and the 6 scholarships held at the pause are read again (their holds were made by a person
-- and stay until a person releases them). Nothing is dropped or deleted.
insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, candidate_id, scholarship_id, provider_id, url, storage_path)
select a.model_code, a.prompt_version, q.run_kind, q.job_id, q.candidate_id, q.scholarship_id, q.provider_id, q.url, coalesce(q.storage_path, e.storage_path)
  from pipeline.scholarship_ai_queue q join pipeline.scholarship_ai_extractions e on e.id = q.extraction_id cross join security.scholarship_ai_active_v1() a
 where q.run_kind in ('admit', 'reread') and q.state = 'done' and q.done_at > '2026-10-11 12:00:00+00' and e.applied is null and e.error is null
   and not exists (select 1 from pipeline.scholarship_ai_queue q2 where q2.root_id = q.id or (q2.id <> q.id and q2.state in ('queued', 'leased') and (q2.candidate_id = q.candidate_id or q2.scholarship_id = q.scholarship_id)));
insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, scholarship_id, provider_id, url)
select a.model_code, a.prompt_version, 'reread', s.id, s.provider_id, coalesce(sp.final_url, sp.url)
  from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id cross join security.scholarship_ai_active_v1() a
 where s.id in ('12ec5c4d-0256-52bd-acb6-7383d10a8366', '44355ecd-76ac-5e43-a752-1886333ca747', 'ae7880a4-9d9f-55c4-ad81-f3bb11135d7b', 'c1b7d73a-4f5a-537a-afd6-7417c47e18b1', 'e79ec13f-c85b-5377-a7dc-454555259976', 'faa99117-a113-5373-a038-5b4d73348490')
   and not exists (select 1 from pipeline.scholarship_ai_queue q where q.scholarship_id = s.id and q.state in ('queued', 'leased'));
