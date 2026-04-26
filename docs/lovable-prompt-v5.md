# Build: Monopoly Deal HP (private multiplayer web app) — v5 SHIP-READY

Build a realtime browser card game for me and up to 4 friends, playable privately via a shared link.

**Access model:** one fixed URL (e.g. `yourapp.com/`). Anyone with the link can join. No auth — first-time visitors enter a name and get an auto-issued `player_token` stored in `localStorage` for refresh recovery within a session. No cross-session identity persistence; on Full Reset, tokens are invalidated.

**No in-app chat.** Friends coordinate via voice (Discord/WhatsApp).

**Priority ranking (when in conflict):**
1. Rules correctness
2. Information-state integrity (no hand leaks)
3. Interaction clarity (every player always knows what's being asked of them)
4. Concurrency safety
5. Visual polish

---

## Top-level design principles

1. **Server-authoritative.** All game logic lives in plpgsql RPCs. Client only triggers RPCs and renders state. No optimistic UI.
2. **Information-state is sacred.** Never broadcast a player's hand or the deck order to any channel outside that player.
3. **The host is the referee.** No automatic timers on player decisions. Instead, the host has **"Force Resolve" buttons** to unstick any waiting state (reactions, payments, turns) when a player is AFK.
4. **Every interactive moment is explicitly specified in the Interaction Flow Specification below.** Build flows exactly as written. Do not invent steps.
5. **Legal actions only.** If an action is illegal (complete-set item, Harry-protected color, empty discard for Reparo), dim it with an explanatory tooltip — never let the player click then fail silently.
6. **Cast Spell is binding.** The moment a player clicks "Cast Spell" on a card, the play is consumed. If they cancel mid-targeting, the spell goes to discard with no effect. This prevents weird rollback UI.
7. **Art is separate.** Ship with styled placeholders (color band + title + cash value + charge table). Admin page accepts art uploads later.

---

## Stack — fixed

- Vite + React + TypeScript + Tailwind + shadcn/ui
- Supabase (Postgres + Realtime + Storage). No Firebase.
- Zustand for client-side derived UI state only
- `@dnd-kit/core` for drag-and-drop (click-menu is primary; drag is a power-user shortcut)
- All game mutations go through Supabase plpgsql RPCs with `security definer`. RLS denies all writes from `anon`.

---

## Concurrency model — build FIRST before any gameplay

1. `game_state` has a `version int` column. Every RPC reads current version via `SELECT ... FOR UPDATE`, asserts caller's `expected_version` matches, mutates, bumps version, returns new state.
2. On mismatch, RPC raises `stale_state`. Client refetches from public view and retries (or surfaces an error toast).
3. Every RPC takes `actor_player_id` + `player_token`. Server validates token against `players.token`. Tokens never appear in the public view.
4. Turn RPCs assert `actor_player_id = game_state.turn_player_id`, except reaction RPCs (called by target) and payment RPCs (called by debtor).
5. Every RPC body runs in a transaction with `SELECT ... FOR UPDATE` on `game_state`.

**Smoke test before cards exist:** two browsers fire 100 concurrent `increment_counter` RPCs against a dummy row. Final value must equal exactly 200. Do not proceed past Slice 0 until this passes.

---

## Information-state model — build before any cards

### Zone visibility

| Zone | Face | Who sees full card | Who sees count only |
|---|---|---|---|
| Draw pile | down | nobody | everyone |
| Discard pile | up | everyone | — |
| Pending stack | up | everyone | — |
| Player hand | up to owner | owner | everyone else |
| Player bank | up | everyone | — |
| Player item area | up | everyone | — |
| Character card | up | everyone | — |

### Realtime channels — strict separation

Do NOT subscribe to `players` or `game_state` tables directly from clients — that would broadcast hands.

- `game:public` broadcasts the **public view** after every RPC: game_state minus `deck_order` (replaced by `deck_count`); all players with `hand` replaced by `hand_count`; full discard; pending_stack; payment_queue; last 50 log entries.
- `game:private:{player_id}` broadcasts **only that player's hand**. Server authenticates subscription via `player_token`.

Every RPC publishes to `game:public` and to each affected player's private channel.

### What opponents CANNOT see

- Your hand contents (count only)
- The draw pile order

Everything else is public.

---

## Build order — vertical slices, never skip

Each slice must be fully working before moving on. See `test-plan.md` for per-slice acceptance tests.

0. **Infra.** Supabase project, schema, `reset_game` RPC, `increment_counter` smoke test, public+private channels wired, React shell, name-entry screen.
1. **Lobby + reconnect.** Join by name, auto-suffix duplicates, host = first joiner, reconnect by token, host kick + full reset.
2. **Character select.** 5 character cards, no duplicates, Harry picks protected color, Start Game at 2+ locked.
3. **Minimum playable game — points + items only, no spells.** Draw 2, play up to 3 (play-to-bank, play-item, end-turn, force-discard-to-7), win detection live, bot-fill dev toggle. **Playtest at end of this slice.**
4. **Wild items + recolor.** Two-color and every-color wilds. All-every-color-set illegality enforced. Free recolor during own turn.
5. **Non-reactive spells.** Geminio, Reparo, Obliviate (cast without Protego for now), Levicorpus, Confundo, Wingardium Leviosa.
6. **Debt payments.** Stupefy, Alohomora, Accio — still without Protego. Payment modal, sequential debtor queue leftward.
7. **Protego reaction stack.** Full state machine including chains.
8. **Petrificus Totalus + character powers.** Draco override, Harry protection, Luna draw-3, Hermione plays-4, Cedric discard-draw.
9. **Polish.** Animations, log formatting, asset upload admin page, house-rule settings UI, host "Force Resolve" controls.

Better to ship end-of-Slice-6 cleanly than Slice 9 broken.

---

## Dev toggle: bot fill

Host-only button in lobby, visible only with `?dev=1`: "Fill with dummy players." Creates N dummies with random names. On character select, dummies auto-pick unused characters. On a dummy's turn, they do nothing by default; host clicks a dummy seat to impersonate it (server checks host token). This is the ONLY way to solo-test.

---

## Schema

```sql
create table game_state (
  id int primary key default 1,
  version int not null default 0,
  phase text not null default 'lobby',
    -- 'lobby' | 'character_select' | 'in_game' | 'paused' | 'finished'
  host_player_id uuid,
  previous_phase text,              -- restored when unpausing
  turn_player_id uuid,
  turn_number int not null default 0,
  plays_allowed_this_turn int not null default 3,
  plays_this_turn int not null default 0,
  has_drawn_this_turn bool not null default false,
  winner_player_id uuid,
  deck_order uuid[] not null default '{}',
  discard_pile uuid[] not null default '{}',
  pending_stack jsonb not null default '[]'::jsonb,
  payment_queue jsonb not null default '[]'::jsonb,
  log jsonb not null default '[]'::jsonb,
  settings jsonb not null default '{
    "max_players": 5,
    "protego_chain_rule": "one_cancels_one",
    "cedric_discard_rule": "top_only",
    "harry_color_timing": "choose_once_at_character_select",
    "reparo_spell_destination": "bank_as_points",
    "petrificus_removal_sources": ["bank"],
    "host_absent_transfer_seconds": 30
  }'::jsonb,
  started_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint singleton check (id = 1)
);

create table players (
  id uuid primary key default gen_random_uuid(),
  token uuid not null default gen_random_uuid(),
  name text not null,
  seat_index int not null,
  joined_at timestamptz not null default now(),
  is_connected bool not null default true,
  last_seen_at timestamptz not null default now(),
  chosen_character text,
  protected_color text,
  petrified bool not null default false,
  hand uuid[] not null default '{}',
  bank uuid[] not null default '{}',
  item_area jsonb not null default '[]'::jsonb
);

-- item_area = [{ column_id, color, cards: [{ card_id, assigned_color }] }]
-- A player may have multiple columns of the same color (Obliviate defense).

create table item_sets (
  color text primary key,
  set_size int not null,
  cash_value int not null,
  charge_table jsonb not null
);

create table cards (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  category text not null,
    -- 'point' | 'item' | 'wild_item_two_color' | 'wild_item_any_color' | 'spell' | 'character'
  title text not null,
  cash_value int,
  colors text[] default '{}',
  wild_charge_tables jsonb,
  spell_effect text,
  spell_allowed_colors text[],
  rules_text text,
  flavor_text text,
  art_asset_url text
);

create view game_state_public as
  select id, version, phase, host_player_id, turn_player_id, turn_number,
         plays_allowed_this_turn, plays_this_turn, has_drawn_this_turn,
         winner_player_id,
         coalesce(array_length(deck_order, 1), 0) as deck_count,
         discard_pile, pending_stack, payment_queue, log, settings,
         started_at, updated_at
  from game_state;

create view players_public as
  select id, name, seat_index, is_connected, last_seen_at,
         chosen_character, protected_color, petrified,
         coalesce(array_length(hand, 1), 0) as hand_count,
         bank, item_area
  from players;
```

RLS: enable on all tables. Grant SELECT on the two views + `cards` + `item_sets` to `anon`. Deny all writes from `anon`. Only `security definer` RPCs mutate.

---

## Deck composition — CONFIRMED (111 cards total)

Seed migration must assert `count(*) = 111` and raise if not.

| Category | Count |
|---|---|
| Character cards | 5 |
| Magical Item cards | 28 |
| Two-Color Wild items | 9 |
| Every-Color Wild items | 2 |
| Point cards | 20 |
| Accio (2-color) | 10 |
| Accio (any color) | 3 |
| Geminio | 10 |
| Reparo | 2 |
| Alohomora | 3 |
| Confundo | 3 |
| Stupefy | 3 |
| Levicorpus | 3 |
| Protego | 3 |
| Wingardium Leviosa | 3 |
| Petrificus Totalus | 2 |
| Obliviate | 2 |
| **TOTAL** | **111** |

Per-category assertion block in seed migration:

```sql
do $$ begin
  assert (select count(*) from cards) = 111, 'deck total must be 111';
  assert (select count(*) from cards where category != 'character') = 106;
  assert (select count(*) from cards where category = 'character') = 5;
  assert (select count(*) from cards where category = 'item') = 28;
  assert (select count(*) from cards where category = 'wild_item_two_color') = 9;
  assert (select count(*) from cards where category = 'wild_item_any_color') = 2;
  assert (select count(*) from cards where category = 'point') = 20;
  assert (select count(*) from cards where spell_effect like 'accio_%' and spell_effect != 'accio_any') = 10;
  assert (select count(*) from cards where spell_effect = 'accio_any') = 3;
  assert (select count(*) from cards where spell_effect = 'geminio') = 10;
  assert (select count(*) from cards where spell_effect = 'reparo') = 2;
  assert (select count(*) from cards where spell_effect = 'alohomora') = 3;
  assert (select count(*) from cards where spell_effect = 'confundo') = 3;
  assert (select count(*) from cards where spell_effect = 'stupefy') = 3;
  assert (select count(*) from cards where spell_effect = 'levicorpus') = 3;
  assert (select count(*) from cards where spell_effect = 'protego') = 3;
  assert (select count(*) from cards where spell_effect = 'wingardium_leviosa') = 3;
  assert (select count(*) from cards where spell_effect = 'petrificus_totalus') = 2;
  assert (select count(*) from cards where spell_effect = 'obliviate') = 2;
end $$;
```

---

## Item sets — CONFIRMED from physical cards

```sql
insert into item_sets (color, set_size, cash_value, charge_table) values
  ('brown',       2, 1, '{"1": 1, "complete": 2}'::jsonb),
  ('light-blue',  3, 1, '{"1": 1, "2": 2, "complete": 3}'::jsonb),
  ('pink',        3, 2, '{"1": 1, "2": 2, "complete": 4}'::jsonb),
  ('orange',      3, 2, '{"1": 1, "2": 3, "complete": 5}'::jsonb),
  ('light-green', 2, 2, '{"1": 1, "complete": 2}'::jsonb),
  ('black',       4, 2, '{"1": 1, "2": 2, "3": 3, "complete": 4}'::jsonb),
  ('red',         3, 3, '{"1": 2, "2": 3, "complete": 6}'::jsonb),
  ('yellow',      3, 3, '{"1": 2, "2": 4, "complete": 6}'::jsonb),
  ('dark-blue',   2, 4, '{"1": 3, "complete": 8}'::jsonb),
  ('dark-green',  3, 4, '{"1": 2, "2": 4, "complete": 7}'::jsonb);
```

Items (28 rows):

```
brown:       butterbeer, pumpkin_juice
light-blue:  berties_beans, chocolate_frog, cauldron_cake
pink:        brass_scales, dragon_hide_gloves, cauldron
orange:      hogwarts_a_history, beginners_guide_to_transfiguration, monster_book_of_monsters
light-green: portkey, floo_powder
black:       toad, rat, owl, cat
red:         quaffle, bludger, snitch
yellow:      omnioculars, remembrall, sneakoscope
dark-blue:   felix_felicis, veritaserum
dark-green:  amortentia, aging_potion, polyjuice_potion
```

Count: 2+3+3+3+2+4+3+3+2+3 = 28 ✓

### Accio pairings (10 cards = 2 per pairing)

1. Brown / Light Blue
2. Pink / Orange
3. Light Green / Black
4. Red / Yellow
5. Dark Blue / Dark Green

### Two-color wilds (9 total; provisional seed, verify via admin)

| Pairing | Cash | Count |
|---|---|---|
| brown / light-blue | 1 | 1 |
| pink / orange | 2 | 1 |
| pink / yellow | 2 | 1 |
| red / yellow | 3 | 2 |
| light-blue / black | 2 | 1 |
| light-blue / brown | 1 | 1 |
| dark-green / black | 4 | 1 |
| dark-green / dark-blue | 4 | 1 |

Sum: 9. Wild cash = max(cash of both colors) per card. Wilds carry both colors' `charge_table` in `wild_charge_tables` jsonb keyed by color slug.

### Every-color wild (2 copies)

- **Cash value 0** (confirmed). Cannot be used as payment.
- Cannot be banked.
- Cannot form a set made entirely of every-color wilds.

### Point cards (20) — CONFIRMED distribution

| Value | Count |
|---|---|
| 1 | 6 |
| 2 | 5 |
| 3 | 3 |
| 4 | 3 |
| 5 | 2 |
| 10 | 1 |

---

## Character cards (5)

| Slug | Banner | Flavor (italic) | Mechanical effect |
|---|---|---|---|
| harry | crimson | When hiding under his invisibility cloak, no one will see what you're carrying! | At character select, pick one color. While not petrified, your items of that color cannot be taken or discarded by opponents' spells. |
| draco | dark green | Mention his father's name and you can get away with anything. | While not petrified, you may take items that are part of a complete set via Confundo, Levicorpus, Wingardium Leviosa. (Obliviate is unaffected — it already targets complete sets.) |
| hermione | deep red | You never know what useful spell she might discover in the library. | While not petrified, `plays_allowed_this_turn = 4` instead of 3. |
| luna | blue | When you open your mind to the unexpected, extraordinary opportunities may present themselves! | While not petrified, at start of turn draw 3 cards instead of 2 (unless hand is empty; then still 5). |
| cedric | yellow | With the dedication and resourcefulness of a true Hufflepuff, he finds value where others don't. | While not petrified, at start of turn may draw from discard instead of deck. |

---

## Spell registry (authoritative)

Each spell can be played two ways:
- **Bank it** — place face-up in Bank at cash value. Counts as 1 play. Permanently locked as cash; can never be cast later. Banked spells can be used as payment at their cash value.
- **Cast it** — trigger effect, then discard (unless attached, e.g. Petrificus).

| Slug | Count | Cash | Effect | Target | Protego? |
|---|---|---|---|---|---|
| accio_brown_light_blue | 2 | 1 | Pick brown or light-blue; each opponent pays per caster's item-count in that color. | all opponents independently | yes per-target |
| accio_pink_orange | 2 | 1 | Pick pink or orange. | all opponents | yes per-target |
| accio_light_green_black | 2 | 1 | Pick light-green or black. | all opponents | yes per-target |
| accio_red_yellow | 2 | 1 | Pick red or yellow. | all opponents | yes per-target |
| accio_dark_blue_dark_green | 2 | 1 | Pick dark-blue or dark-green. | all opponents | yes per-target |
| accio_any | 3 | 3 | Pick any color. | all opponents | yes per-target |
| alohomora | 3 | 2 | Each opponent pays 2 points. | all opponents | yes per-target |
| confundo | 3 | 3 | Swap one of your items with one opponent's item. Neither may be from a complete set (Draco ignores). | 1 opponent, 1 item each | yes |
| geminio | 10 | 1 | Draw 2 cards. | self | no |
| levicorpus | 3 | 3 | Take one item from an opponent. Not from complete set (Draco ignores). | 1 opponent, 1 item | yes |
| obliviate | 2 | 5 | Take a complete item set from an opponent. | 1 opponent, 1 complete set | yes |
| petrificus_totalus | 2 | 5 | Attach to opponent's character card; disables ability until they discard 10 points. | 1 opponent | yes |
| protego | 3 | 4 | Reaction — blocks a spell cast against you. Can be chained. | reaction only | — |
| reparo | 2 | 2 | Take any one card from discard pile and place in front of you. | self | no |
| stupefy | 3 | 3 | One opponent pays 5 points. | 1 opponent | yes |
| wingardium_leviosa | 3 | 4 | Discard one item from an opponent. Not from complete set (Draco ignores). | 1 opponent, 1 item | yes |

### Accio resolution

1. Caster picks color from card's allowed options.
2. Engine counts caster's items in that color (including wilds currently assigned to that color).
3. Look up `item_sets.charge_table[count]`, using key `"complete"` when count equals `set_size`.
4. If count is 0, payout is 0 — cast still proceeds, warn in UI.
5. Each opponent independently may play Protego.
6. Surviving debts enqueue in `payment_queue` leftward from caster.

### Reparo — house-rule-governed destinations

Rulebook says "place in front of you," which is ambiguous for non-item cards.

- **Item / wild item:** goes to item area. For items, into a new column of its color or append to existing non-complete column of same color (engine picks; default append). For wilds, caster picks color.
- **Point card:** goes to Bank.
- **Spell card:** follows `settings.reparo_spell_destination`. Default `bank_as_points`. Alternate `cast_for_effect` (costs an additional play; legal only if plays remain).
- **Petrificus Totalus from discard:** always goes to Bank as 5 cash (it has no valid "in front" destination).

### Petrificus Totalus

- Attaches to target's character card; sets `players.petrified = true`. Card stays visually on character; does NOT go to discard on attach.
- While petrified: character ability disabled. Engine recomputes `plays_allowed_this_turn` and Luna's draw count at each affected point.
- Removal: during petrified player's own ACTION phase, they discard cards totaling ≥ 10 pts. Does NOT count as a play.
- **Source of removal discard:** default `["bank"]` only. On removal, Petrificus moves to discard; `petrified = false`.

### Protego state machine

`pending_stack` structure:

```jsonc
[
  {
    "id": "uuid",
    "kind": "spell",
    "spell_slug": "stupefy",
    "caster_id": "uuid",
    "params": {},
    "targets": [
      { "player_id": "uuid", "status": "awaiting", "result_debt": 5 }
    ],
    "awaiting_response_from": "uuid",
    "started_at": "iso-timestamp"
  }
  // Protego frames push on top
]
```

Resolution:

1. `cast_spell` RPC validates caller, consumes the play, constructs the frame, pushes to pending_stack. For multi-target spells, sets `awaiting_response_from` to the leftmost target from caster.
2. Awaiter client sees the reaction panel. If awaiter has no Protego in hand → auto-resolve after 2s notification (see Flow 7 in Interaction Spec).
3. `play_protego` RPC pushes a new Protego frame. `awaiting_response_from` becomes the player below on the stack (next to decide whether to counter).
4. `pass_reaction` RPC marks current awaiter's target as `awaiting_hit` (took it) and advances `awaiting_response_from` leftward to next `awaiting` target. If no awaiters remain, resolve top frame.
5. When top frame has no awaiters:
   - **Protego frame:** cancels frame below for that target only. Both move to discard. If spell has other unresolved targets, continue with next.
   - **Spell frame:** apply to `awaiting_hit` targets. Spell to discard. Debts enqueue leftward from caster.

House rule `latest_protego_wins_all_for_that_target`: once any Protego fires for a target, target is immediately protected and no further reactions asked for them.

---

## Rules engine — authoritative

### Turn phases

```
DRAW → ACTION → CLEANUP → (next connected player, to the LEFT) DRAW
```

**Turn order is LEFT**, per rulebook. Derive next seat from sorted list of currently-connected `seat_index`, skipping disconnects.

- **DRAW (`start_turn` RPC):**
  - If hand is empty → draw 5.
  - Else Luna (not petrified) draws 3; everyone else draws 2.
  - Cedric (not petrified) may draw from discard instead: if discard non-empty, show a modal "Draw from Deck / Top of Discard"; if empty, auto-draw from deck with a toast.
  - If deck empty during a draw, reshuffle discard (minus cards currently in `pending_stack` or `payment_queue`) into deck; continue.
  - If both empty, draw what's available. `has_drawn_this_turn = true` regardless of source.
  - Set `plays_allowed_this_turn` based on Hermione + petrified status.
- **ACTION:** player calls `play_to_bank` | `play_item` | `recolor_wild` (free) | `cast_spell` | `remove_petrificus` (free, petrified players only) | `end_turn`. `plays_this_turn` increments only for plays (not recolors, not Petrificus removal, not end_turn).
- **CLEANUP (triggered by `end_turn`):**
  - If hand.length > 7, RPC returns `{status: "must_discard", excess: N}`. Client shows **Discard Picker modal** (see Flow 11 in Interaction Spec). Client resubmits `end_turn` with discard card ids. Server validates count == excess, moves cards to discard, proceeds.
  - Advance `turn_player_id` leftward to next connected seat. Reset `plays_this_turn = 0`, `has_drawn_this_turn = false`. Publish.

### Core rules

- **Items are locked in their column once played.** Only wilds can recolor freely during own turn.
- **Multiple columns of same color:** legal, intentional Obliviate defense. When playing a new item of color X and a non-complete X column exists, prompt: "Add to existing column (n/m)? OR Start a new column?"
- **Column count never exceeds set_size.** If playing would exceed, server rejects with clear error.
- **Set complete:** `count >= set_size AND exists(card in column where card.category != 'wild_item_any_color')`. Every-color wilds alone don't count.
- **Win detection:** after every RPC that mutates an `item_area`, recount complete distinct-color columns. If ≥ 3 AND `pending_stack` empty AND `payment_queue` empty → set `winner_player_id`, `phase = 'finished'`. Win check is deferred during chain resolution to prevent premature wins that Protego might reverse.
- **Hand is sanctuary.** Never touchable for payment, spells, or steals. Exception: `remove_petrificus` from Bank by default.
- **End-turn with 0 plays is legal.** Explicit button always visible on active player's UI.

### Payment rules

- **No change.** Overpayment is lost. UI surfaces this.
- **If total available (Bank + items, EXCLUDING every-color wilds with cash 0) < debt:** debtor must pay everything. Log "paid X of Y; Z forgiven."
- **If total available = 0:** debt forgiven silently. Log "nothing to pay; debt forgiven." Payment modal doesn't appear.
- **Destination:**
  - Bank cards → recipient's Bank. Banked spells stay banked (cash on recipient's side too).
  - Item cards → recipient's item area. Default: append to existing non-complete column of same color if one exists, else new column. Wilds preserve current color assignment.
