# Test plan — Monopoly Deal HP

This is the acceptance-test specification for `lovable-prompt-v5.md`. Every slice has its own test suite. A slice is "done" when all tests pass.

Tests are grouped by slice, then by category. Each test has:
- **Setup:** what to configure before running
- **Steps:** user actions
- **Expected:** what must be true after

Use the `?dev=1` bot-fill toggle to run multi-player tests solo. Impersonate each seat via the host's click-to-impersonate.

---

## Slice 0 — Infra

### T0.1 Concurrency smoke test
- **Setup:** Supabase project provisioned, schema created, `increment_counter` RPC deployed, two browser tabs opened to same room.
- **Steps:** In a JS console in each tab, `for (let i = 0; i < 100; i++) supabase.rpc('increment_counter')`. Run both simultaneously.
- **Expected:** Final counter value = exactly 200. If less, version-check is broken — do NOT proceed.

### T0.2 RLS denies client writes
- **Steps:** In JS console, `await supabase.from('game_state').update({ phase: 'finished' }).eq('id', 1)`.
- **Expected:** Update fails with permission error. Phase unchanged.

### T0.3 Public view excludes deck order
- **Steps:** Seed deck. `await supabase.from('game_state_public').select('*').single()`.
- **Expected:** No `deck_order` column returned. `deck_count` is a number.

### T0.4 Public view excludes hands
- **Steps:** Seed a game with players holding hands. `await supabase.from('players_public').select('*')`.
- **Expected:** No `hand` field. `hand_count` is a number per player. `token` field not returned.

---

## Slice 1 — Lobby + reconnect

### T1.1 First joiner becomes host
- **Steps:** Open URL, enter name "Alice."
- **Expected:** Alice is in the lobby, host badge on her seat, host controls visible only to her.

### T1.2 Second joiner is non-host
- **Steps:** Open URL in another browser, enter name "Bob."
- **Expected:** Both Alice and Bob see both players. Alice has host badge, Bob doesn't. Host controls visible only to Alice.

### T1.3 Duplicate name suffixing
- **Steps:** Third person joins with name "Alice."
- **Expected:** Joined as "Alice (2)." No collision.

### T1.4 Refresh preserves identity
- **Steps:** Alice refreshes her tab.
- **Expected:** Alice resumes as Alice, still host, other players unaffected.

### T1.5 Full reset clears tokens
- **Steps:** Alice clicks Full Reset. Refreshes.
- **Expected:** Alice sees name-entry screen (not reconnected). Can join as a fresh player.

### T1.6 Host kick (pre-game)
- **Steps:** Alice clicks Kick on Bob's seat.
- **Expected:** Bob removed from lobby. Bob's browser sees "You've been removed" screen.

### T1.7 Max players enforcement
- **Steps:** 6 people try to join.
- **Expected:** 6th sees "Game is full" screen. No 6th seat created.

---

## Slice 2 — Character select

### T2.1 Character uniqueness
- **Setup:** 3 players in character select.
- **Steps:** Alice picks Harry. Bob tries to pick Harry.
- **Expected:** Harry card is grayed for Bob with "Taken by Alice" tooltip.

### T2.2 Harry color picker
- **Steps:** Alice picks Harry.
- **Expected:** Color picker modal appears showing all 10 colors. Alice picks red. `protected_color = 'red'` saved.

### T2.3 Start Game enabled at 2+
- **Setup:** Alice locked, Bob unlocked.
- **Expected:** Start Game button disabled for Alice.
- **Steps:** Bob picks Luna.
- **Expected:** Start Game button enabled for Alice.

### T2.4 Start Game randomizes first player
- **Steps:** Alice clicks Start Game.
- **Expected:** Phase changes to `in_game`. `turn_player_id` is one of the present players (randomized). Log: "Turn T1: {Player}'s turn."

---

## Slice 3 — Minimum playable game (points + items only)

### T3.1 Initial deal
- **Expected:** Every player's `hand_count = 5` at game start. `deck_count = 106 - (5 × num_players)`.

### T3.2 Draw on turn start
- **Setup:** Alice's turn, hand count 5.
- **Steps:** Turn begins (automatic after start).
- **Expected:** Alice's `hand_count = 7`. `deck_count -= 2`. `has_drawn_this_turn = true`.

### T3.3 Empty-hand draws 5
- **Setup:** Alice's turn, hand count 0 at start (contrived via test helpers).
- **Expected:** Alice draws 5, not 2.

### T3.4 Luna draws 3
- **Setup:** Luna's turn, hand count 5.
- **Expected:** After draw, Luna's hand_count = 8.

