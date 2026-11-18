-- CF-247 S2-BOOST-Providers (Platform Admin 18 Nov 2026 16:56 and 17:03: resolve the 88 held university descriptions, the 89 held
-- scholarships and the 312 campus localities by deterministic rules promoted into the platform; no table or column is added).
-- What was read live (17:00 to 17:40 AEDT, SELECT only):
--   * Layer 4 > University descriptions shows 751 items: 88 are university descriptions, 663 are course descriptions (the Course Module's).
--     Of the 88, 46 fail the first-sentence name check (28 at once, 18 after the refused sentences are left out), 26 keep fewer than
--     pdesc.min_sentences sentences, the rest are topic and page refusals. A name written as its initials ("ICMS is a higher education
--     institution ...") or one of several trading names held in one field ("A; B; C") is not among the name forms.
--   * Layer 4 > Held scholarships: 89 pending; 82 have never had the AI re-check (pipeline.scholarship_ai_reviews.recheck is null). The
--     re-check was queued once, by a data update in 20261019130000, for the items of that day; nothing queues it for an item held later.
--   * Layer 4 > Campus locality: 312 campuses in 94 Australian postcodes. The share the 90% rule tests is the share of the postcode's AREA
--     inside the Significant Urban Area (ABS postcode correspondence), so a regional city's postcode fails it: Armidale 2350 is 6% by area
--     and 82% by mesh blocks, Canberra 2601 is 56% and 94%. The same ABS rows hold the mesh-block count of each part.
-- 1 Rule pdesc-name-forms-v2: security.pdesc_name_forms_v1 also gives each name of a semicolon-separated list and the initials of a
--   name's capitalised words (four letters or more). The validation, the machine gate, the word lists and the admission are not changed;
--   the existing settlement admits a held reading only when every one of its checks then passes (never over a description a person wrote).
-- 2 Rule l4-held-sch-recheck-v1 (job scholarship-recheck-queue, hourly at minute 9): every pending held scholarship page that has a stored
--   copy and no re-check is queued for the existing AI re-check (job scholarship-recheck, coverage-sweep mode scholarship_recheck, the
--   first model of the scholarship chain through Models & services). The re-check quotes who may apply and the value from the stored
--   page and records a recommendation; it publishes and rejects nothing.
-- 3 Rule l4-campus-locality-v1 (job layer4-campus-locality, hourly at minute 57): a postcode is settled through the existing Inbox
--   decision, under the system automation account, when (a) one Significant Urban Area holds at least destination.postcode_mesh_min_share
--   of the postcode's mesh blocks, (b) the mesh blocks outside every Significant Urban Area do, or (c) one Significant Urban Area holds
--   the most mesh blocks, at least destination.postcode_mesh_name_min_share, and every waiting campus in the postcode gives that
--   area's own name as its suburb. Every other postcode waits for a person, as before.
-- G1: both jobs are catalogued. G2: switches, shares and batches are settings. G3: no consumer API object is changed.
-- Replaces: security.pdesc_name_forms_v1 (it knew neither a semicolon-separated trading name nor a name's initials)
-- Retires: nothing

set local lock_timeout = '5s';

-- 1 ------------------------------------------------------------------------------------------------------------ pdesc-name-forms-v2
do $g$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.pdesc_name_forms_v1(text[])'::regprocedure) <> '655c3643ba0b4c25bdc7bfe4fa63c22c'
     and (select position('pdesc-name-forms-v2' in p.prosrc) from pg_proc p where p.oid = 'security.pdesc_name_forms_v1(text[])'::regprocedure) = 0 then
    raise exception 'security.pdesc_name_forms_v1 is not the text of 20261112023700; nothing applied';
  end if;
end $g$;

create or replace function security.pdesc_name_forms_v1(p_names text[]) returns text[]
language sql immutable set search_path to '' as $f$
  -- CF-247 F-PDESC (20261112023700): the forms a provider's own name is written in, for the first-sentence check
  -- pdesc-name-forms-v2 (20261118203000): each name of a semicolon-separated list of trading names, and a name's initials
  select coalesce(array_agg(distinct f) filter (where length(f) >= 3), '{}'::text[])
    from (select btrim(regexp_replace(replace(v, '&', ' and '), '\s+', ' ', 'g')) f
            from unnest(coalesce(p_names, '{}'::text[])) n0
            cross join lateral unnest(array[n0] || regexp_split_to_array(n0, '\s*;\s*')) n
            cross join lateral unnest(array[n] || string_to_array(n, ',')) part
            cross join lateral (select btrim(regexp_replace(part, '\s*\([^)]*\)', '', 'g')) bare) b
            cross join lateral (select btrim(regexp_replace(b.bare, '(\s*,?\s+(pty\.?\s*ltd\.?|proprietary\s+limited|limited|ltd\.?|inc\.?|incorporated|llc))+\s*$', '', 'i')) plain) c
            cross join lateral unnest(array[btrim(part), b.bare, c.plain,
                 -- the initials of the capitalised words of one whole name ("International College of Management, Sydney" gives ICMS)
                 case when part = n and position(';' in n) = 0 then
                   (select case when length(string_agg(left(w, 1), '' order by o)) >= 4  -- fixed: shorter initials are everyday words
                                then string_agg(left(w, 1), '' order by o) end
                      from regexp_split_to_table(regexp_replace(c.plain, '[^A-Za-z ]', ' ', 'g'), '\s+') with ordinality t(w, o)
                     where w ~ '^[A-Z]') end]) v
           where nullif(btrim(coalesce(part, '')), '') is not null) z
$f$;
comment on function security.pdesc_name_forms_v1(text[]) is 'CF-247 F-PDESC (20261112023700; pdesc-name-forms-v2 20261118203000): a provider''s name forms (each semicolon- or comma-separated name, no parenthesised part, no legal suffix, & as and, and the initials of a whole name when four letters or more) for the first-sentence check in provider_description_validate_v1.';
revoke all on function security.pdesc_name_forms_v1(text[]) from public, anon, authenticated;

-- settings ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'scholarship.held_recheck_rule_on', 'Held scholarships: queue the AI re-check by rule',
  '1: every hour, rule l4-held-sch-recheck-v1 queues the AI re-check for each held scholarship page that has a stored copy and no re-check yet. The re-check quotes who may apply and the value and records a recommendation; it publishes and rejects nothing. 0: no held page is queued.',
  'number', '1'::jsonb, 0, 1, 'switch', 327, 'CF-247 S2-BOOST-Providers, Platform Admin 18 Nov 2026 17:03 item 2', 'Scholarships', 'security.scholarship_recheck_queue_rule_v1, job scholarship-recheck-queue'),
 ('pipeline', 'batch.scholarship_recheck_queue', 'Held scholarship pages queued for the re-check per run',
  'How many held scholarship pages one hourly run of scholarship-recheck-queue queues. Job scholarship-recheck then reads batch.scholarship_recheck of them every two minutes.',
  'number', '120'::jsonb, 1, 1000, 'pages', 328, 'CF-247 S2-BOOST-Providers, Platform Admin 18 Nov 2026 17:03 item 2', 'Scholarships', 'job scholarship-recheck-queue'),
 ('pipeline', 'destination.campus_locality_rule_on', 'Campus locality: settle postcodes by rule',
  '1: every hour, rule l4-campus-locality-v1 settles a campus postcode whose mesh blocks sit in one Significant Urban Area (or outside every one), or whose campuses all give the area''s own name as their suburb. Every other postcode waits in Layer 4 for a person. 0: only a person decides.',
  'number', '1'::jsonb, 0, 1, 'switch', 1864, 'CF-247 S2-BOOST-Providers, Platform Admin 18 Nov 2026 17:03 item 3', 'Destination data', 'security.campus_locality_rule_v1, job layer4-campus-locality'),
 ('pipeline', 'destination.postcode_mesh_min_share', 'Campus locality: mesh-block share for a match by rule',
  'The share of a postcode''s ABS mesh blocks that one Significant Urban Area (or the area outside every one) must hold for rule l4-campus-locality-v1 to settle the postcode on that alone. Mesh blocks follow where people live; the area share does not.',
  'number', '0.9'::jsonb, 0.5, 1, 'share (0 to 1)', 1865, 'CF-247 S2-BOOST-Providers, Platform Admin 18 Nov 2026 17:03 item 3', 'Destination data', 'security.campus_locality_rule_candidates_v1'),
 ('pipeline', 'destination.postcode_mesh_name_min_share', 'Campus locality: mesh-block share when the suburb is the area''s name',
  'The smaller mesh-block share that is enough when every waiting campus in the postcode gives the Significant Urban Area''s own name as its suburb and that area holds more of the postcode''s mesh blocks than any other part.',
  'number', '0.5'::jsonb, 0.5, 1, 'share (0 to 1)', 1866, 'CF-247 S2-BOOST-Providers, Platform Admin 18 Nov 2026 17:03 item 3', 'Destination data', 'security.campus_locality_rule_candidates_v1'),
 ('pipeline', 'destination.campus_locality_rule_batch', 'Campus locality: postcodes settled per run',
  'How many waiting postcodes one hourly run of layer4-campus-locality may settle.',
  'number', '200'::jsonb, 1, 2000, 'postcodes', 1867, 'CF-247 S2-BOOST-Providers, Platform Admin 18 Nov 2026 17:03 item 3', 'Destination data', 'job layer4-campus-locality')
on conflict (toolset_key, key) do nothing;

-- 2 --------------------------------------------------------------------------------------------------------- l4-held-sch-recheck-v1
create or replace function security.scholarship_recheck_queue_rule_v1(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_lim int := least(greatest(coalesce(p_limit, 0), 0), 1000);  -- fixed: upper bound of the setting's range
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_n int := 0; v_no_copy int;
begin
  if security.pipeline_num_v1('scholarship.held_recheck_rule_on', 0) < 1 or v_lim = 0 then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:held_sch_recheck_rule'));  -- fixed: one run at a time
  with pick as (
    select r.id from pipeline.scholarship_ai_reviews r
     where r.status = 'pending' and r.recheck is null and nullif(btrim(coalesce(r.storage_path, '')), '') is not null
     order by r.created_at, r.id limit v_lim for update skip locked),
  upd as (
    update pipeline.scholarship_ai_reviews r
       set recheck = jsonb_build_object('state', 'queued', 'queued_at', now(), 'scope', 'rule l4-held-sch-recheck-v1')
      from pick where r.id = pick.id returning r.id)
  select count(*) into v_n from upd;
  select count(*) into v_no_copy from pipeline.scholarship_ai_reviews r
   where r.status = 'pending' and r.recheck is null and nullif(btrim(coalesce(r.storage_path, '')), '') is null;
  if v_n > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'rule_execute', 'l4-held-sch-recheck-v1', jsonb_build_object('queued', v_n, 'held_without_stored_copy', v_no_copy), v_sys);
  end if;
  return jsonb_build_object('ok', true, 'queued', v_n, 'held_without_stored_copy', v_no_copy,
    'pending', (select count(*) from pipeline.scholarship_ai_reviews where status = 'pending'));
end $function$;
revoke all on function security.scholarship_recheck_queue_rule_v1(integer) from public, anon, authenticated;
comment on function security.scholarship_recheck_queue_rule_v1(integer) is 'CF-247 rule l4-held-sch-recheck-v1 (Platform Admin 18 Nov 2026 17:03): queues the existing AI re-check for held scholarship pages that have a stored copy and no re-check; the re-check records quotes and a recommendation and publishes or rejects nothing.';

-- 3 ---------------------------------------------------------------------------------------------------------- l4-campus-locality-v1
create or replace function security.campus_suburb_norm_v1(p text) returns text
language sql immutable set search_path to '' as $f$
  -- a suburb or area name as letters only, lower case ("PORT  MACQUARIE" and "Port Macquarie" are the same place)
  select regexp_replace(lower(coalesce(p, '')), '[^a-z]', '', 'g')
$f$;
revoke all on function security.campus_suburb_norm_v1(text) from public, anon, authenticated;
comment on function security.campus_suburb_norm_v1(text) is 'CF-247 rule l4-campus-locality-v1: a suburb or area name as lower-case letters only, for comparing a campus suburb with a locality name.';

create or replace function security.campus_locality_rule_candidates_v1()
returns table(country_code text, postcode text, ref text, campuses integer, basis text, locality_id uuid, locality text, geography_code text, mesh_share numeric)
language sql stable security definer set search_path to '' as $function$
  with o as (
    select o.country_code, o.postcode, o.campus_id, security.campus_suburb_norm_v1(k.city) suburb
      from security.destination_campus_locality_open_v1(null) o join catalogue.campuses k on k.id = o.campus_id
     where o.country_code = 'AU'),
  pc as (select o.country_code, o.postcode, count(*)::int campuses, min(o.campus_id::text) ref, array_agg(distinct o.suburb) suburbs from o group by 1, 2),
  s as (
    select a.postcode, a.sua_code, a.sua_name, a.mesh_blocks, sum(a.mesh_blocks) over (partition by a.postcode) tot,
           row_number() over (partition by a.postcode order by a.mesh_blocks desc, a.sua_code) rk
      from destination.abs_postcode_sua_shares a
     where a.boundary_vintage = (select max(x.boundary_vintage) from destination.abs_postcode_sua_shares x where x.postcode = a.postcode)),
  t as (
    select pc.*, s.sua_name, s.mesh_blocks::numeric / nullif(s.tot, 0) mshare, l.id locality_id, l.name locality, l.geography_code
      from pc join s on s.postcode = pc.postcode and s.rk = 1
      left join destination.localities l on l.country_code = 'AU' and l.geography_type = 'SUA' and l.geography_code = s.sua_code
           and exists (select 1 from destination.locality_postcodes p where p.country_code = 'AU' and p.postcode = pc.postcode and p.locality_id = l.id))
  select t.country_code, t.postcode, t.ref, t.campuses,
         case when t.locality_id is not null and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_min_share', 0.9) then 'mesh_share'
              when t.locality_id is null and t.sua_name ilike 'Not in any%' and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_min_share', 0.9) then 'outside'
              when t.locality_id is not null and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_name_min_share', 0.5)
                   and not exists (select 1 from unnest(t.suburbs) u
                                    where u = '' or u <> all (select security.campus_suburb_norm_v1(x) from regexp_split_to_table(t.locality, '\s+-\s+') x)) then 'suburb_name'
              else 'hold' end,
         t.locality_id, t.locality, t.geography_code, round(t.mshare, 4)
    from t
$function$;
revoke all on function security.campus_locality_rule_candidates_v1() from public, anon, authenticated;
comment on function security.campus_locality_rule_candidates_v1() is 'CF-247 rule l4-campus-locality-v1: each waiting Australian campus postcode with the Significant Urban Area that holds most of its ABS mesh blocks and the basis on which the rule may settle it (mesh_share, outside, suburb_name) or hold. Read only.';

create or replace function security.campus_locality_rule_v1(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare w record; v_prev text; v_res jsonb;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_lim int := least(greatest(coalesce(p_limit, 0), 0), 2000);  -- fixed: upper bound of the setting's range
        v_ok jsonb := '{}'::jsonb; v_campuses int := 0; v_fail int := 0;
begin
  if security.pipeline_num_v1('destination.campus_locality_rule_on', 0) < 1 or v_lim = 0 then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:campus_locality_rule'));  -- fixed: one run at a time
  for w in select c.* from security.campus_locality_rule_candidates_v1() c where c.basis <> 'hold' order by c.postcode limit v_lim loop
    v_prev := current_setting('request.jwt.claim.sub', true);
    perform set_config('request.jwt.claim.sub', v_sys::text, true);
    begin
      v_res := security.layer4_campus_locality_inbox_decide_v1(w.ref, case when w.basis = 'outside' then 'no_locality' else 'choose_locality' end,
        case when w.basis = 'outside' then null else w.geography_code end,
        left(format('[rule l4-campus-locality-v1] %s Approved by Platform Admin 18 Nov 2026 17:03',
          case w.basis
            when 'mesh_share' then format('%s holds %s%% of the mesh blocks of postcode %s (ABS postcode correspondence).', w.locality, round(w.mesh_share * 100), w.postcode)
            when 'outside' then format('%s%% of the mesh blocks of postcode %s are outside every Significant Urban Area (ABS postcode correspondence).', round(w.mesh_share * 100), w.postcode)
            else format('Every waiting campus in postcode %s gives %s as its suburb, and %s holds %s%% of the postcode''s mesh blocks, more than any other part.', w.postcode, w.locality, w.locality, round(w.mesh_share * 100)) end), 1000));
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      if coalesce((v_res->>'ok')::boolean, false) then
        v_ok := jsonb_set(v_ok, array[w.basis], to_jsonb(coalesce((v_ok->>w.basis)::int, 0) + 1));
        v_campuses := v_campuses + w.campuses;
      else v_fail := v_fail + 1;
      end if;
    exception when others then perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true); v_fail := v_fail + 1;
    end;
  end loop;
  if v_ok <> '{}'::jsonb or v_fail > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'rule_execute', 'l4-campus-locality-v1', jsonb_build_object('postcodes_settled', v_ok, 'campuses', v_campuses, 'failed', v_fail), v_sys);
  end if;
  return jsonb_build_object('ok', true, 'postcodes_settled', v_ok, 'campuses', v_campuses, 'failed', v_fail,
    'waiting', (select count(*) from security.destination_campus_locality_open_v1(null)));
end $function$;
revoke all on function security.campus_locality_rule_v1(integer) from public, anon, authenticated;
comment on function security.campus_locality_rule_v1(integer) is 'CF-247 rule l4-campus-locality-v1 (Platform Admin 18 Nov 2026 17:03): settles a waiting campus postcode through the existing Layer 4 Inbox decision, under the system automation account, on the ABS mesh-block share or the campuses'' own suburb name; every other postcode waits for a person.';

-- jobs -------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('scholarship-recheck-queue', 'Layer 4', 33, 'Held scholarships: queue the AI re-check by rule',
  'Every hour at minute 9, when setting scholarship.held_recheck_rule_on is 1 (Settings > Pipeline settings > Scholarships): rule l4-held-sch-recheck-v1 queues up to batch.scholarship_recheck_queue held scholarship pages that have a stored copy and no re-check. Job scholarship-recheck reads them; the re-check records quotes and a recommendation and publishes or rejects nothing.',
  6, true),
 ('layer4-campus-locality', 'Layer 4', 34, 'Campus locality: settle postcodes by rule',
  'Every hour at minute 57, when setting destination.campus_locality_rule_on is 1 (Settings > Pipeline settings > Destination data): rule l4-campus-locality-v1 settles up to destination.campus_locality_rule_batch waiting campus postcodes on the ABS mesh-block share or the campuses'' own suburb name, through the Layer 4 Inbox decision. Every other postcode waits for a person.',
  6, true)
on conflict (jobname) do nothing;

select cron.schedule('scholarship-recheck-queue', '9 * * * *',
  'select security.scholarship_recheck_queue_rule_v1(security.pipeline_num_v1(''batch.scholarship_recheck_queue'', 120)::int)')
where not exists (select 1 from cron.job where jobname = 'scholarship-recheck-queue');

select cron.schedule('layer4-campus-locality', '57 * * * *',
  'select security.campus_locality_rule_v1(security.pipeline_num_v1(''destination.campus_locality_rule_batch'', 200)::int)')
where not exists (select 1 from cron.job where jobname = 'layer4-campus-locality');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'scholarship-recheck-queue', 'Layer 4', 'Scholarships', 'Held scholarships: the AI re-check queued by rule every hour', 'active', '{}', '20261118203000'),
  ('function', 'security.scholarship_recheck_queue_rule_v1', 'Layer 4', 'Scholarships', 'One run of rule l4-held-sch-recheck-v1', 'active', '{}', '20261118203000'),
  ('job', 'layer4-campus-locality', 'Layer 4', 'Destination data', 'Campus locality: postcodes settled by rule every hour', 'active', '{}', '20261118203000'),
  ('function', 'security.campus_locality_rule_v1', 'Layer 4', 'Destination data', 'One run of rule l4-campus-locality-v1', 'active', '{}', '20261118203000'),
  ('function', 'security.campus_locality_rule_candidates_v1', 'Layer 4', 'Destination data', 'The waiting campus postcodes and the basis the rule may settle each on', 'active', '{}', '20261118203000'),
  ('function', 'security.campus_suburb_norm_v1', 'Layer 4', 'Destination data', 'A suburb or area name as lower-case letters only', 'active', '{}', '20261118203000')
