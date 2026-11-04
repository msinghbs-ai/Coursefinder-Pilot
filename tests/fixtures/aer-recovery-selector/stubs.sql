-- CF-247 AER recovery selector fixtures: the live columns the lifecycle settings (20261104540000 §1) write, beyond ../aer-review-queue.
alter table pipeline.platform_toolset_settings add column if not exists updated_by uuid;
alter table pipeline.field_enrich_items add column if not exists cost_usd numeric;
