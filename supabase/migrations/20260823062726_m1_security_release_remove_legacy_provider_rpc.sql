-- CF-CHG-20260823-027 — M1 Security Release
-- Retire obsolete direct authenticated Provider paging compatibility RPCs.
-- Current browser code uses only public.admin_read(text,jsonb).

drop function if exists public.ui_providers_page(integer,integer,text);
drop function if exists public.ui_providers_page(integer,integer,text,text,text,text,text,text,text);
