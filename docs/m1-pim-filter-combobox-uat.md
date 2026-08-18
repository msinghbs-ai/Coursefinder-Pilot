# M1-PIM Searchable Combobox Filter Contract

Date: 18 August 2026

Status: ACCEPTED UX DECISION / IMPLEMENTATION SUPPORT ADDED

Provider Admin reference filters must support both typed entry and dropdown selection.

Required pattern:
- searchable combobox, not text-only and not dropdown-only;
- Country options sourced from governed Provider/reference data;
- State / Province / Region options dependent on selected Country where authoritative values exist;
- keyboard and mouse selection;
- clearable selection;
- server-side filtering after selection;
- no fabricated subdivision values when authoritative mapping is absent.

Backend support added through authenticated RPC `public.ui_provider_filter_options(text)`.

UAT:
- available Provider countries returned: AU, CA, NZ;
- CA dependent subdivisions returned authoritative province/territory options including Alberta, British Columbia, Ontario, Quebec and others;
- AU returns no fabricated subdivision choices because accepted AU Provider/Campus subdivision mapping is currently absent.

Authoritative cross-chat design contract: `coursefinder-admin/docs/coursefinder-admin-pim-design-decisions-v1.1.md`.