- **Payment queue:** debts resolve leftward from caster. Only active debtor sees payment modal; others see waiting indicator.

### Disconnect handling

- On realtime drop: `is_connected = false`, `last_seen_at = now()`.
- **No automatic timeouts on player decisions.** Game waits indefinitely. Host uses Force Resolve buttons.
- **Host disconnect:** if host's `is_connected = false` for > `host_absent_transfer_seconds` (default 30s), auto-transfer host role to the connected player with earliest `joined_at`. Log entry: "Host transferred from X to Y (X offline)." If old host reconnects, they join as regular player — no reclaim.

---

## Host controls — the "referee" model

Host sees a sidebar with these buttons. All gated by `host_token`.

- **Pause / Resume:** sets `phase = 'paused'`, stores previous phase. Everyone sees "PAUSED" overlay. No actions possible. Resume restores `phase = previous_phase`.
- **Force Resolve (current state):** contextual button that appears when there's a stuck decision.
  - If `pending_stack` top frame is awaiting a disconnected / AFK player → button text "Force Pass (Chintan)" — treats their decision as "pass / take the hit."
  - If `payment_queue` has an active debtor who is AFK → button text "Force Auto-Pay (Chintan)" — server auto-pays with minimum overpayment algorithm.
  - If active turn player is AFK with no pending payment/reaction → button text "Force End Turn (Chintan)" — discards hand conservatively to 7, advances turn.
