-- CF-247 F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): the switch the provider-description worker v0.59.14 reads to prove a joined quote fragment by fragment (PR "quote fragments"; the worker reads it through svc_worker_settings_v1).
--
-- Live evidence (project fxcwkweaxjtknorudmwp, 9 Nov 2026, SELECT only): of the 8 provider descriptions whose latest read is held quote_not_on_page, 7 quotes in 5 providers are quotes the model joined from separate page passages with an ellipsis (Australian Catholic University,
-- Lincoln University, Auscanus, NMIT, Tai Poutini). With the switch on, a joined quote is accepted only when every fragment is on the page by the whole-quote rule, long enough (pdesc.min_quote_chars) and in the page's order.
-- At most 3 of those providers can clear (ACU, NMIT, Tai Poutini), and only if their real pages carry the fragments in order.
-- This change adds the setting only, shipping 0 (off): the worker behaves as v0.59.13 until the Platform Admin turns it on on Settings > Pipeline settings, with a reason. A passing test never switches anything on by itself.
-- The setting is a pipeline-toolset number read by the worker as ws["reading.provider_quote_fragments_on"] (public.svc_worker_settings_v1 returns pipeline keys beginning enrich. or reading.), like reading.course_quote_fragments_on.
-- Replaces: nothing (a new setting, off)
-- Retires: nothing
-- Nothing is dropped or deleted. No function, job, table or consumer API object is touched (G3).

do $g$
begin
  if to_regprocedure('public.svc_worker_settings_v1()') is null then raise exception 'required public.svc_worker_settings_v1 is missing'; end if;
  -- fixed: the worker only receives pipeline keys beginning enrich. or reading.; the setting is useless otherwise
  if pg_get_functiondef('public.svc_worker_settings_v1()'::regprocedure) not like '%s.key like ''reading.%''%' then
    raise exception 'provider quote fragments: svc_worker_settings_v1 no longer returns reading.* settings';
  end if;
end $g$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'reading.provider_quote_fragments_on', 'Provider descriptions: prove a joined quote fragment by fragment',
  'On (1): a quote the model joined from separate passages of the official page with an ellipsis is accepted when every fragment is on the page exactly as a whole quote must be (same wording, case and word boundaries), has at least the shortest quote length (Provider descriptions: shortest quote) and follows the one before it in the page''s order; at least two fragments. A fragment missing, too short or out of order keeps the read held as quote_not_on_page. Off (0): the quote must be on the page whole, as before. Every other check, the identity proof, the manual locks and Layer 4 are unchanged.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1024, 'Provider descriptions', 'worker coverage-sweep provider_description (description.ts providerDescriptionSentences), read through svc_worker_settings_v1',
  'CF-247 F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): quotes joined with an ellipsis; ships off')
on conflict (toolset_key, key) do nothing;

do $c$
begin
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'reading.provider_quote_fragments_on'
                   and kind = 'number' and min_value is not null and max_value is not null and (value #>> '{}')::numeric between min_value and max_value
                   and coalesce(label, '') <> '' and coalesce(unit, '') <> '' and coalesce(used_by, '') <> '') then
    raise exception 'provider quote fragments post-check: the setting is missing, has no range, label, unit or used_by, or sits outside its range';
  end if;
end $c$;
