-- CF-247, 7 Oct 2026: automatic adapter build, part 3 of 6: qualify a built adapter and list the fields ready to admit.
-- Platform Admin, 7 Oct 2026 22:05: the build stops at Ready to admit; admitting stays a separate, deliberate step (part 5) under the standing rule that
-- a passing check never auto-activates. Fields are ready when they pass the admit rule AND agree with held values (90%+ on 3+ courses, read on 5+ pages).
-- Central pages found among stored links are attached; they wait for approval in Layer 4 as before. Called by the step function (part 4).

create or replace function security.adapter_autobuild_qualify_v1(p_build_id uuid)
returns void language plpgsql security definer set search_path to '' as $f$
declare b pipeline.adapter_autobuilds%rowtype; v_q jsonb; v_admit text[]; v_held jsonb; v_f text; v_x jsonb; v_central jsonb; v_s record; v_why text;
begin
  select * into b from pipeline.adapter_autobuilds where id = p_build_id and status = 'qualifying';
  if not found then return; end if;
    v_q := security.adapter_qualify_one_v1(b.provider_id, coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5), coalesce((security.firecrawl_setting('qualify_agree_share') #>> '{}')::numeric, 0.9));
    v_admit := '{}'; v_held := '{}'::jsonb;
    foreach v_f in array array['intakes', 'english', 'fee', 'delivery'] loop
      v_x := v_q->'fields'->v_f;
      if v_x is null then continue; end if;
      v_why := case
        when not coalesce((v_x->>'pass')::boolean, false) then coalesce(v_x->>'why', 'does not pass')
        when coalesce((v_x->>'read')::int, 0) < 5 then 'read on fewer than 5 pages'
        when coalesce((v_x->>'agree')::int, 0) < 3 or v_x->>'agree_share' is null then 'not enough held values to check against (needs 3 agreeing courses)'
        when (v_x->>'agree_share')::numeric < 0.9 then 'agrees on under 90% of checked courses' end;
      if v_why is null then v_admit := v_admit || v_f; else v_held := v_held || jsonb_build_object(v_f, v_why); end if;
    end loop;
    v_central := '[]'::jsonb;
    for v_s in select distinct on (k.kind) k.kind, u.url from pipeline.coverage_provider_urls u
                 cross join lateral (select case
                   when u.url ~* '(key-?dates|academic-?calendar|semester-?dates|term-?dates|important-?dates|principal-?dates)' then 'intake_calendar'
                   when u.url ~* '(international.*(fee|tuition)|(fee|tuition).*international|fee-?schedule|tuition-?fees)' then 'fee_schedule'
                   when u.url ~* '(english-?language-?requirement|english-?requirement|english-?proficiency)' then 'english_policy' end kind) k
                where u.provider_id = b.provider_id and k.kind is not null
                  and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = b.provider_id and f.kind = k.kind)
                order by k.kind, length(u.url) loop
      begin
        perform public.admin_provider_central_page('add', jsonb_build_object('provider_id', b.provider_id, 'kind', v_s.kind, 'url', v_s.url, 'reason', 'Automatic build: found among the provider''s stored links'));
        v_central := v_central || jsonb_build_object('kind', v_s.kind, 'url', v_s.url);
      exception when others then null;
      end;
    end loop;
    update pipeline.adapter_autobuilds set status = 'done', result = result || jsonb_build_object('qualify', v_q, 'ready', to_jsonb(v_admit), 'held', v_held, 'central_pages', v_central),
           note = case when cardinality(v_admit) > 0 then 'Ready to admit: ' || array_to_string(v_admit, ', ') || '. A Platform Admin admits them.' else 'Built and testing; no field passed the checks yet.' end, updated_at = now() where id = b.id;
end $f$;
revoke all on function security.adapter_autobuild_qualify_v1(uuid) from public, anon, authenticated;