### T3.5 Play to bank
- **Setup:** Alice's turn, 3-pt Galleon in hand.
- **Steps:** Click the card, select "Play to Bank."
- **Expected:** Card moves to bank. `plays_this_turn = 1`. Bank total = 3.

### T3.6 Play item to new column
- **Setup:** Alice has Butterbeer in hand, no brown items yet.
- **Steps:** Click → "Play as Item."
- **Expected:** New brown column with Butterbeer. Column header: "brown 1/2". `plays_this_turn = 1`.

### T3.7 Play item to existing column
- **Setup:** Alice has 1 brown column with Butterbeer (1/2). Pumpkin Juice in hand.
- **Steps:** Click → "Play as Item."
- **Expected:** Modal asks "Add to existing brown column (1/2)? OR Start a new column?" Alice picks "Add." Column becomes 2/2 with COMPLETE badge.

### T3.8 Multiple columns same color (Obliviate defense)
- **Setup:** Continues from T3.7. Alice draws another Butterbeer.
- **Steps:** Click → "Play as Item."
- **Expected:** Modal asks "Add to existing brown column (2/2)? — blocked because complete. OR Start a new column?" Only "Start new column" enabled. Second brown column created.

### T3.9 Column can't exceed set_size
- **Setup:** Alice has complete brown column (2/2).
- **Steps:** Try to play a third Butterbeer into that column (not as new column).
- **Expected:** Server rejects. Error toast "Column is complete."

### T3.10 End turn with ≤ 7 cards
- **Setup:** Alice's hand count = 7.
- **Steps:** End Turn.
- **Expected:** Turn advances to next left seat. Alice sees her seat un-highlighted.

### T3.11 End turn with > 7 cards — discard picker
- **Setup:** Alice's hand count = 9 (e.g. she played 0 cards after drawing 2).
- **Steps:** Click End Turn.
- **Expected:** Discard Picker modal appears: "You have 9 cards. Discard 2 to end your turn." No Cancel button. Checkboxes on all 9 cards, confirm disabled until exactly 2 selected. Alice picks 2, clicks Confirm. Cards to discard pile. Turn advances.

### T3.12 3-complete-set win
- **Setup:** Alice has 2 complete columns. She plays a card that completes her 3rd.
- **Expected:** Game ends immediately. Phase = `finished`. Winner banner appears. Log: "{Alice} wins with 3 complete sets: brown, light-blue, red."

### T3.13 Win must be distinct colors
- **Setup:** Alice has 3 complete brown columns (impossible normally but force via bot-fill).
- **Expected:** No win (not 3 distinct colors). Game continues.

### T3.14 Turn order is LEFT
- **Setup:** 3 players seated: Alice (seat 0), Bob (seat 1), Chintan (seat 2). First turn Alice.
- **Steps:** Alice ends turn, then Bob.
- **Expected:** Order is Alice → Bob → Chintan → Alice. (Leftward increment of seat_index.)

### T3.15 Disconnected seat is skipped
- **Setup:** Alice → Bob → Chintan. Bob disconnects during Alice's turn.
- **Steps:** Alice ends turn.
- **Expected:** Turn advances to Chintan (skipping Bob). Bob's seat shows "Reconnecting..." badge.

### T3.16 Deck reshuffle when empty
- **Setup:** Force deck to have 1 card, discard pile has 10.
- **Steps:** Alice starts turn, needs to draw 2.
- **Expected:** 1 card drawn from deck, discard reshuffled into deck (excluding any in pending_stack), 1 more card drawn. Final hand correct.

### T3.17 Both piles empty
- **Setup:** Force deck + discard both empty.
- **Steps:** Alice starts turn.
- **Expected:** 0 cards drawn. No error. Turn proceeds. Alice can still play cards from her hand.

---

## Slice 4 — Wild items + recolor

### T4.1 Two-color wild play
- **Setup:** Alice has brown/light-blue wild in hand.
- **Steps:** Click → "Play as Item." Menu offers "Play as Brown" / "Play as Light-Blue."
- **Expected:** She picks Brown. New brown column (or appends). Wild shown with brown side visible.

### T4.2 Every-color wild play
- **Setup:** Alice has every-color wild in hand.
- **Steps:** Click → "Play as Item." Menu offers all 10 colors.
- **Expected:** Picks dark-blue. New dark-blue column with wild inside.

