# Agent working rules (Coursefinder-Pilot)

Every agent working in this repository follows `CLAUDE.md` in full (G1 to G4, the consumer API freeze, housekeeping, automatic merging and the rest). This file repeats the standing mandate below so that agents that read `AGENTS.md` first see it.

### Standing Mandate: Immediate Live Activation (No Unrequested Shadow or Future Deferrals)

Platform Admin, 21 Nov 2026 10:07 AEDT. Non-negotiable; it applies to every change in both repositories.

1. **Reported Bugs & Verified Fixes Ship Live Immediately:** Every reported bug fix, UI/filter fix, parser fix, or verified deterministic admission rule MUST take effect **immediately upon deploy** in the same PR.
2. **Zero Unrequested Shadow Soaks or Delayed Cutovers:** NEVER place a bug fix or verified admission rule into shadow-only mode, behind an off-by-default flag, or on a 24-hour / next-day cutover timer unless the user explicitly instructs a shadow period first.
3. **No Assumed Future Work:** NEVER defer a reported fix to "tomorrow", "a future lane", or "a follow-up PR" without explicit user confirmation. Either ship and activate the complete fix immediately in the current PR, or—if a hard guardrail conflict exists—ask the user for an immediate decision before writing deferred code.
