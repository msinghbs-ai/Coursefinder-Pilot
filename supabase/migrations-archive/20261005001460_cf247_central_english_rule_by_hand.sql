-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 07:36): central English rule associated with universities.
-- The policy parser reads most central English pages attached at 07:50 as "no values" (rules in tables or prose by
-- level, for example James Cook, Lincoln, Vancouver Island, Sunshine Coast). A central rule can now be written out from
-- the attached page as levels and named courses. It is saved as a PROPOSAL only: it is approved, like any parsed policy,
-- in Layer 4 Review › Attributes, where the plan and the agreement check run first. An approved rule fills only courses
-- with no English requirement, so a course page reading comes first and a value entered by hand is never changed.
-- New function only. No text value in this file contains a semicolon.

create or replace function public.admin_provider_english_propose(p_provider_id uuid, p_rule jsonb, p_url text, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_id uuid; v_src uuid; v_ev uuid; v_defaults jsonb := '{}'::jsonb; v_ex jsonb := '[]'::jsonb; v_prop jsonb; k text; r jsonb; v_note text := btrim(coalesce(p_note, ''));
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  if coalesce(btrim(p_url), '') !~* '^https?://' then raise exception 'the central English page address is required'; end if;
  if length(v_note) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  -- one requirement: IELTS overall from 4 to 9 in halves, optional lowest band
  for k in select x from unnest(array['undergraduate', 'postgraduate']) x loop
    r := p_rule->k;
    continue when r is null;
    if (r->>'overall') !~ '^[4-9](\.[05])?$' or coalesce(r->>'min_band', '5') !~ '^[3-9](\.[05])?$' then raise exception 'the % rule needs an IELTS overall (and lowest band) from 4 to 9 in halves', k; end if;
    v_defaults := v_defaults || jsonb_build_object(k, jsonb_build_array(jsonb_build_object('test_code', 'IELTS', 'overall_score', (r->>'overall')::numeric,
                    'component_scores', case when r ? 'min_band' then jsonb_build_object('listening', (r->>'min_band')::numeric, 'reading', (r->>'min_band')::numeric, 'writing', (r->>'min_band')::numeric, 'speaking', (r->>'min_band')::numeric) else '{}'::jsonb end,
                    'quote', left(coalesce(r->>'quote', ''), 400))));
  end loop;
  for r in select e from jsonb_array_elements(coalesce(p_rule->'named', '[]'::jsonb)) e loop
    if length(btrim(coalesce(r->>'name', ''))) < 4 or (r->>'overall') !~ '^[4-9](\.[05])?$' or coalesce(r->>'min_band', '5') !~ '^[3-9](\.[05])?$' then raise exception 'each named course needs a name and an IELTS overall (and lowest band) from 4 to 9 in halves'; end if;
    v_ex := v_ex || jsonb_build_array(jsonb_build_object('name', btrim(r->>'name'), 'level', null, 'reqs', jsonb_build_array(jsonb_build_object('test_code', 'IELTS', 'overall_score', (r->>'overall')::numeric,
              'component_scores', case when r ? 'min_band' then jsonb_build_object('listening', (r->>'min_band')::numeric, 'reading', (r->>'min_band')::numeric, 'writing', (r->>'min_band')::numeric, 'speaking', (r->>'min_band')::numeric) else '{}'::jsonb end,
              'quote', left(coalesce(r->>'quote', ''), 400)))));
  end loop;
  if v_defaults = '{}'::jsonb and jsonb_array_length(v_ex) = 0 then raise exception 'give at least one level rule or named course'; end if;
  v_prop := jsonb_build_object('parser', 'written out from the central page', 'style', case when v_defaults = '{}'::jsonb then 'named_courses' else 'level_default' end,
                               'defaults', v_defaults, 'exceptions', v_ex, 'named', '[]'::jsonb, 'caveats', '[]'::jsonb, 'signals', '[]'::jsonb, 'conflicts', '[]'::jsonb);
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
  values (p_provider_id, 'english_policy', btrim(p_url), 'Central English page given by a Platform Admin', 9, 'manual', 'found')
  on conflict on constraint provider_fact_sources_key do nothing;
  select id, evidence_id into v_src, v_ev from pipeline.provider_fact_sources where provider_id = p_provider_id and kind = 'english_policy' and url = btrim(p_url);
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status, decision_note)
  values (p_provider_id, v_src, 'english_policy', 'written out from the central page', md5(v_prop::text), v_ev, btrim(p_url), v_prop->>'style', v_prop, 'proposed', left(v_note, 500))
  on conflict (fact_source_id, parser, content_hash) do nothing
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', 'english_rule_proposed', btrim(p_url), jsonb_build_object('decision', 'Decision 254', 'proposal_id', v_id, 'provider_id', p_provider_id, 'rule', p_rule, 'note', v_note), auth.uid());
  return jsonb_build_object('id', v_id, 'note', 'Approve or reject it in Layer 4 Review › Attributes.');
end $f$;
revoke all on function public.admin_provider_english_propose(uuid, jsonb, text, text) from public, anon;
grant execute on function public.admin_provider_english_propose(uuid, jsonb, text, text) to authenticated;