### T4.3 Wild recolor (free)
- **Setup:** Alice's turn, she has a brown/light-blue wild in her brown column.
- **Steps:** Click the wild in item area → "Recolor" → "Light-Blue."
- **Expected:** Wild moves to light-blue column (existing or new). `plays_this_turn` unchanged.

### T4.4 Recolor target complete
- **Setup:** Alice has a complete light-blue column (3/3). Her wild is in brown.
- **Steps:** Click wild → "Recolor" → try "Light-Blue."
- **Expected:** Light-Blue option is grayed OR offers "Start new light-blue column" only. Cannot exceed set_size.

### T4.5 All-every-color-wild set is invalid
- **Setup:** Alice plays 2 every-color wilds into dark-blue (set size 2).
- **Expected:** Column shows "2/2" but NOT marked COMPLETE. Win condition doesn't fire even if she has 2 other complete sets.

### T4.6 Mixed wild + real completes set
- **Setup:** Alice has Felix Felicis in dark-blue. She plays an every-color wild as dark-blue.
- **Expected:** Column 2/2, marked COMPLETE (contains at least one non-every-color card).

### T4.7 Wild cash in payment
- **Setup:** (Slice 6 will re-test this.) Two-color wild with cash 2 is in Alice's item area.
- **Expected:** When Alice needs to pay and selects this wild, counts as 2 points.

### T4.8 Every-color wild can't pay
- **Setup:** Every-color wild in Alice's item area.
- **Expected:** In payment modal, shown but disabled with tooltip "cash 0 — cannot pay with this."

---

## Slice 5 — Non-reactive spells (no Protego yet)

### T5.1 Geminio draws 2
- **Setup:** Alice has Geminio in hand. Hand count 5.
- **Steps:** Cast Geminio.
- **Expected:** Hand count 7. Geminio to discard. `plays_this_turn += 1`.

### T5.2 Geminio when deck empty
- **Setup:** Deck has 1 card, discard has 5.
- **Steps:** Cast Geminio.
- **Expected:** Draws 1, reshuffles discard (minus Geminio itself, which is going to discard now), draws 1 more. Hand correct.

### T5.3 Reparo — pick from discard
- **Setup:** Discard has [Accio, Butterbeer]. Alice casts Reparo.
- **Steps:** DiscardBrowser opens. Alice picks Butterbeer. Confirm.
- **Expected:** Butterbeer to Alice's item area (brown column). Accio stays in discard. Reparo to discard.

### T5.4 Reparo empty discard
- **Setup:** Discard empty.
- **Expected:** Reparo grayed in hand with tooltip "Discard pile is empty."

### T5.5 Reparo retrieves a spell — default house rule
- **Setup:** `settings.reparo_spell_destination = "bank_as_points"`. Discard has Stupefy.
- **Steps:** Alice Reparo's Stupefy.
- **Expected:** Stupefy goes to Alice's Bank as 3-pt cash (locked). Cannot be cast later.

### T5.6 Levicorpus takes an item
- **Setup:** Alice casts Levicorpus, targets Bob, picks Bob's Snitch (not in complete set).
- **Expected:** Snitch moves to Alice's red column. Bob's red column decrements.

### T5.7 Levicorpus blocked by complete set
- **Setup:** Bob has a complete yellow set. Alice casts Levicorpus, picks Bob.
- **Expected:** Bob's complete-set items dimmed with "complete-set" tooltip. Not clickable (unless Alice is Draco).

### T5.8 Draco can take from complete set
- **Setup:** Alice is Draco. Bob has complete yellow set.
- **Steps:** Alice casts Levicorpus, picks Bob.
- **Expected:** All Bob's items (including complete-set) enabled. Alice can pick any.

### T5.9 Levicorpus when no eligible target
- **Setup:** All opponents have only complete sets and Alice isn't Draco.
- **Expected:** Levicorpus grayed in hand with tooltip "No opponent has a non-complete item."

### T5.10 Confundo 3-step flow
- **Setup:** Alice has Butterbeer (brown, not complete). Bob has Snitch (red, not complete).
- **Steps:** Alice casts Confundo. Step 1: picks her Butterbeer. Step 2: picks Bob. Step 3: picks Bob's Snitch. Confirm.
- **Expected:** Butterbeer → Bob's brown column. Snitch → Alice's red column.

### T5.11 Confundo cancel mid-targeting
- **Setup:** Alice casts Confundo. Step 1 complete. At step 2, she clicks Cancel.
- **Expected:** Confundo to discard. No swap. `plays_this_turn` still incremented (play was consumed).
- **Log:** "Alice cancelled Confundo (spell discarded, play spent)."

