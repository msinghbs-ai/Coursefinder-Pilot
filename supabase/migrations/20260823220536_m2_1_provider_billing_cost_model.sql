alter table pipeline.layer2_acquisition_providers add column if not exists billing_config jsonb not null default '{}'::jsonb;

create or replace function security.layer2_provider_effective_cost_usd(p_billing jsonb,p_units numeric default 1)
returns numeric language plpgsql immutable set search_path='pg_catalog','security' as $$
declare v_direct numeric;v_plan numeric;v_included numeric;v_per_request numeric;begin
 if p_billing is null or jsonb_typeof(p_billing)<>'object' then return null;end if;
 if coalesce(upper(p_billing->>'currency'),'USD')<>'USD' then return null;end if;
 v_direct:=nullif(p_billing->>'unit_cost_usd','')::numeric;
 if v_direct is not null then return round(v_direct*greatest(coalesce(p_units,1),0),8);end if;
 v_plan:=nullif(p_billing->>'plan_cost_usd','')::numeric;v_included:=nullif(p_billing->>'included_units','')::numeric;v_per_request:=coalesce(nullif(p_billing->>'units_per_request','')::numeric,1);
 if v_plan is null or v_included is null or v_included<=0 then return null;end if;
 return round((v_plan/v_included)*v_per_request*greatest(coalesce(p_units,1),0),8);
exception when invalid_text_representation then return null;end$$;

-- Browser projection exposes only sanitised non-secret billing metadata and an estimated request cost.
-- The live migration also updates security.admin_layer2_provider_read, public.layer2_provider_runtime_config
-- and public.layer2_provider_control so billing_config participates in governed read/update/runtime contracts.
-- Keep credential values exclusively in Vault; billing_config must never contain secret-like keys.