on conflict do nothing;

-- first runs -------------------------------------------------------------------------------------------------------------------------
create temp table cf_plan on commit drop as select * from security.campus_locality_rule_candidates_v1();
create temp table cf_run on commit drop as
  select security.campus_locality_rule_v1(security.pipeline_num_v1('destination.campus_locality_rule_batch', 200)::int) campus,
         security.scholarship_recheck_queue_rule_v1(security.pipeline_num_v1('batch.scholarship_recheck_queue', 120)::int) sch;

do $c$
declare v jsonb := (select campus from cf_run); s jsonb := (select sch from cf_run);
begin
  if (v->>'failed')::int > 0 then raise exception 'post-check: % postcodes could not be settled: %', v->>'failed', v; end if;
  if exists (select 1 from cf_plan p join destination.locality_postcodes lp on lp.country_code = p.country_code and lp.postcode = p.postcode
              where p.basis = 'hold' and lp.resolve_reason like '[rule l4-campus-locality-v1]%') then
    raise exception 'post-check: a postcode the rule holds for a person was settled by the rule';
  end if;
  if exists (select 1 from cf_plan p where p.basis in ('mesh_share', 'suburb_name')
                and not exists (select 1 from destination.locality_postcodes lp where lp.country_code = p.country_code and lp.postcode = p.postcode
                                   and lp.locality_id = p.locality_id and lp.is_primary_match)) then
    raise exception 'post-check: a settled postcode does not hold the locality the rule chose';
  end if;
  if exists (select 1 from pipeline.scholarship_ai_reviews r where r.recheck->>'scope' = 'rule l4-held-sch-recheck-v1' and (r.status <> 'pending' or r.storage_path is null)) then
    raise exception 'post-check: the re-check was queued for an item that is not held or has no stored copy';
  end if;
  if not ('ICMS' = any (security.pdesc_name_forms_v1(array['International College of Management, Sydney; Aspire English']))
          and 'Aspire English' = any (security.pdesc_name_forms_v1(array['International College of Management, Sydney; Aspire English']))
          and security.pdesc_name_forms_v1(array['Monash University Pty Ltd']) @> array['Monash University', 'Monash University Pty Ltd']
          and not ('UoQ' = any (security.pdesc_name_forms_v1(array['University of Queensland'])))) then
    raise exception 'post-check: name forms';
  end if;
  if (select count(*) from cron.job where jobname in ('scholarship-recheck-queue', 'layer4-campus-locality') and active) <> 2 then raise exception 'post-check: the jobs are not scheduled'; end if;
  raise notice 'Rule l4-campus-locality-v1 first run: %', v;
  raise notice 'Rule l4-held-sch-recheck-v1 first run: %', s;
end $c$;