### T5.12 Wingardium Leviosa discards opponent item
- **Setup:** Bob has Snitch (not complete).
- **Steps:** Alice casts Wingardium Leviosa, targets Bob's Snitch.
- **Expected:** Snitch to discard pile. Bob's red column decrements.

### T5.13 Obliviate takes complete set
- **Setup:** Bob has complete dark-blue (Felix Felicis + Veritaserum).
- **Steps:** Alice casts Obliviate, targets Bob's dark-blue column.
- **Expected:** Both cards move to Alice's item area (new dark-blue column if she didn't have one, or appended). Alice's column is now 2/2 COMPLETE. Bob loses his column entirely.

### T5.14 Obliviate needs a complete set
- **Setup:** No opponent has a complete set.
- **Expected:** Obliviate grayed in hand with tooltip "No opponent has a complete set."

### T5.15 Banking a spell
- **Setup:** Alice has Protego in hand.
- **Steps:** Click → "Play to Bank."
- **Expected:** Protego in bank at 4 cash (locked watermark). `plays_this_turn += 1`. Cannot be cast later.

### T5.16 Cast Spell is binding
- **Setup:** Alice casts Confundo. Clicks Cancel at step 1.
- **Expected:** Confundo to discard. `plays_this_turn` incremented. No further UI.

---

## Slice 6 — Debt payments (no Protego yet)

### T6.1 Stupefy — single debtor
- **Setup:** Alice casts Stupefy on Bob. Bob has Bank with 2-pt + 4-pt.
- **Expected:** Bob sees payment modal "You owe Alice 5 pts." Bob selects 2+4 = 6 (overpays 1). Confirms. Bob's bank decreases; Alice's bank gains 2-pt + 4-pt. Log notes overpayment.

### T6.2 Exact payment
- **Setup:** Bob has 5-pt in bank. Alice casts Stupefy.
- **Expected:** Bob selects the 5-pt. Pays exactly. No overpayment warning.

### T6.3 Underpayment (insufficient funds)
- **Setup:** Bob has 2-pt in bank, no items.
- **Steps:** Alice casts Stupefy (owes 5).
- **Expected:** Modal pre-selects the 2-pt with message "You don't have enough — paying everything. 3 pts forgiven." Confirm. Bob bank empty. Alice gains 2.

### T6.4 Nothing to pay
- **Setup:** Bob has empty bank AND empty item area.
- **Steps:** Alice casts Stupefy.
- **Expected:** No modal shown to Bob. Auto-log "Bob had nothing to pay; debt forgiven." Queue advances.

### T6.5 Item payment
- **Setup:** Bob has empty bank, has Butterbeer (1pt) and Snitch (3pt) in items.
- **Steps:** Alice casts Stupefy (owes 5).
- **Expected:** Modal shows bank empty, items section has both cards selectable. Bob selects both (4 total, less than 5). "Paying everything — 1 pt forgiven." Items to Alice's area.

### T6.6 Mixed payment
- **Setup:** Bob has 2-pt in bank + Snitch (3pt) in items.
- **Steps:** Alice casts Stupefy.
- **Expected:** Bob selects both. Exactly 5. Bank card goes to Alice's bank; Snitch goes to Alice's red column.

### T6.7 Item payment destination — append to existing
- **Setup:** Alice has an incomplete red column with Quaffle (1/3). Bob pays her a Snitch.
- **Expected:** Snitch appends to Alice's existing red column (2/3).

### T6.8 Item payment destination — new column (if existing complete)
- **Setup:** Alice's red column is complete. Bob pays her another Snitch.
- **Expected:** New red column created for Alice (1/3).

### T6.9 Wild payment preserves color
- **Setup:** Bob has a brown/light-blue wild currently set to brown. He pays it to Alice.
- **Expected:** Wild arrives in Alice's brown column (or new). Alice can recolor on her next turn.

### T6.10 Every-color wild can't pay
- **Setup:** Bob has ONLY an every-color wild in items, bank empty. Alice casts Stupefy.
- **Expected:** Modal shows every-color wild disabled. Total available = 0. "Nothing to pay; debt forgiven."

### T6.11 Banked spell as payment
- **Setup:** Bob has a banked Protego (4 pts). Alice casts Stupefy.
- **Expected:** Bob selects the banked Protego. Goes to Alice's bank, still locked. Alice can NEVER cast it (it's marked locked from the moment it was banked).

