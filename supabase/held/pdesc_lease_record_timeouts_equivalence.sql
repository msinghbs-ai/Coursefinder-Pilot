-- SELECT-only (no writes): run from a Supabase SQL session (project fxcwkweaxjtknorudmwp) as the database owner, BEFORE and AFTER migration 20261109233000
-- (provider-description lease and record time-outs). It never calls the lease, record or fire functions (they write production rows); it runs the read-only pieces
-- of public.svc_provider_description_next on the live data, one by one, and ends in an exception that carries the result, so nothing persists.
-- What it prints, as one line: PDESC LEASE TIMINGS {...}
--   1 pieces:  milliseconds for each read-only piece of the lease on the due reads (machine-blocked pass, stored-copy pass, identity re-offer, recovery-held select,
--              the pick as it is today (old_pick) and the lazy pick of the migration (new_pick), and the About-page candidates of the ten picked reads);
--   2 equal:   the OLD pick (the text of the live function, md5 54c8856ec36465059d41d71a5a5d462b, without its row lock) and the NEW pick compared for limits 3, 10, 100 and 1000,
--              in automatic (machine) mode and in manual mode: "same_order_keys" is true when the picks come in the same order by (country load, next try, created), and at limit 1000
--              "same_set" is true when both return exactly the same reads. (Reads that tie on all three values may come in either order, in the old text too, so a limited pick
--              compares by those values, not by id.) "mismatches" must be 0;
--   3 plans:   the same lease work repeated seven times on one connection with the default plan cache and with plan_cache_mode = force_custom_plan (milliseconds per repeat),
--              because a plpgsql statement can switch to a generic plan from its sixth run on a connection.
-- Expected after the migration: mismatches 0; every piece in "pieces" well under 2000 ms on a quiet database (target under 1500 ms for the stored-copy pass with the
-- migration's index, under 300 ms for new_pick). Timings on a busy minute (several cron jobs start together on the minute) are two to three times higher.
do $x$
declare
  t0 timestamptz; v_model text; v_ws text[]; v_stored jsonb; v_reoffer uuid[]; v_mach boolean; v_lim int; v_act jsonb; v_ko text[]; v_kn text[];
  v_old uuid[]; v_new uuid[]; v_ms_old int; v_ms_new int; v_eq jsonb := '[]'; v_bad int := 0; v_due int; v_pieces jsonb := '{}'; v_n int; i int; v_plans jsonb := '{}'; v_ms jsonb; v_mode text;
  function_ms int;
begin
  perform set_config('statement_timeout', '170s', true);
  select c.model_identifier into v_model from pipeline.central_ai_settings c where c.id = 1;
  select count(*) into v_due from pipeline.provider_description_reads r where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()));

  -- 1 pieces (automatic mode, as live)
  t0 := clock_timestamp();
  select count(*) into v_n from (select x.id, security.provider_description_machine_blocked_v1(x.provider_id) blk from pipeline.provider_description_reads x where (x.state='queued' and x.next_try_at<=now()) or (x.state='reading' and x.leased_until<now())) b where b.blk is not null;
  v_pieces := v_pieces || jsonb_build_object('machine_blocked_pass_ms', round(extract(epoch from clock_timestamp() - t0) * 1000), 'blocked_rows', v_n);
  t0 := clock_timestamp();
  v_ws := security.pdesc_about_like_patterns_v1();
  select coalesce(jsonb_object_agg(z.pid, to_jsonb(z.sid)), '{}'::jsonb) into v_stored from (
    select x.provider_id::text pid, security.provider_description_stored_v1(x.provider_id) sid
      from (select distinct o.provider_id from pipeline.provider_description_reads o where (o.state='queued' or (o.state='reading' and o.leased_until<now()))
               and exists (select 1 from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id=s.id where s.provider_id=o.provider_id and lower(a.source_url) like any (v_ws))
             offset 0) x) z where z.sid is not null;
  v_pieces := v_pieces || jsonb_build_object('stored_copy_pass_ms', round(extract(epoch from clock_timestamp() - t0) * 1000), 'stored_copies', (select count(*) from jsonb_object_keys(v_stored)));
  t0 := clock_timestamp();
  v_reoffer := array(select l.provider_id from (select distinct on (o.provider_id) o.provider_id, o.state, o.rule, o.checks from pipeline.provider_description_reads o
                        where o.state not in ('queued', 'reading') order by o.provider_id, o.created_at desc) l
                      where l.state = 'held' and coalesce(security.toolset_setting('pipeline', 'pdesc.identity_reeval_rules'), '[]'::jsonb) ? l.rule
                        and coalesce(l.checks->'identity'->>'reader_behavior_version', '') is distinct from coalesce(security.pdesc_reader_behaviour_v1(), ''));
  v_pieces := v_pieces || jsonb_build_object('identity_reoffer_ms', round(extract(epoch from clock_timestamp() - t0) * 1000), 'reoffered', coalesce(array_length(v_reoffer, 1), 0));
  t0 := clock_timestamp();
  select count(*) into v_n from pipeline.provider_description_reads x join pipeline.evidence_artifacts a on a.id=(v_stored->>x.provider_id::text)::uuid
    where x.state='queued' and not (x.provider_id = any(v_reoffer)) and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',x.provider_id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),v_model,coalesce(x.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true);
  v_pieces := v_pieces || jsonb_build_object('recovery_held_select_ms', round(extract(epoch from clock_timestamp() - t0) * 1000));

  -- 2 equal, and the pick timings
  foreach v_mach in array array[true, false] loop
    select coalesce(jsonb_object_agg(q.cid, q.n), '{}'::jsonb) into v_act from (select pz.country_id::text cid, count(*) n from pipeline.provider_description_reads o join catalogue.providers pz on pz.id=o.provider_id where v_mach and o.state in ('reading','proposed','admitted','held') and o.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id) q;
    foreach v_lim in array array[3, 10, 100, 1000] loop
      t0 := clock_timestamp();
      v_old := array(with act as materialized (select pz.country_id,count(*) n from pipeline.provider_description_reads o join catalogue.providers pz on pz.id=o.provider_id
                              where v_mach and o.state in ('reading','proposed','admitted','held') and o.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id)
        select r.id from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
                   and security.provider_description_scope_v1(r.provider_id)
                   and (r.provider_id = any(v_reoffer) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>r.provider_id::text)::uuid),v_model,coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))))
                   and exists(select 1 from catalogue.providers p where p.id=r.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
                   and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=r.provider_id)
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   and case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then true else (v_stored->>r.provider_id::text) is not null end
                 order by case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 limit v_lim);
      v_ms_old := round(extract(epoch from clock_timestamp() - t0) * 1000);
      t0 := clock_timestamp();
      v_new := array(with act as materialized (select pz.country_id,count(*) n from pipeline.provider_description_reads o join catalogue.providers pz on pz.id=o.provider_id
                              where v_mach and o.state in ('reading','proposed','admitted','held') and o.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id)
        select c.id from (
          select r.id, r.provider_id, r.prompt_version from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))))
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   and case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then true else (v_stored->>r.provider_id::text) is not null end
                 order by case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 offset 0) c
         where security.provider_description_scope_v1(c.provider_id)
           and (c.provider_id = any(v_reoffer) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',c.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>c.provider_id::text)::uuid),v_model,coalesce(c.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))
           and exists(select 1 from catalogue.providers p where p.id=c.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
           and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=c.provider_id)
         limit v_lim);
      v_ms_new := round(extract(epoch from clock_timestamp() - t0) * 1000);
      v_ko := array(select coalesce((v_act->>pz.country_id::text)::int, 0) || '/' || r.next_try_at::text || '/' || r.created_at::text from unnest(v_old) with ordinality u(id, ord) join pipeline.provider_description_reads r on r.id = u.id join catalogue.providers pz on pz.id = r.provider_id order by u.ord);
      v_kn := array(select coalesce((v_act->>pz.country_id::text)::int, 0) || '/' || r.next_try_at::text || '/' || r.created_at::text from unnest(v_new) with ordinality u(id, ord) join pipeline.provider_description_reads r on r.id = u.id join catalogue.providers pz on pz.id = r.provider_id order by u.ord);
      v_eq := v_eq || jsonb_build_object('machine', v_mach, 'limit', v_lim, 'old_n', coalesce(array_length(v_old,1),0), 'new_n', coalesce(array_length(v_new,1),0), 'same_order_keys', v_ko = v_kn,
                 'same_set', (select coalesce(array_agg(x order by x),'{}') from unnest(v_old) x) = (select coalesce(array_agg(x order by x),'{}') from unnest(v_new) x), 'old_ms', v_ms_old, 'new_ms', v_ms_new);
      if v_mach and v_lim = 10 then
        v_pieces := v_pieces || jsonb_build_object('old_pick_limit10_ms', v_ms_old, 'new_pick_limit10_ms', v_ms_new);
        -- the About-page candidates of the ten picked reads (the last part of the lease answer)
        t0 := clock_timestamp();
        select count(*) into v_n from unnest(v_new) u(id) join pipeline.provider_description_reads r on r.id = u.id,
          lateral (select coalesce(jsonb_agg(z.url order by (z.pg->>'main_host')::boolean desc, z.score desc, length(z.url)), '[]'::jsonb) c from (
                     select y.url, y.score, g.pg from (
                       select distinct e->>'url' url, coalesce((e->>'score')::numeric, 0) score
                         from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e
                        where cs.provider_id = r.provider_id and e->>'kind' = 'about_page' and e->>'url' ~* '^https?://'
                          and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)) y
                       cross join lateral (select security.provider_description_page_v1(r.provider_id, y.url) pg offset 0) g
                      where (g.pg->>'ok')::boolean) z) cc;
        v_pieces := v_pieces || jsonb_build_object('candidates_of_ten_ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
      end if;
    end loop;
  end loop;
  select count(*) into v_bad from jsonb_array_elements(v_eq) e where not ((e->>'same_order_keys')::boolean and (e->>'old_n') = (e->>'new_n') and ((e->>'limit')::int < 1000 or (e->>'same_set')::boolean));

  -- 3 plans: the stored-copy pass and the lazy pick, seven times on this connection, default plan cache first, then force_custom_plan
  foreach v_mode in array array['auto', 'force_custom_plan'] loop
    perform set_config('plan_cache_mode', v_mode, true);
    v_ms := '[]';
    for i in 1 .. 7 loop
      t0 := clock_timestamp();
      select coalesce(jsonb_object_agg(z.pid, to_jsonb(z.sid)), '{}'::jsonb) into v_stored from (
        select x.provider_id::text pid, security.provider_description_stored_v1(x.provider_id) sid
          from (select distinct o.provider_id from pipeline.provider_description_reads o where (o.state='queued' or (o.state='reading' and o.leased_until<now()))
                   and exists (select 1 from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id=s.id where s.provider_id=o.provider_id and lower(a.source_url) like any (v_ws))
                 offset 0) x) z where z.sid is not null;
      select count(*) into v_n from (select c.id from (
          select r.id, r.provider_id, r.prompt_version from pipeline.provider_description_reads r
           where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now())) and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
             and (select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
             and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
           order by r.next_try_at, r.created_at offset 0) c
         where security.provider_description_scope_v1(c.provider_id)
           and exists(select 1 from catalogue.providers p where p.id=c.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
         limit 10) k;
      v_ms := v_ms || to_jsonb(round(extract(epoch from clock_timestamp() - t0) * 1000));
    end loop;
    v_plans := v_plans || jsonb_build_object(v_mode, v_ms);
  end loop;

  raise exception 'PDESC LEASE TIMINGS {"due_reads":%, "mismatches":%, "pieces":%, "equal":%, "plans_ms_per_repeat":%}', v_due, v_bad, v_pieces::text, v_eq::text, v_plans::text;
end $x$;
