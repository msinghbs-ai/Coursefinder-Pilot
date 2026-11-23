-- Read-back page carrier (read-only branch s2-build-am-reads, never merged): sets the page the probe returns; nothing is written.
-- Replaces: nothing.
-- Retires: nothing.
select set_config('cf.page', '47', true);