### T6.12 Alohomora queues all opponents
- **Setup:** 4 players: Alice, Bob, Chintan, Dave. Alice casts Alohomora.
- **Expected:** Payment queue: Bob → Chintan → Dave (leftward from Alice). Only Bob's modal appears first. When Bob resolves, Chintan's shows. Etc.

### T6.13 Accio with 0 items
- **Setup:** Alice casts Accio (brown/light-blue), picks brown. She owns 0 brown items.
- **Expected:** Preview shows "0 pts from each opponent (warning)." Confirm → queue runs with amount = 0. All debtors see "nothing to pay" and log entries only.

### T6.14 Accio with partial set
- **Setup:** Alice has 1 Butterbeer (brown, set size 2). Casts Accio → picks brown.
- **Expected:** Each opponent owes 1 pt (from `charge_table["1"] = 1` for brown). Queue runs sequentially.

### T6.15 Accio with complete set
- **Setup:** Alice has Butterbeer + Pumpkin Juice (complete brown). Casts Accio → picks brown.
- **Expected:** Each opponent owes `charge_table["complete"] = 2` pts.

### T6.16 Win via payment
- **Setup:** Alice has 2 complete sets. Bob owes her a red Snitch that completes her 3rd red column.
- **Steps:** Bob confirms payment.
- **Expected:** After payment_queue fully drains AND pending_stack empty, win fires. Alice wins.

### T6.17 Accio any-color picker
- **Setup:** Alice casts accio_any. She has items in brown (2) and yellow (1).
- **Expected:** Color picker shows all 10 colors with per-color payout preview. Clicking "pink" (she has 0 pink) casts with 0 payout, not an error.

---

## Slice 7 — Protego reaction stack

### T7.1 Basic Protego blocks spell
- **Setup:** Alice casts Stupefy on Bob. Bob has Protego in hand.
- **Steps:** Bob sees reaction modal. Clicks Play Protego.
- **Expected:** Alice sees "Your Stupefy was blocked" modal. Alice has no Protego → auto-resolve after 2s notification. Both Stupefy and Protego to discard. Bob pays nothing.

### T7.2 No Protego — auto-resolve
- **Setup:** Alice casts Stupefy on Bob. Bob has no Protego.
- **Expected:** Bob sees a 2-second "Alice cast Stupefy on you — taking the hit" toast, NOT a modal. Server auto-advances. Payment modal follows.

### T7.3 Counter-Protego chain depth 2
- **Setup:** Alice casts Stupefy on Bob. Both have Protego.
- **Steps:** Bob plays Protego. Alice's reaction modal appears. Alice plays Protego.
- **Expected:** Depth-2 chain: Bob's Protego cancels Alice's Stupefy portion, but Alice's Protego cancels Bob's Protego, so Stupefy ultimately resolves. Bob owes 5. All chain cards to discard.

### T7.4 Counter-Protego chain depth 3
- **Setup:** Alice (1 Protego) casts Stupefy on Bob (2 Protegos).
- **Steps:** Bob plays Protego. Alice plays Protego. Bob plays Protego.
- **Expected:** Depth-3 chain, ultimately Stupefy is blocked. Bob pays nothing.

### T7.5 Multi-target spell partial Protegos
- **Setup:** Alice casts Alohomora. Bob has Protego, Chintan doesn't, Dave has Protego.
- **Steps:** Bob plays Protego (Alice has no Protego → auto-pass caster). Chintan has no Protego → auto-take-hit. Dave plays Protego (Alice auto-pass again).
- **Expected:** Bob and Dave safe. Only Chintan pays 2.

### T7.6 Protego frame clears from stack on resolution
- **Setup:** Post T7.1.
- **Expected:** `pending_stack` is empty. Game continues from Alice's turn (she used a play by casting).

### T7.7 Protego can't be cast outside a reaction
- **Setup:** Alice's turn. She has Protego in hand.
- **Steps:** Click Protego.
- **Expected:** Menu shows ONLY "Play to Bank" + "Cancel." No "Cast Spell" option.

### T7.8 Reaction modal blocks other actions
- **Setup:** Alice casts Stupefy on Bob. Chintan (bystander) tries to click his own cards.
- **Expected:** Chintan's cards are non-interactive until the pending_stack resolves. Small indicator "Bob is deciding..." visible.

### T7.9 Obliviate + Protego — protected on block
- **Setup:** Alice has complete sets × 2, Bob has a complete set Alice wants. Bob has Protego.
- **Steps:** Alice casts Obliviate on Bob. Bob Protegos. Alice has no Protego.
- **Expected:** Obliviate blocked. Bob keeps his set. Game continues.

