# Spec decisions log

Append-only log of design decisions resolved during build, per the per-slice
refinement workstream in the build plan. Each entry: date, slice, decision,
why, and where it lives in code.

---

## 2026-04-26 · Pre-Slice-0 · Architecture & defaults

Locked in during the brainstorming/planning pass. See
`/Users/chintangandhi/.claude/plans/cheerful-jingling-parasol.md` for the
full plan.

| Decision | Value | Why |
|---|---|---|
| Build venue | Claude Code (this directory) | User chose to skip Lovable and have me implement directly. |
| Hosting | GitHub Pages, repo `monodeal` | Free, no platform account beyond GitHub. |
| Routing | HashRouter (`/#/admin`) | Avoids SPA-fallback gymnastics on GH Pages. |
| Backend | Supabase free tier, single project | Matches the spec; no dev/prod split. |
| Mobile | Responsive from Slice 3 | User requested phone + desktop in v1. |
| Reconnect window | Hold seats forever | Friend-game; host kicks if a seat needs freeing. |
| Late join / spectators | None; lobby locks at "Start Game" | Simpler model, matches private 2–5 player spec. |
| Sound | Silent v1, no audio assets | No assets exist; deferred indefinitely. |
| Concurrency retry | Auto-retry once on `stale_state`, then toast | Cap at 1 to avoid infinite UI loops. |
| `reparo_spell_destination` | `bank_as_points` | Spec default; user accepted. |
| Petrificus removal source | `["bank"]` only; no admin toggle in v1 | Spec default; toggle deferred. |
| `?dev=1` host impersonation | Enabled (full RPC impersonation by host_token) | Required by spec for solo testing. |
| Reaction modal copy | "Play Protego" / "Take the hit" | Two-button modal; revisit at Slice 7 if friend feedback differs. |
| Cedric draw split | Up to 1 from discard + rest from deck | When `cedric_discard_rule = "top_only"` and Cedric draws 2. |
| Confundo / Wingardium target consent | Instant once Protego window closes | No per-target confirm modal. |
| Obliviate steal | Random card (blind) from target's hand | "Take a complete item set from an opponent" interpreted as a complete-set steal; if hand-card variant is meant, revisit at Slice 5. |
| Force-end-turn discard | Host picks which cards | Host already has the controls; simplest model. |

---

## 2026-04-26 · Slice 0 · Wild card cash values are TABLE-authoritative

The spec prose at line 314 says "Wild cash = max(cash of both colors) per
card," but the table at lines 303-313 has `pink/yellow = cash 2` (max would
be 3). The seed migration uses **table values verbatim**.

**Why:** the table is more specific and matches physical card scans (per the
"CONFIRMED from physical cards" note). Prose appears to be an
oversimplification.

**Where:** `supabase/migrations/20260426000002_seed_cards.sql`, two-color
wild section.
