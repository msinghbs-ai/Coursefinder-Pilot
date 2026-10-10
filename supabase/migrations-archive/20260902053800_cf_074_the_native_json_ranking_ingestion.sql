alter table ranking.observations
  add column if not exists overall_score_display text,
  add column if not exists overall_score_low numeric,
  add column if not exists overall_score_high numeric;

undefined

revoke all on function public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb) to service_role;