### T7.10 Obliviate + Protego — win deferred until resolution
- **Setup:** Alice has 2 complete sets. She casts Obliviate on Bob's complete set. Bob plays Protego, Alice counter-Protegos (depth 2 = spell resolves).
- **Expected:** During stack resolution, win does NOT fire even though mid-resolution Alice momentarily has 3 sets on paper. Only after all chain cards to discard AND pending_stack empty AND payment_queue empty → win fires. (This prevents false wins from reversed spells.)

### T7.11 Host Force Pass during Protego decision
- **Setup:** Alice casts Stupefy on Bob. Bob has Protego but disconnects.
- **Expected:** Bob's seat shows "offline." Host sees "Force Pass (Bob)" button. Host clicks it. Stupefy resolves, Bob pays 5.

### T7.12 Reparo'd spell can be cast (alternate house rule)
- **Setup:** `settings.reparo_spell_destination = "cast_for_effect"`. Discard has Stupefy. Alice has `plays_this_turn = 1` (2 plays remaining).
- **Steps:** Alice casts Reparo, picks Stupefy. Modal offers "Cast Stupefy now (uses 1 more play) OR Bank as 3 pts."
- **Expected:** Stupefy is castable as a second play.

---

## Slice 8 — Petrificus Totalus + character powers

### T8.1 Petrificus attaches
- **Setup:** Alice casts Petrificus Totalus on Bob.
- **Expected:** `Bob.petrified = true`. Petrificus card visually on Bob's character card. Card NOT in discard.

### T8.2 Petrified Hermione plays 3 not 4
- **Setup:** Bob is Hermione, petrified. His turn.
- **Expected:** `plays_allowed_this_turn = 3`.

### T8.3 Petrified Luna draws 2 not 3
- **Setup:** Bob is Luna, petrified.
- **Expected:** Draws 2 at turn start.

### T8.4 Petrified Cedric can't pick discard
- **Setup:** Bob is Cedric, petrified. Discard non-empty.
- **Expected:** No "draw from discard" modal. Auto-draws 2 from deck.

### T8.5 Petrified Harry unprotected
- **Setup:** Harry protects red. Bob petrifies Harry.
- **Steps:** Bob tries to take one of Harry's red items via Levicorpus.
- **Expected:** All of Harry's items including red are eligible targets.

### T8.6 Petrified Draco loses override
- **Setup:** Draco is petrified. Draco tries Levicorpus on complete set.
- **Expected:** Complete set items dimmed. Draco blocked like any other non-Draco.

### T8.7 Petrificus removal — 10 pts from bank
- **Setup:** Bob is petrified, has 10 pts in bank.
- **Steps:** On Bob's turn ACTION phase, clicks Petrificus on his character. Modal: "Discard ≥ 10 from bank." Selects 10 exactly. Confirms.
- **Expected:** Cards to discard. `petrified = false`. Petrificus card to discard. Not a play (plays_this_turn unchanged).

### T8.8 Petrificus removal — not enough
- **Setup:** Bob has only 5 pts in bank.
- **Expected:** Confirm button stays disabled. Bob can select all 5 but sum < 10. Modal informs "Need 10+ points."

### T8.9 Petrificus removal overpayment
- **Setup:** Bob has 4-pt + 10-pt in bank.
- **Steps:** Selects only the 10-pt.
- **Expected:** Valid. Confirm enabled. 10-pt to discard, petrified = false.

### T8.10 Hermione bonus when un-petrified mid-turn
- **Setup:** Hermione is petrified, her turn. She has `plays_allowed_this_turn = 3`. After 2 plays, she removes Petrificus.
- **Expected:** `plays_allowed_this_turn` immediately becomes 4. She has 2 plays remaining (4 - 2 used).

### T8.11 Harry's protection against spells
- **Setup:** Harry protects red. Alice casts Levicorpus on Harry.
- **Expected:** Harry's red items dimmed with "Harry-protected." Alice can pick any non-red item.

### T8.12 Harry protection on two-color wild
- **Setup:** Harry has brown/red wild currently set to red. Harry protects red.
- **Expected:** The wild counts as red for protection purposes — it's dimmed to Alice's Levicorpus.

### T8.13 Harry protects against Obliviate
- **Setup:** Harry has complete red set. Alice casts Obliviate on Harry.
- **Expected:** Red set dimmed. If all of Harry's complete sets are red, Alice can't pick any — game should allow cancel (binding: spell discarded, play consumed).

