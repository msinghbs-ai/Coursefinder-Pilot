-- CF-186 runtime-history reconciliation marker.
-- Pilot replaced public.scholarship_international_detail_batch_service at this point
-- with the discovered-only, first-party, international and individual-Scholarship
-- semantic gate used during the live M2.4.5 hardening run.
-- The exact intermediate function body was applied directly to Pilot before repo
-- reconciliation. The authoritative current function body is captured by the later
-- current-state replay migration; this file preserves the deployed migration identity.

comment on function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean) is
'CF-186 history; current replay definition is authoritative. Automatic detail acquisition is first-party, international, individual-Scholarship only and never publishes.';