- **Kick Player (pre-game):** removes player from lobby.
- **Kick Player (mid-game):** confirmation-gated. Moves kicked player's hand + bank + items to discard. Remove seat. If < 2 players remain, auto-trigger Full Reset.
- **Reset Lobby:** keeps player names + seats; clears chosen_character, protected_color, petrified, hand, bank, item_area, deck_order, discard_pile, pending_stack, payment_queue, log, winner_player_id, turn state. Phase → `character_select`.
- **Full Reset:** wipes players AND game_state to defaults. Phase → `lobby`. Confirmation-gated if a game is in progress.
- **Settings:** live toggles for all house rule settings in `game_state.settings`.

Host controls visible to host only. Every host action emits a log entry.

---

## Admin asset page

Separate route: `/admin?host_token=...`.

- Lists every card row from `cards` table with current `art_asset_url` preview.
- Per-card: upload image to Supabase Storage `card_art/` bucket, save URL to `cards.art_asset_url`. Live, no redeploy.
- Editable fields: `title`, `rules_text`, `flavor_text`, `cash_value`, `colors`, `spell_allowed_colors`, `wild_charge_tables`.
- Full CRUD on `item_sets` rows.
- "Deck verification" panel showing all count-assertions live; green checkmarks for matches, red for mismatches.

