CREATE OR REPLACE FUNCTION security.ranking_edition_check_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 3 Nov 2026 (direction 09:32 §5, ranking refresh): each active ranking system (ranking.systems) is compared with its publisher's
-- release calendar (ranking.edition_calendar) and its last file import. A newer edition not held, or an import older than
-- ranking.import_max_age_days (or none), opens or updates one integration issue (fingerprint ranking_edition:<code>) for a person to import the
-- licensed file in Rankings & statistics › Datasets. Nothing is fetched or imported. A system no longer behind marks its issue cleared.
declare v_grace int := security.pipeline_num_v1('ranking.edition_grace_days', 30)::int;
        v_age int := security.pipeline_num_v1('ranking.import_max_age_days', 400)::int;
        v_cal text[] := security.pipeline_list_v1('ranking.edition_calendar', '["qs_wur:6:1", "the_wur:10:1", "arwu:8:0"]');
        r record; i record; v_month int; v_off int; v_y int; v_expect int; v_held int; v_last timestamptz; v_why text[]; v_fp text;
        v_seen text[] := '{}'; v_out jsonb := '[]'::jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('ranking-edition-check')) then return jsonb_build_object('skipped', 'running'); end if;  -- fixed: lock key
  for r in select s.id, s.code, s.publisher_name, s.ranking_name, s.official_url from ranking.systems s where s.active order by s.code loop
    v_month := null; v_off := null; v_expect := null;
    select nullif(split_part(c, ':', 2), '')::int, coalesce(nullif(split_part(c, ':', 3), '')::int, 0) into v_month, v_off
      from unnest(v_cal) c where split_part(c, ':', 1) = r.code and split_part(c, ':', 2) ~ '^[0-9]{1,2}$' and split_part(c, ':', 3) ~ '^-?[0-9]*$' limit 1;
    if v_month between 1 and 12 then
      v_y := extract(year from now() at time zone 'UTC')::int;  -- fixed: the calendar year is counted in UTC
      v_expect := case when now() >= make_timestamptz(v_y, v_month, 1, 0, 0, 0, 'UTC') + make_interval(days => v_grace) then v_y else v_y - 1 end + v_off;
    end if;
    select max(e.edition_year) into v_held from ranking.editions e where e.system_id = r.id and e.status = 'accepted';
    select max(m.uploaded_at) into v_last from ranking.manual_imports m where m.system_id = r.id;
    v_why := '{}';
    if v_expect is not null and (v_held is null or v_held < v_expect) then
      v_why := v_why || ('edition ' || v_expect || ' is out by the publisher''s calendar; ' || coalesce('latest held ' || v_held, 'no edition held'));
    end if;
    if v_last is null or v_last < now() - make_interval(days => v_age) then
      v_why := v_why || ('last file import ' || coalesce(to_char(v_last, 'YYYY-MM-DD'), 'never') || ' (older than ' || v_age || ' days)');
    end if;
    if cardinality(v_why) > 0 then
      v_fp := 'ranking_edition:' || r.code;
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', v_fp,
        'title', r.ranking_name || ': a new edition to import', 'layer', 'Layer 1', 'subsystem', 'ranking.' || r.code,
        'failure', array_to_string(v_why, '; '),
        'expected', 'The latest edition published by ' || r.publisher_name || ' is imported from its licensed file (Rankings & statistics › Datasets). The platform does not fetch or import rankings.',
        'source', 'ranking-edition-check', 'validation_layer', 'V4',
        'evidence', jsonb_build_object('system', r.code, 'expected_edition', v_expect, 'held_edition', v_held, 'last_import', v_last, 'official_url', r.official_url),
        'severity', 'P2', 'root_cause_class', 'missing_dependency', 'workstream', 'A10'), 'ranking-edition-check');
      v_seen := v_seen || v_fp;
    end if;
    v_out := v_out || jsonb_build_object('system', r.code, 'expected', v_expect, 'held', v_held, 'last_import', v_last, 'issue', cardinality(v_why) > 0);
  end loop;
  for i in select x.id, x.fingerprint, x.condition_cleared_at, x.status from pipeline.integration_issues x
            where x.status <> 'closed' and x.fingerprint like 'ranking\_edition:%' and not (x.fingerprint = any (v_seen)) loop
    if i.condition_cleared_at is null then
      update pipeline.integration_issues set condition_cleared_at = now() where id = i.id;
      insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note)
      values (i.id, 'not_observed', i.status, i.status, 'ranking-edition-check', 'the edition is held and the import is recent; close after verification');
    end if;
  end loop;
  return jsonb_build_object('systems', v_out, 'issues', cardinality(v_seen));
end $function$