### T8.14 Harry can't protect his only non-complete from Levicorpus if Draco exists
- **Setup:** Harry has red complete set + 1 non-complete brown item. Alice (Draco) casts Levicorpus.
- **Expected:** Harry's protected red is dimmed even to Draco (Draco ignores complete-set but NOT Harry-protected). Brown item is eligible.

### T8.15 Luna draws 3 normally
- **Setup:** Luna's turn, hand count 5, not petrified.
- **Expected:** Draws 3 at turn start. Hand count 8.

### T8.16 Cedric draws from discard
- **Setup:** Cedric's turn, hand count 5, discard pile has [Butterbeer, Accio, Stupefy]. Not petrified.
- **Expected:** Modal offers "Draw from Deck OR Top of Discard (Stupefy)." Cedric picks discard. Stupefy to hand. Then continues draw to hand count 7 (1 from discard + 1 from deck).

### T8.17 Hermione 4 plays
- **Setup:** Hermione's turn, not petrified. She plays 4 cards.
- **Expected:** 4th play allowed. End Turn after 4th (or 3rd if she wants) works normally.

---

## Slice 9 — Polish, host controls, admin

### T9.1 Pause freezes game
- **Setup:** Mid-game, Alice's turn. Host clicks Pause.
- **Expected:** Everyone sees "PAUSED" overlay. No actions possible. Alice can't click her cards. Log: "Host paused the game."

### T9.2 Resume restores state
- **Setup:** Continues T9.1. Host clicks Resume.
- **Expected:** Phase restored. Alice's turn resumes exactly where it was. All state intact.

### T9.3 Host force auto-pay
- **Setup:** Alice casts Stupefy on Bob. Bob disconnects during payment modal.
- **Expected:** Host sidebar shows "Force Auto-Pay (Bob)" button. Host clicks. Server auto-pays minimum overpayment. Log: "Host force-resolved Bob's payment."

### T9.4 Host force end turn
- **Setup:** Alice's turn. She disconnects mid-action.
- **Expected:** After brief disconnect detection, host sees "Force End Turn (Alice)." Clicks. Server discards Alice's hand to 7 (conservatively, e.g. newest cards), advances turn.

### T9.5 Host disconnect auto-transfer
- **Setup:** Alice is host. She closes her tab. Wait 35 seconds.
- **Expected:** Host auto-transfers to next-earliest-joined connected player (e.g. Bob). Bob's sidebar shows host controls. Log: "Host transferred from Alice to Bob."

### T9.6 Old host reconnects as regular player
- **Setup:** Continues T9.5. Alice reopens the URL with her old token.
- **Expected:** Alice joins as a regular player. No host badge. Bob remains host.

### T9.7 Host mid-game kick
- **Setup:** Alice is host. Bob is playing but being unresponsive.
- **Steps:** Alice clicks "Kick Bob." Confirm dialog "This will end Bob's participation. Continue?" Alice confirms.
- **Expected:** Bob's hand + bank + items all move to discard. Bob's seat removed. Game continues.

### T9.8 Kick last-but-one player triggers reset
- **Setup:** 2 players remaining (Alice + Bob). Alice kicks Bob.
- **Expected:** Only 1 player left → auto Full Reset. Phase → lobby.

### T9.9 Admin asset upload
- **Setup:** Host navigates to `/admin?host_token=...`.
- **Steps:** Uploads a PNG for Butterbeer.
- **Expected:** Image stored in Supabase Storage `card_art/`. `cards.art_asset_url` updated. All players see Butterbeer with the image in their UI within a few seconds (realtime update).

### T9.10 Admin deck verification panel
- **Setup:** Fresh seed.
- **Expected:** Panel shows all 18 assertions (total, per-category) as green checkmarks. Artificially break one (e.g. delete a Geminio), see it turn red with expected vs actual.

### T9.11 Settings change mid-game
- **Setup:** Game in progress with default settings.
- **Steps:** Host changes `protego_chain_rule` to `latest_protego_wins_all_for_that_target`. A new Protego-eligible spell is cast and a chain starts.
- **Expected:** New chain uses the new rule. Any frame already in-flight before the change uses the old rule (settings are read at frame-creation).

### T9.12 New Game after win
- **Setup:** Game finished, Alice wins.
- **Steps:** Any player clicks "New Game."
- **Expected:** Reset Lobby semantics. Phase → character_select. Players keep their seats, names, tokens.

### T9.13 Mobile layout readable
- **Setup:** Open URL on a phone browser (or Chrome DevTools mobile viewport).
- **Expected:** Layout doesn't break. Cards are readable (may require pinch-zoom for items). Hand is tappable. Modals are full-screen and touch-friendly.