---

## UI layout — CRITICAL

This section is authoritative. Render the table exactly as specified. The layout must handle 2-5 players without breaking.

### Core principle: two-tier information density

Every piece of public information is visible at **two fidelities**:

1. **Table-glance fidelity (default)** — compressed opponent views that fit on screen. Players see enough to make strategic decisions at a glance (which sets are near-complete, how much cash each player has, which hand sizes are dangerous).
2. **Full fidelity (on demand)** — click any zone to open a modal with full card-by-card detail.

**Rule:** any public card must be fully inspectable in ≤ 2 clicks. Players must never have to squint.

---

### Table layout (desktop-first)

Arrangement is a hexagonal ring around a central play zone. Viewer ("me") is always at the bottom. Opponents fill remaining positions based on seat order going leftward from me.

**2-player layout:**
```
                  ┌──────────────┐
                  │  Opponent 1  │
                  └──────────────┘
                  ┌──────────────┐
                  │    CENTER    │
                  └──────────────┘
                  ┌──────────────┐
                  │      ME      │
                  └──────────────┘
```

**3-player layout:**
```
                  ┌──────────────┐
                  │  Opponent 2  │
                  └──────────────┘
       ┌────────┐ ┌────────────┐
       │ Opp 1  │ │   CENTER   │
       └────────┘ └────────────┘
                  ┌──────────────┐
                  │      ME      │
                  └──────────────┘
```

