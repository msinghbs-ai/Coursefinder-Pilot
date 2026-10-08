-- CF-247 Standing Review Rule 4, low agreement (8 Oct 2026, Platform Admin, multiple choice): "Page wins, admit anyway" (no Layer 4
-- items), fields already admitting are never switched off ("No, flag only"), and "Yes, admit automatically daily".
-- Daily at 03:37 UTC every switched-on university adapter is qualified again (security.adapter_qualify_one_v1, read share 0.5,
-- agreement 0.9, read-only). A field read on at least half the pages that agrees with held values on under 90% and is not yet
-- admitted is admitted: added to admit_fields, or, for an adapter switched on but not admitting, admission switched on for the Rule 4
-- fields only (its other fields stay off). The adapter's stored pages are then applied, and the 10-minute adapter-overwrite job puts
-- the page readings in place of held values (values entered or locked by hand are never touched; per-course exclusions stay).
-- Never admitted by this rule: a Canadian fee (Decision 220, no Canadian fee without the course code) and any provider and field a
-- Platform Admin lists in pipeline.l4_rule4_holds. Each admission is logged in admin_control_events (actor empty: the rule) and each
-- run in pipeline.layer4_rule_runs.
create table if not exists pipeline.l4_rule4_holds (
  provider_id uuid not null, field text not null check (field in ('intakes', 'english', 'fee', 'delivery')), reason text not null,
  set_by uuid, set_at timestamptz not null default now(), primary key (provider_id, field));
alter table pipeline.l4_rule4_holds enable row level security;
revoke all on pipeline.l4_rule4_holds from public, anon, authenticated;

create or replace function security.l4_rule_low_agreement_v1()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare a record; q jsonb; v_add text[]; v_done jsonb := '[]'::jsonb; v_checked int := 0; v_country text;
begin
  for a in select u.provider_id, u.admit, u.admit_fields from pipeline.uni_adapters u where u.enabled order by u.provider_id loop
    v_checked := v_checked + 1;
    q := security.adapter_qualify_one_v1(a.provider_id, 0.5, 0.9);
    select k.iso_alpha2 into v_country from catalogue.providers p left join ref.countries k on k.id = p.country_id where p.id = a.provider_id;
    v_add := array(
      select x.k from jsonb_each(coalesce(q->'fields', '{}'::jsonb)) x(k, v)
       where x.k in ('intakes', 'english', 'fee', 'delivery')
         and (x.v->>'read_share')::numeric >= 0.5 and (x.v->>'agree_share')::numeric < 0.9
         and not (a.admit and x.k = any(coalesce(a.admit_fields, '{}')))
         and not (x.k = 'fee' and v_country = 'CA')
         and not exists (select 1 from pipeline.l4_rule4_holds h where h.provider_id = a.provider_id and h.field = x.k)
       order by x.k);
    if cardinality(v_add) > 0 then
      update pipeline.uni_adapters u
         set admit = true,
             admit_fields = array(select distinct f from unnest(case when a.admit then coalesce(a.admit_fields, '{}') else '{}'::text[] end || v_add) f order by f),
             admit_reason = 'Rule 4 (daily): low agreement, page wins - ' || array_to_string(v_add, ', ') || ' admitted', admit_changed_at = now()
       where u.provider_id = a.provider_id;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('toolsets', 'uni_adapter_admit', a.provider_id::text,
              jsonb_build_object('admit', true, 'fields', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = a.provider_id),
                                 'reason', 'Rule 4 (daily): low agreement, page wins', 'rule', 'rule_4', 'qualify', q->'fields'), null);
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_apply', 'provider_id', a.provider_id));
      v_done := v_done || jsonb_build_object('provider_id', a.provider_id, 'fields', to_jsonb(v_add));
    end if;
  end loop;
  insert into pipeline.layer4_rule_runs(rule, raised) values ('low_agreement', jsonb_build_object('adapters_checked', v_checked, 'admitted', v_done));
  return jsonb_build_object('adapters_checked', v_checked, 'admitted', jsonb_array_length(v_done));
end $f$;
revoke all on function security.l4_rule_low_agreement_v1() from public, anon, authenticated;

select cron.schedule('l4-rule-low-agreement', '37 3 * * *', 'select security.l4_rule_low_agreement_v1()');
