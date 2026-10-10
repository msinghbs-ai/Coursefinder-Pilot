-- CF-247 (Decision 227, 2 Oct 2026). A policy default is checked against the courses whose own pages already gave an
-- English score. Where at least 10 such courses can be compared and more of them differ from the default than agree
-- with it, the default is not the university's real standard (for example a nursing table read as the default), and
-- the proposal cannot be approved. Patch behind an md5 guard.

do $p$
declare s text; d text;
  o1 text := $o$declare x pipeline.provider_policy_proposals%rowtype; v jsonb := '{}'::jsonb;$o$;
  n1 text := $n$declare x pipeline.provider_policy_proposals%rowtype; v jsonb := '{}'::jsonb; v_ag int := 0; v_df int := 0;$n$;
  o2 text := $o$if x.status <> 'proposed' then raise exception 'already decided or not a proposal (%)', x.status; end if;$o$;
  n2 text := $n$if x.status <> 'proposed' then raise exception 'already decided or not a proposal (%)', x.status; end if;
  if p_action = 'approve' and x.kind = 'english_policy' then
    select count(*) filter (where r.outcome = 'agrees'), count(*) filter (where r.outcome = 'differs') into v_ag, v_df
      from security.provider_english_plan_v1(p_id) r;
    if v_ag + v_df >= 10 and v_df > v_ag then
      raise exception 'This default does not match most course pages (% agree, % differ), so it cannot be approved', v_ag, v_df;
    end if;
  end if;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_provider_policy_decide';
  if md5(s) is distinct from 'bff1631490ab3348960e8564b8909eba' then raise exception 'admin_provider_policy_decide changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece 1 not found once'; end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'piece 2 not found once'; end if;
  execute replace(replace(d, o1, n1), o2, n2);
end $p$;