**4-player layout:**
```
                  ┌──────────────┐
                  │  Opponent 2  │
                  └──────────────┘
       ┌────────┐ ┌────────────┐ ┌────────┐
       │ Opp 1  │ │   CENTER   │ │ Opp 3  │
       └────────┘ └────────────┘ └────────┘
                  ┌──────────────┐
                  │      ME      │
                  └──────────────┘
```

**5-player layout:**
```
         ┌──────────────┐   ┌──────────────┐
         │  Opponent 2  │   │  Opponent 3  │
         └──────────────┘   └──────────────┘
       ┌────────┐   ┌────────────┐   ┌────────┐
       │ Opp 1  │   │   CENTER   │   │ Opp 4  │
       └────────┘   └────────────┘   └────────┘
                  ┌──────────────┐
                  │      ME      │
                  └──────────────┘
```

Opponents are arranged so **Opp 1 is the next player leftward** (acts after me), and subsequent opponents continue in turn order. This makes the play order visually trace around the ring counter-clockwise-ish, matching the rulebook's "play proceeds left."

### My zone (bottom, full-fidelity)

Fixed minimum height ~35% of viewport. Horizontal layout from left to right:

```
┌───────────────────────────────────────────────────────────────────┐
│ [Character]  [Item columns: brown | l-blue | red | ...]  [Bank]   │
│ [───── My hand (face-up fan) ─────]                               │
└───────────────────────────────────────────────────────────────────┘
```

**Character card** (far left): full size. Shows name, portrait, banner color. Harry shows protected-color badge. Petrified players show attached Petrificus Totalus overlay.

**Item area** (center-left): each color column rendered at FULL scale. Columns flex horizontally. Each column:
- Header strip: `{color name} {n/set_size}` with color swatch
- Cards offset-stacked downward by 30% card height so every card's top band (name + cash value) stays visible
- When complete: gold border + "COMPLETE" badge + subtle pulse animation
- Harry-protected color: cloak SVG overlay on column header
- Column click: opens "My [color] column" modal with full face detail (redundant since already full-fidelity, but maintained for consistency)

**Bank** (right side): flex-wrap grid, 5 cards per row, full-size cards. Running total badge top-right: "Bank: 12 pts". Banked spells show a "LOCKED" watermark diagonally across them — critical so no one mistakes a banked Protego for a castable one.

**Hand** (bottom strip, below all of the above): horizontal face-up fan. Cards overlap ~40% horizontally so every card's title + cash value is visible. Hover lifts the hovered card ~30px to make it fully readable. Click opens action menu. Drag initiates drag-and-drop. On my turn in ACTION phase, all legally playable cards get a gold glow. During reactions, only Protego glows. During payments, only cash-usable cards glow.

### Opponent zone (top/sides, compressed)

Each opponent zone is ~55% of my zone's size. Contents:

```
┌─────────────────────────────────────────────┐
│ [Char] [Hand: 🂠×6]  [Bank strip ≤6 cards]   │
│ [Item column thumbnails: 🟤¼  🟦⅓  🔴⅔ ...]  │
└─────────────────────────────────────────────┘
```

**Character card** (top-left of their zone): ~60% scale. Name + character ability icon. Petrified overlay if applicable. Harry shows protected-color badge. Active-turn indicator: glowing ring around the whole zone when it's their turn.

**Hand**: never shown face-up. Render a single card-back icon with a count badge: "Hand: 6". If hand count = 0, render empty slot with "Empty". **Never shows individual cards.**

**Bank strip**: horizontal row of up to 6 compressed card thumbnails (title-only, ~40% scale). If bank has >6 cards, show first 5 + "+N more" thumbnail. Running total visible: "Bank: 8 pts". **Click the strip** → opens **"Bob's Bank" modal** (see below).

**Item area**: compressed horizontal row of **column thumbnails**, one per column. Each thumbnail shows:
- Color swatch (background)
- `n/set_size` counter ("2/3")
- Top card name only (if single non-wild) or "[Wild + Snitch]" compressed title
- Complete columns: gold border + ✓
- Harry-protected columns: small cloak icon overlay

**Click any column thumbnail** → opens **"Bob's [color] column" modal** showing full-face cards stacked in the column.

### Center zone

Central rectangle. Contents flex vertically:

```
┌────────────────────────────────────────────┐
│ [Draw 🂠×52]              [Discard 🃏×14]    │
│                                            │
│ [Pending Stack: Accio → Protego]           │
│ [Payment Queue: Bob (3) → Alice (3)]       │
│                                            │
│ ─────────────── LOG ───────────────        │
│ T3: Luna cast Accio...                     │
│ T3:   Bob played Protego                   │
└────────────────────────────────────────────┘
```

**Draw pile**: face-down card-back + count badge ("Deck: 52"). Not clickable (no peeking).

**Discard pile**: top card face-up + count badge ("Discard: 14"). Click opens **Discard Browser modal** (scrollable grid of every card in discard, newest first, full-face).

**Pending stack panel**: only visible when pending_stack is non-empty. Renders as a vertical stack of frame cards showing spell name + caster name. Topmost frame is highlighted. Example during Protego chain:
```
┌───────────────────┐
│ Protego (Alice)   │ ← topmost, awaiting response from Bob
├───────────────────┤
│ Protego (Bob)     │
├───────────────────┤
│ Stupefy (Alice)   │ ← base frame
└───────────────────┘
Awaiting: Bob
```

**Payment queue panel**: only visible during multi-payment resolution. Horizontal strip:
```
Pay queue: [Bob: 3 pts ← active] → [Chintan: 3 pts] → [Dave: 3 pts]
```

**Log** (bottom portion of center, or collapsible drawer): last 10 entries visible inline. Click to expand full log. Entries are color-coded by turn.

