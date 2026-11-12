-- CF-247 AER: the course-read daily cap no longer stops the on-demand backlog run (Platform Admin 13 Nov 2026 09:30: "Do not impose daily toolset shares,
-- routine per-provider caps, scheduled batch sizes, refresh intervals or hourly execution delays on the authorised on-demand request"; "If an actual technical
-- bottleneck prevents higher throughput, fix the shared cause through the normal engineering release process").
-- Evidence (13 Nov 2026 10:50 AEDT): 11,594 eligible course reads remain across 991 providers; course reads now finish at about 1,200 an hour; the cap
--   aer.schedule_daily_max is at its range maximum (5,000) with 2,837 used in the last 24 hours, so the run would stop at about 12:30 with about 9,000 left.
--   Cost at the measured US$0.0055 a read: about US$64 for the whole backlog, against an OpenRouter balance of about US$98 (floor US$0.50).
-- Guards: G2 (the cap stays a setting; its range is widened and the value set with the Platform Admin's reason), G3 (no consumer API object), Decision 260.
-- What: aer.schedule_daily_max range 0..5,000 -> 0..20,000; value 5,000 -> 15,000. The credit floor, the Layer 4 back-pressure (aer.schedule_layer4_max),
--   per-run batch and every admission rule are unchanged.
-- Reversal without code: set the value back on Settings › Pipeline settings, with a reason.
-- Replaces: nothing. Retires: nothing.

update pipeline.platform_toolset_settings
   set max_value = 20000, value = to_jsonb(15000), updated_at = now(),
       reason = 'Platform Admin 13 Nov 2026 09:30: on-demand AER backlog is not held by the daily course-read cap (11,594 reads left at 10:50)'
 where toolset_key = 'pipeline' and key = 'aer.schedule_daily_max' and (value #>> '{}')::numeric = 5000;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting_change', 'pipeline.aer.schedule_daily_max',
        jsonb_build_object('from', 5000, 'to', 15000, 'max_value', 20000, 'reason', 'Platform Admin 13 Nov 2026 09:30: on-demand AER backlog'), null);