### T9.14 Opponent bank modal inspection
- **Setup:** 3-player game in progress. Bob has 8 cards in his bank. Alice (viewing) sees the compressed strip showing 5 cards + "+3 more."
- **Steps:** Alice clicks Bob's bank strip.
- **Expected:** Modal "Bob's Bank" opens with all 8 cards at full fidelity. Running total visible. Locked spells show LOCKED watermark. ESC closes.

### T9.15 Opponent column modal inspection
- **Setup:** Bob has a complete yellow column (Omnioculars + Remembrall + Sneakoscope). Alice sees the compressed thumbnail.
- **Steps:** Alice clicks the yellow column thumbnail.
- **Expected:** Modal "Bob's yellow column (3/3)" opens with all 3 cards visible full-face. Complete badge visible.

### T9.16 Discard browser
- **Setup:** Discard has 15 cards from various turns.
- **Steps:** Any player clicks the discard pile (top card shown face-up).
- **Expected:** Modal opens with scrollable grid of every discarded card, newest first, full-face. Read-only (no actions).

### T9.17 Layout adapts to player count
- **Setup:** Start a 2-player game, then a 3-player, 4-player, 5-player separately (or reset between).
- **Expected:** Each layout renders per the spec. No overlap, no off-screen elements. 5-player layout fits on a 1280×720 viewport without scroll.

### T9.18 Opponent hand never shows individual cards
- **Setup:** Inspect page DOM for any opponent's hand area.
- **Expected:** Only a card-back icon + count is rendered. No `card_id` values in the rendered DOM for any opponent's hand.

### T9.19 Banked spell cannot be mistaken for castable
- **Setup:** Alice banks a Protego. Her Bank now contains the Protego with LOCKED watermark.
- **Expected:** Watermark clearly visible at table-glance size. Clicking on it in the bank doesn't offer "Cast Spell." Tooltip: "Banked spells are locked as cash."

### T9.20 Color-blind-safe completion indicator
- **Setup:** Alice has a complete brown column.
- **Expected:** Column displays BOTH gold border AND "COMPLETE" text badge AND 2/2 counter. Remove the CSS color → a monochrome user can still identify complete sets via text.

---

## End-to-end integration tests

### E2E.1 Full game, 3 players, no spells
- **Setup:** Bot-fill 2 bots. Impersonate each to play out a game where only items and points are played. End the game with a 3-set win.
- **Expected:** Game completes without errors. Log is coherent. Winner banner fires.

### E2E.2 Full game with Protego chain
- **Setup:** Bot-fill 3 bots. Manually drive a scenario with an Accio → Protego → Protego → Protego chain. Verify correct resolution.

### E2E.3 Full game with Petrificus + Obliviate
- **Setup:** 4 players. Trigger Petrificus on Hermione, verify 3 plays. Then Obliviate her complete set. Verify win conditions track correctly.

### E2E.4 Full game ending via payment-completing-set
- **Setup:** Force a state where an Accio payment provides the caster's 3rd complete set.
- **Expected:** Win fires AFTER payment queue drains, not mid-payment.

### E2E.5 Reconnect during reaction
- **Setup:** Alice casts Stupefy on Bob. Bob refreshes his browser.
- **Expected:** Bob's reconnect restores the reaction modal exactly as it was.

### E2E.6 Reconnect during payment
- **Setup:** Bob is mid-payment. Refreshes.
- **Expected:** Payment modal restored with prior selections.

### E2E.7 Hand-size limit with Geminio chain
- **Setup:** Hermione has 7 cards. She plays Geminio twice in one turn (4 plays = ok). Hand now 11. Plays Geminio 3rd time? No — 3 plays limit on Geminio (each costs 1 play; 4 total allowed). So end-of-turn hand is 11 - 4 + drawn.
- **Expected:** At end of turn, discard picker requires discard to 7. Exact behavior matches T3.11.

---

## What NOT to automate

These require human playtesting, not automated assertions:
- Card animations feel good
- Flow timing isn't annoying
- Color palette is readable
- Tooltips are understandable
- Drag-and-drop feels responsive

Playtest with 3+ real humans before declaring v1 done.

---

## Acceptance gate

Do not declare any slice complete until every test in that slice's section passes. If a test fails, fix the bug BEFORE moving to the next slice. A failing test in slice N will usually cascade into slice N+1 and make later debugging harder.

After Slice 9, run all E2E tests. After all pass, playtest manually with real humans. Then ship.