### Modals — full-fidelity inspection

Every click-to-inspect opens a centered modal with:
- Header: "Bob's Bank" / "Bob's brown column (2/2)" / "Discard Pile" / etc.
- Body: full-size cards, fully readable, scrollable if overflow.
- Close: X button, ESC key, or click outside modal.
- **Modals are purely informational** — no actions can be taken from them (except Discard Browser during Reparo casting, which makes cards clickable).

### Card component

`<Card cardId face="up"|"down" size="full"|"compressed"|"thumbnail" interactive? onClick?>`

- **Full** (~200×280px): my hand, my bank, my items, modal views, reaction modal, payment modal.
- **Compressed** (~120×170px): opponent bank strip cards.
- **Thumbnail** (~80×110px): opponent column representations.
- **Face down**: always renders card-back pattern regardless of size.

Face-up with `art_asset_url` → render image with title band + cash-value circle overlaid. Without art → styled placeholder: color band at top (or rainbow gradient for every-color wild), large title, cash-value circle top-left, rules text / charge table in body.

Aspect always 2.5:3.5.

### Visual state indicators

- **Active turn:** glowing gold ring around the active player's zone
- **Disconnected:** zone dims to 60% opacity, "Reconnecting..." badge over character card
- **Petrified:** Petrificus Totalus card rendered attached to character card, slight purple tint on the zone
- **Harry-protected column:** cloak SVG overlay on column header, shield icon, dimmed when hovered by opposing spell targeting
- **Complete column:** gold border + "COMPLETE" badge + subtle pulse
- **Host:** small crown icon next to their name
- **Winner (end game):** full-screen banner with character portrait, banner color, confetti

### Color-blind safety

Set-complete state MUST be indicated by text badge ("COMPLETE") in addition to gold border — never rely on color alone. Column counts ("2/3") are also primary indicators. Harry's protection is indicated by a cloak icon (shape, not color).

### Responsiveness

- Desktop (≥1024px): full layout as described.
- Tablet (768-1023px): opponent zones compress further. Character portraits become icon-only. Column thumbnails remain clickable.
- Mobile (<768px): single-column stack — my zone at bottom of scroll, opponents above in vertical stack, center zone becomes a floating panel. Modals fill screen. Primary use case is still desktop; mobile is "don't break."

---

## Interaction Flow Specification

This section is the contract for Lovable. Build every flow exactly as specified. When a flow is triggered, the listed perspective's UI state must match exactly.

Each flow is labeled F1, F2, ... for easy reference from tests.

---

### F1: Joining the game

**Trigger:** user opens the URL.

**Perspectives:**
- New user: name-entry screen. Submit → creates `players` row, issues token stored in localStorage, shows lobby.
- User with valid token in localStorage: skips name entry, calls `reconnect(token)`, resumes at current phase.
- User with token in localStorage but token doesn't match any player (post-reset): clear localStorage, show name-entry.

**When a game is already in progress and a new person (no token) joins:** they see a "Game in progress" screen with a spectate option. If they spectate, they subscribe to `game:public` only. They have no interactions. On game end + reset, they become a regular joiner.

---

### F2: Character selection

**Trigger:** phase = `character_select`.

**Perspectives:**
- All players see 5 character cards in a grid. Each card shows name, flavor text, mechanical effect.
- Picking a character (click) sends `choose_character(slug)` RPC.
- If another player already chose that character → card dimmed with "Taken by Luna" tooltip.
- If the pick is Harry → after the character lock, Harry immediately sees a color picker modal: "Pick the color to protect." 10 colors shown (brown, light-blue, pink, orange, light-green, black, red, yellow, dark-blue, dark-green). Click one → `set_protected_color(color)` RPC. Locked in. No re-pick.
- Once all present players have locked: host sees "Start Game" enabled (≥ 2 locked). Clicks → `start_game` RPC. Phase → `in_game`, first turn_player_id randomized from present seats.

---

### F3: Turn start (DRAW phase)

**Trigger:** `turn_player_id` changes.

**Perspectives:**
- Active player: if Cedric and discard non-empty, sees modal "Draw from Deck (2 cards, face-down) or Top of Discard ([card preview])." Otherwise, auto-draws per character. Cards fly into hand visually. `phase` effectively moves to ACTION.
- Active player: gets browser tab title flash "Your turn!" + subtle border pulse on their seat. No sound unless enabled.
- All players: see `turn_player_id` glow on the active player's seat. Log entry: "Turn T3: Luna's turn."

**Edge cases:**
- Hand empty: draws 5 regardless of character.
- Deck empty mid-draw: reshuffle discard (excluding pending_stack + payment_queue cards) into deck, continue.
- Deck + discard both empty: draw whatever's available, no error.
- Cedric + empty discard: auto-draw from deck with toast "Discard is empty — drew from deck."
- Luna + petrified: draws 2, not 3.

---

### F4: Playing a card to Bank

**Trigger:** active player clicks a Point or Spell card in hand OR drags it onto their Bank zone.

**Perspectives:**
- **Click path:** card lifts, menu appears: "Play to Bank" / "Cast Spell (if spell)" / "Cancel". Click "Play to Bank" → `play_to_bank(card_id)` RPC fires.
- **Drag path:** valid drop zones highlight when dragging starts (Bank is valid for points + spells, item-area columns for items, center for spells). Drop on Bank → same RPC.
- **Illegal cards:** items/wilds in hand show "Play to Bank" grayed with tooltip "Items cannot go in Bank."
- All players: card animates from my hand to my bank, running total updates.
- Log: "Luna banked Accio (1 pt) — bank now 7."
- `plays_this_turn += 1`.

---

### F5: Playing an item card

**Trigger:** active player plays an item / wild.

**Perspectives:**
- Click card in hand → menu offers "Play as Item" (+ Play to Bank if it's a spell, but items can't bank).
- For a two-color wild: menu offers "Play as [Color 1]" / "Play as [Color 2]" (colors shown as swatches).
- For every-color wild: menu offers "Play as [Color]" with submenu of all 10 colors.
- After color resolved, if the player has an existing non-complete column of that color: modal "Add to existing [color] column (n/m) OR Start a new column?" — unless it would exceed set_size, in which case "Start new column" is the only option.
- Drag path: same logic — drop on a specific column adds there; drop on blank item area creates new column.
- **Illegal:** dropping into a complete column is forbidden; drop zone shown red.
- All players see: item slides into the column. If set completes, gold border + "COMPLETE" badge animate in.
- Log: "Luna played Butterbeer — brown (1/2)."
- `plays_this_turn += 1`.

**Post-play win check:** engine counts Luna's complete distinct-color columns. If ≥ 3 AND no pending_stack/payment_queue → win fires.

---

### F6: Recoloring a wild (free action)

