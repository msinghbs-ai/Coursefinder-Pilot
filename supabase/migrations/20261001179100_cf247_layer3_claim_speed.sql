-- CF-247: speed up the Layer 3 English and intake claims (public.layer3_fact_claim_service). Measured on 1 Oct 2026:
-- a 40-item intake claim took 9.1 seconds and an English claim 4.7 seconds; calls through the API stop at 8 seconds, so
-- intake claims failed with "statement timeout" (18 between 07:00 and 08:30 UTC). Most of the time went on two checks
-- run as separate functions for each of about 15,000 read course pages (2.1 of 2.8 seconds in the page query):
--   security.coverage_identity_allowed(...)          -> the same rule written as a join on the country admission rules;
--   security.layer4_entity_or_parent_blocked(...)    -> the same rule (an operational block on the course or its
--                                                      provider) written against security.layer4_active_blocks.
-- The page query drops from 2.8 seconds to 0.15 seconds with the same pages chosen. Edited in place from the live
-- definition, only if its body is the one left by 20261001179000 (md5 guard).

do $claim$
declare s text; d text; v text;
  o3 text := $o3$security.coverage_identity_allowed(pg.provider_id, pg.identity_basis, case p_task_class when 'provider_intake_validation' then 'intakes' else 'english' end)$o3$;
  n3 text := $n3$exists (select 1 from catalogue.providers px join pipeline.coverage_admission_countries ax on ax.country_id=px.country_id and ax.active
                    where px.id=pg.provider_id and coalesce(ax.identities->(case p_task_class when 'provider_intake_validation' then 'intakes' else 'english' end) ? pg.identity_basis, false))$n3$;
  o4 text := $o4$and not security.layer4_entity_or_parent_blocked('course',pg.course_id,'operational')$o4$;
  n4 text := $n4$and not exists (select 1 from security.layer4_active_blocks bk where bk.block_scope='operational'
                         and ((bk.entity_type='course' and bk.entity_id=pg.course_id) or (bk.entity_type='provider' and bk.entity_id=co.provider_id)))$n4$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'layer3_fact_claim_service';
  v := md5(s);
  if v is distinct from '41679fa171837a67a990274c83aad306' then raise exception 'layer3_fact_claim_service changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o3, ''))) / length(o3) <> 1 then raise exception 'identity check not found once'; end if;
  if (length(d) - length(replace(d, o4, ''))) / length(o4) <> 1 then raise exception 'block check not found once'; end if;
  execute replace(replace(d, o3, n3), o4, n4);
end $claim$;
