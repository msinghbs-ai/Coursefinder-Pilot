-- HELD (not a migration): forward recovery for 20261110200000 (planner unit costs, IQ-00355). It restores security.enrich_unit_costs_v1 byte for byte to the body read live on 10 Nov 2026 (the slower per-row form).
-- Run only if the Platform Admin decides to take the change back. Guarded by the md5 of what is live now (the edited text or the original); a body that is neither stops it. Nothing is dropped or deleted.

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.enrich_unit_costs_v1()'::regprocedure);
begin
  if md5(v_src) = 'f10198f02de958119baefd490931c258' then raise notice 'already the original'; return; end if;
  if md5(v_src) <> '00d1b42bc96af737982c3ba77a384036' then raise exception 'live security.enrich_unit_costs_v1() differs from both texts this recovery knows (body md5 %)', md5(v_src); end if;
  execute $ddl$
create or replace function security.enrich_unit_costs_v1()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- what each kind of step actually used, last 30 days (estimates follow the platform, nothing is typed in)
  with u as (select security.fc_purpose_group_v1(x.purpose) g, x.purpose, x.units, x.provider_id from pipeline.coverage_vendor_usage x where x.at > now() - interval '30 days')  -- fixed: estimate window
  select jsonb_build_object(
    'site_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g in ('other', 'central')), 0), 1),
    'search_credits_per_course', round(coalesce((select sum(units) / nullif(count(*), 0) from u where purpose = 'course_link_search'), 0), 2),
    'adapter_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g = 'reads'), 0), 1),
    'scholarship_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g = 'scholarships'), 0), 1),
    'enrich_usd_per_item', coalesce((select round(avg(coalesce(e.cost_usd, 0)), 5) from pipeline.field_enrich_items e where e.updated_at > now() - interval '30 days' and e.state in ('filled', 'skipped', 'review', 'failed')), 0),
    'adapter_usd', coalesce((select round(sum(d.cost_usd) / nullif(count(distinct d.provider_id), 0), 4) from pipeline.uni_adapter_drafts d where d.created_at > now() - interval '30 days'), 0),
    'scholarship_usd', coalesce((select round(sum(s.cost_usd) / nullif(count(distinct s.provider_id), 0), 4) from pipeline.scholarship_ai_extractions s where s.at > now() - interval '30 days'), 0))
$function$
$ddl$;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.enrich_unit_costs_v1()'::regprocedure)) <> 'f10198f02de958119baefd490931c258' then raise exception 'the recovery did not restore the original body'; end if;
end $g$;
