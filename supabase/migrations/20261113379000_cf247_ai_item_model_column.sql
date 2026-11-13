-- CF-247 AI spend control, columns step 3 of 3: pipeline.field_enrich_items.model. Nothing else.
-- Platform Admin 13 Nov 2026 19:14: "GPT 4.1 mini is too expensive it has exhausted the AI credit. use other cheaper model and define the usage per
--   field in ui under Model and Services ... then Service based Model with cascading, Then Recent usage".
-- Why three small files (20261113377000, 20261113378000, 20261113379000) before the two migrations that fill the columns (20261113380000 and
-- 20261113390000): adding a column takes ACCESS EXCLUSIVE on its table until the transaction ends. Inside the larger migration that lock was held
-- on pipeline.ai_spend_ledger through a backfill of about 80,000 rows and then taken on pipeline.platform_toolset_settings: it blocked every AI
-- cost record and every settings read (the consumer API included; PostgREST sessions wait 8 seconds) and it deadlocked against a concurrent
-- public.svc_scholarship_ai_record (independent QA, 13 Nov 2026). One table a file means one ACCESS EXCLUSIVE lock a transaction: there is no
-- second lock to wait for while holding the first, so no lock-order deadlock is possible, and each lock is held for an instant.
-- lock_timeout: a lock that cannot be had in 3 seconds fails this migration at once instead of queueing behind a long reader and blocking
-- everyone after it. Nothing is half done (one transaction); run it again.
-- Locks on existing tables, for this short transaction only:
--   pipeline.field_enrich_items         ACCESS EXCLUSIVE (one nullable column, no rewrite)
-- G3: no consumer API object is changed: new nullable columns beside, nothing renamed or retyped. No function, trigger, row or job is touched.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '3s';

alter table pipeline.field_enrich_items add column if not exists model text;
comment on column pipeline.field_enrich_items.model is 'The OpenRouter id of the model that answered this item (the worker reports it with the result; 13 Nov 2026). The spend ledger takes it from here.';