**Trigger:** on my turn during ACTION, I click a wild in my item area.

**Perspectives:**
- Menu opens: "Recolor" / "Cancel".
- Recolor → color picker shows legal colors (excluding colors whose column is already complete).
- Click destination color. If I have an existing non-complete column of that color, modal "Add to existing column OR Start new column?". Otherwise new column auto-created.
- Wild moves. If source column is now empty, remove the column.
- If recolor completes a set OR uncompletes a set, emit appropriate animations.
- Log: "Luna recolored WildItem to dark-blue."
- Does NOT increment `plays_this_turn`.

---

### F7: Casting a spell — per-spell targeting flows

**Shared rule:** clicking "Cast Spell" on a card is binding. Play is consumed. Canceling during targeting sends the spell to discard with no effect (play still counted). UI displays a warning on the first "Cast Spell" click for the session: "Cast Spell is binding — once you start targeting, canceling discards the spell with no effect."

#### F7a: Geminio

- Click card → menu: "Play to Bank" / "Cast Spell" / "Cancel".
- "Cast Spell" → play consumed. Animation: 2 cards draw from deck into hand. Spell to discard.
- Log: "Luna cast Geminio (drew 2)."

#### F7b: Reparo

- Click → "Cast Spell" → play consumed. DiscardBrowser modal opens showing every card in discard. If empty (shouldn't be possible if Reparo was legal to cast — dim it if discard empty), error toast.
- I click a card. Confirm button "Take This Card." Or "Cancel" → spell discarded, no card taken.
- Chosen card moves to me per house rules:
  - Item/wild → item area. For wilds I pick color.
  - Point → Bank.
  - Spell → Bank at cash value (locked).
- Log: "Luna used Reparo — took Accio (banked)."

#### F7c: Alohomora

- Click → "Cast Spell" → play consumed. Modal: "Alohomora — each opponent will pay 2 points. Proceed?" / "Cancel."
- Confirm → each opponent queued for Protego decision leftward from me, then payment queue builds.
- Cancel → spell to discard, no effect.

#### F7d: Stupefy

- Click → "Cast Spell" → play consumed. Opponent picker overlay: my opponents highlighted with "Target: Stupefy (5 pts)" tooltip. "Cancel" available.
- Click opponent → Protego queue for that target, then payment for 5 pts.
- Cancel → spell to discard.

#### F7e: Accio (2-color)

- Click → "Cast Spell" → play consumed. Color picker: "Brown or Light-Blue?" with live preview:
  - "Brown: you own 2 items → opponents pay 2 pts each."
  - "Light-Blue: you own 0 items → opponents pay 0 pts each (warning)."
- Click one color → each opponent queued for Protego leftward.
- Cancel → spell to discard.

#### F7f: Accio (any color)

- Click → "Cast Spell" → play consumed. Any-color picker: 10 colors with live preview of payout per color.
- Click one → proceed as F7e.

#### F7g: Levicorpus

- Click → "Cast Spell" → play consumed. Opponent picker: highlight opponents; dimmed if they have no eligible items (e.g. all in complete sets unless I'm Draco; all Harry-protected).
- Click opponent → their item area enlarges. Eligible items highlighted; ineligible dimmed with tooltip ("complete-set" or "Harry-protected").
- Click an item → Protego offered to target.
- Cancel at any targeting step → spell to discard.

#### F7h: Confundo

- Click → "Cast Spell" → play consumed. **Step 1:** my item area enlarges; I pick ONE of my non-complete-set items. Ineligible dimmed ("in complete set — no Draco override exists for casting Confundo").
- **Step 2:** opponent picker like F7g.
- **Step 3:** their item picker like F7g.
- Confirm → Protego queue; if passes, swap happens.
- Cancel at any step → spell to discard.

#### F7i: Wingardium Leviosa

- Same as F7g but the action is "discard" not "take" — item goes to discard pile, not my area.

#### F7j: Obliviate

- Click → "Cast Spell" → play consumed. Opponent picker (only opponents with at least one non-Harry-protected complete set enabled).
- Click opponent → their complete sets highlighted. Click one → Protego offered.
- Cancel → spell to discard.

#### F7k: Petrificus Totalus

- Click → "Cast Spell" → play consumed. Opponent picker (exclude already-petrified opponents).
- Click → Protego offered.
- On resolve (non-Protego): Petrificus card ATTACHES to target's character card visually. Does NOT go to discard.
- Log: "Luna cast Petrificus Totalus on Chintan — petrified."

#### F7l: Protego

- In hand outside a reaction: click → menu shows ONLY "Play to Bank" + "Cancel." No "Cast Spell" option.
- In hand during a reaction where I'm the awaiter: handled in F10.

**Universal cancel contract:** clicking Cancel during any targeting step (F7c–F7k) discards the spell with no effect; play is still consumed. A small log line notes: "Luna cancelled Confundo (spell discarded, play spent)."

---

### F8: Ending the turn normally

**Trigger:** active player clicks "End Turn."

**Perspectives:**
- If `hand.length <= 7`: `end_turn` RPC fires. Turn advances.
- If `hand.length > 7`: server returns `{status: "must_discard", excess: N}`. See F11 (Discard Picker).

---

### F9: Being the target of a spell — reaction decision

**Trigger:** a spell frame is on pending_stack with `awaiting_response_from = me`.

**Perspectives — target:**
- Full-screen reaction modal (dark backdrop, modal blocks interaction elsewhere).
- Shows:
  - Caster name + avatar.
  - Spell name + flavor text + rules text.
  - Consequence if it lands (e.g. "You'll pay 5 pts" / "Chintan will take your Snitch" / "Chintan will take your complete Yellow set" / "You'll be petrified").
- Two buttons:
  - **"Play Protego"** — enabled only if I have Protego in hand AND spell is Protego-eligible. Tooltip when disabled: "No Protego in hand."
  - **"Take the hit"** — always enabled.
- No countdown (host referees).
- **If I have no Protego at all:** skip the modal. Instead, 2-second auto-notification toast: "Luna cast Stupefy on you — taking the hit." Server auto-advances pending_stack. (Per your design choice.)

**Perspectives — caster:**
- Sees pending_stack grow in the center panel.
- Target seat shows "Chintan is deciding..." indicator.
- Can't take any other action until resolved or Host force-resolves.

**Perspectives — bystanders:**
- Same as caster. Watch the stack.

**If target is disconnected:** indicator shows "Chintan is offline." Host's sidebar shows **"Force Pass (Chintan)"** button. Clicking it sets target's status to `awaiting_hit` (took the hit) and resolves.

---

### F10: Playing Protego during a reaction

**Trigger:** target clicks "Play Protego" in the F9 modal.

**Perspectives — target:**
- Brief animation (~1.5s): Protego card flies from hand to pending_stack with a shield flash on the target's seat.
- Modal closes.

**Perspectives — caster:**
- Sees Protego land on stack.
- **Immediately enters F9 themselves** as the new awaiter: modal appears asking "Chintan blocked your Stupefy with Protego. Counter with your own Protego? Or accept?"
- If caster has Protego in hand, they can chain.
- If they don't, auto-advance with 2s notification "Your Stupefy was blocked."

**Perspectives — bystanders:**
- Watch stack grow.

**Chain continues until someone passes or runs out of Protegos.** Then resolution cascades:
- Top Protego cancels the frame below it (paired cancellation per `one_cancels_one`).
- Net effect: even-depth chain = spell resolves; odd-depth chain = spell cancelled.
- All chain cards to discard in order.
- If spell resolves, payment / item-movement / petrificus-attach happens next.

---

### F11: Discard Picker (hand > 7 at turn end)

**Trigger:** player clicked End Turn with hand.length > 7.

**Perspectives — active player:**
- Modal: "You have {hand.length} cards. Discard {excess} to end your turn."
- All hand cards shown with checkboxes.
- Running counter: "Selected: 0 / {excess}." Confirm button disabled until exactly `excess` selected.
- **No Cancel button** — they must finish. (They can't "unplay" their turn.)
- On confirm, `end_turn_with_discard(card_ids)` RPC fires. Server validates count, moves cards to discard, advances turn.

**Perspectives — others:**
- See "Luna is discarding..." indicator on her seat.
- Hand count badge updates when she confirms.

**Log:** "Luna discarded 2 cards (hand 9 → 7)."

---

### F12: Paying a debt

**Trigger:** I'm the current debtor in `payment_queue`.

**Perspectives — debtor:**

**Pre-check:** server computes my total available (Bank cash + item cash, excluding every-color wilds with cash 0).
- If total == 0: skip modal. Log "Chintan had nothing to pay; debt forgiven." Advance queue.
- Otherwise: full-screen payment modal.

Modal contents:
- Top banner: "You owe Luna {amount} points."
- Two sections: **Bank** (all bank cards with cash values, checkboxable) and **Item Area** (all items with cash values, checkboxable; every-color wilds shown but disabled with "cash 0 — cannot pay with this" tooltip).
- Running total: "Selected: {sum} pts." Turns green when ≥ amount.
- Warning if overpaying: "You will overpay by {X} pts (no change given)."
- If total available < amount, pre-select ALL cards, show "You don't have enough — paying everything. {X} pts forgiven." Only "Confirm" button enabled.
- Buttons:
  - **"Pay Selected"** — enabled when sum ≥ amount OR all cards selected.
  - **"Cancel"** is NOT provided (payment is compulsory).

On confirm:
- Bank cards → recipient's Bank.
- Item cards → recipient's item area. Default: append to existing non-complete column of same color if one exists, else new column. Wilds preserve current color.
- Payment recipient sees items/cards fly into their zones with a chime-like animation.
- Log: "Chintan paid Luna 5 pts (3-pt Galleon + 2-pt Geminio banked)."

**Perspectives — recipient:**
- "Waiting for Chintan to pay..." indicator during selection.
- Cards arrive after confirm. Running totals update. Potential set-complete animation if an item was paid.

**Perspectives — bystanders:**
- "Chintan is paying Luna (5 pts)..." indicator.

**If debtor is disconnected:** host sees "Force Auto-Pay (Chintan)" button. Clicking it runs the minimum-overpayment algorithm:
- Start with empty selection.
- Add cash cards in ascending cash_value order until sum ≥ debt. This minimizes overpayment.
- Among item vs bank, prefer bank first (keeps item collection intact for the player).
- If total available < debt, auto-select all.
- Submit as normal payment. Log "Auto-paid by host."

---

### F13: Removing Petrificus Totalus

**Trigger:** petrified player clicks Petrificus card attached to their character during their own ACTION phase.

**Perspectives — petrified player:**
- Modal: "Remove Petrificus Totalus — discard ≥ 10 points from your Bank."
- My Bank cards shown with checkboxes. Running total. "Confirm" disabled until sum ≥ 10.
- Confirm → cards to discard, petrified = false, Petrificus card to discard.
- Cancel → modal closes, petrified remains.
- Does NOT count as a play.
- Log: "Luna removed Petrificus Totalus (discarded 10 pts)."

---

### F14: Game end

**Trigger:** winner_player_id set, phase = `finished`.

**Perspectives — everyone:**
- Full-screen winner banner: character portrait, name, "WINS!" in their character's banner color. Confetti.
- Buttons:
  - **"New Game"** (any player): triggers Reset Lobby → character_select with same seats.
  - **"Full Reset"** (host only): wipes everything.

---

### F15: Host Force Resolve (AFK rescue)

**Trigger:** some player is AFK and blocking the game.

**Perspectives — host:**
- Sidebar highlights the current stuck state. Button text is contextual:
  - "Force Pass (Chintan)" during reaction decision
  - "Force Auto-Pay (Chintan)" during payment
  - "Force End Turn (Chintan)" during active turn
- Click → corresponding RPC fires. Server resolves the state using the default path for that decision (pass reaction / auto-pay minimum / discard conservative + end turn).
- Log entry: "Host force-resolved Chintan's decision."

**Perspectives — others:**
- State unsticks, game continues. They see the log entry explaining what happened.

---

### F16: Host pause

**Trigger:** host clicks Pause.

- `phase = 'paused'`, `previous_phase` saved. All RPCs except `resume_game` and admin actions are rejected.
- Everyone sees a full-screen "PAUSED — Host is paused the game" overlay.
- Resume → phase restored, game continues from exact prior state.

---

### F17: Host disconnect & auto-transfer

**Trigger:** host's `is_connected = false` for > 30 seconds.

- Server RPC `check_host_status` runs on any public-channel event; if host has been disconnected beyond threshold, performs atomic host transfer to the connected player with earliest `joined_at`.
- Log: "Host transferred from Luna to Hermione (Luna offline)."
- New host sees host-controls appear in their sidebar.
- If Luna reconnects, she's a regular player.

---

## Ground-truth summary for Lovable

**Must implement exactly:**
- Every number in the deck composition table.
- Every color + set size + charge table in the item_sets table.
- Every character ability as written.
- Every spell effect as written.
- Every interaction flow F1–F17.

**Must support via admin UI (not seed-time):**
- Per-card art uploads.
- Per-card text edits.
- Settings toggles for house rules.

**Must NOT implement (out of scope):**
- In-app chat, voice, reactions.
- Cross-session identity.
- Countdowns or auto-timeouts on player decisions.
- Optimistic client updates.
- Spectator interactions (spectators are view-only).
- Game-history replay or stats across games.

**Don't ship without passing `test-plan.md`.**

Ship it.
