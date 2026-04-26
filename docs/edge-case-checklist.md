# Edge Case Checklist — manual playtest

Use this as a tick-list during playtesting to verify all the fiddly rules work correctly. These are the scenarios that cause rules disputes at the physical table. If any fails, it's a bug, not a "house rule we'll figure out."

Run each scenario with real or bot-filled players. Tick ✅ when observed working; flag bugs for fix.

---

## A. Hand size & discard

- [ ] **A1.** Player ends turn with exactly 7 cards → advances normally, no picker.
- [ ] **A2.** Player ends turn with 8 cards → discard picker requires exactly 1 selection before confirm enabled.
- [ ] **A3.** Player ends turn with 10 cards → picker requires exactly 3.
- [ ] **A4.** Player tries to confirm picker with fewer than required → confirm stays disabled.
- [ ] **A5.** Player tries to confirm with MORE than required → confirm stays disabled.
- [ ] **A6.** Discarded cards are visible in the discard pile afterward (any player can browse).
- [ ] **A7.** Turn advances correctly to next left seat after discard confirms.
- [ ] **A8.** Mid-turn, hand exceeds 7 due to Geminio → no picker yet (only end-of-turn).
- [ ] **A9.** Petrificus Totalus removal discards don't affect hand size check — removal is from bank only.

## B. Empty bank & payment

- [ ] **B1.** I owe 5, my bank is empty AND my item area is empty → no modal shown. Log: "nothing to pay; debt forgiven." Turn continues.
- [ ] **B2.** I owe 5, I have a 1pt card in bank and nothing else → modal opens, card pre-selected, "Paying everything — 4 forgiven." Only confirm.
- [ ] **B3.** I owe 5, I have a 3pt + 4pt in bank → modal opens, I can pick 3+4 = 7 (overpay 2) or 4 alone (overpay not possible, short), etc.
- [ ] **B4.** I owe 5, I pick a 5pt card only → exact payment, no overpayment warning.
- [ ] **B5.** I owe 5, my only card is a 10pt → modal opens, 10pt must be selected, warning "overpay by 5 (no change)."
- [ ] **B6.** I have only every-color wilds (cash 0) in items, bank empty → total available is 0 → modal skipped, "nothing to pay."
- [ ] **B7.** Payment of items to recipient: if recipient has a non-complete column of same color, paid item APPENDS there. If complete column, NEW column created.
- [ ] **B8.** Payment of a wild preserves the wild's current color assignment.
- [ ] **B9.** Payment of a banked spell lands in recipient's bank, still locked (can't be cast).

## C. Targeting — Harry's protection

- [ ] **C1.** Harry protects red. Levicorpus on Harry → red items dimmed with "Harry-protected" tooltip. Non-red items clickable.
- [ ] **C2.** Harry protects red. Obliviate on Harry → complete red set dimmed. Other complete sets clickable.
- [ ] **C3.** Harry protects red. Wingardium Leviosa on Harry → red items dimmed.
- [ ] **C4.** Harry protects red. A wild currently set to red → treated as red, dimmed.
- [ ] **C5.** Harry's protection does NOT apply to Accio (rule: Accio targets caster's items, not victim's).
- [ ] **C6.** Harry protects red. If petrified, red items become targetable (protection lifted).
- [ ] **C7.** Harry's protection does NOT protect his items from being USED TO PAY (Harry choosing to pay with red items is fine; rule is about opponents targeting).
- [ ] **C8.** Harry can change protected color only at character select (default house rule).

## D. Draco's override

- [ ] **D1.** Draco casts Levicorpus on opponent with only complete-set items → items CLICKABLE.
- [ ] **D2.** Draco casts Confundo; at Step 1 (my item), Draco CANNOT pick from his own complete set (the rule is about taking opponents' complete-set items, not giving up his own).
- [ ] **D3.** Draco casts Confundo; at Step 3 (opponent's item), complete-set items ARE selectable.
- [ ] **D4.** Draco's override does not apply if Draco is petrified.
- [ ] **D5.** Harry-protected items override Draco — Draco CANNOT take Harry-protected items even via override.
- [ ] **D6.** Obliviate is unaffected by Draco (already targets complete sets).

## E. Wild card mechanics

- [ ] **E1.** Two-color wild plays with color-picker, color locks on play.
- [ ] **E2.** Wild recolor during own turn is free (doesn't increment plays_this_turn).
- [ ] **E3.** Cannot recolor a wild during another player's turn.
- [ ] **E4.** Cannot recolor a non-wild item (non-wilds are locked by color).
- [ ] **E5.** Column with 3 every-color wilds in dark-blue (set size 2): engine BLOCKS placing the third wild (exceeds set_size regardless of type).
- [ ] **E6.** Column with 2 every-color wilds in dark-blue (hits set_size): NOT marked COMPLETE.
- [ ] **E7.** Column with 1 Felix Felicis + 1 every-color wild in dark-blue: marked COMPLETE (has at least one non-every-color).
- [ ] **E8.** Every-color wilds cannot pay debt (cash 0 dimmed in payment modal).
- [ ] **E9.** Two-color wild cash value is card-fixed (not dependent on current color assignment).
- [ ] **E10.** Wild is taken via Levicorpus → keeps its current color in recipient's area. Recipient can recolor next turn.

## F. Character ability conflicts

- [ ] **F1.** Hermione starts turn with hand empty → draws 5 (not 3, not 4).
- [ ] **F2.** Petrified Hermione: `plays_allowed_this_turn = 3` at turn start.
- [ ] **F3.** Hermione removes Petrificus mid-turn (during ACTION): `plays_allowed_this_turn` immediately jumps to 4, plays_this_turn preserved.
- [ ] **F4.** Luna starts turn with hand empty → draws 5.
- [ ] **F5.** Luna starts turn with hand non-empty, not petrified → draws 3.
- [ ] **F6.** Petrified Luna → draws 2.
- [ ] **F7.** Cedric's turn, discard empty → auto-draw 2 from deck with toast "Discard empty, drew from deck." No modal offering discard.
- [ ] **F8.** Cedric's turn, discard non-empty → modal offers "Deck" or "Discard (Top)" as options. First card from source choice, remaining from deck to meet draw count.
- [ ] **F9.** Petrified Cedric → no option to draw from discard. Auto-draws 2 from deck.
- [ ] **F10.** Multiple players petrified simultaneously — each handled independently, no interference.

## G. Spell cancellation

- [ ] **G1.** Alice clicks Cast Spell on Confundo → play consumed immediately. Targeting flow begins.
- [ ] **G2.** Alice cancels mid-targeting (any step) → spell to discard, play STAYS consumed. Log notes "cancelled Confundo (spell discarded, play spent)."
- [ ] **G3.** Alice casts Levicorpus, selects opponent, selects item, confirms → spell resolves normally.
- [ ] **G4.** Alice casts Confundo but has NO non-complete items of her own → spell grayed in hand, cannot start targeting.
- [ ] **G5.** Alice casts Obliviate but no opponent has complete sets → spell grayed in hand.
- [ ] **G6.** Alice casts Petrificus Totalus on an already-petrified target → target not selectable (dimmed).
- [ ] **G7.** Alice casts Protego outside a reaction → menu offers only "Play to Bank" or "Cancel" (no "Cast Spell" option).

## H. Protego chain mechanics

- [ ] **H1.** Single Protego: target blocks, caster has no Protego → auto-resolve. Both spells to discard.
- [ ] **H2.** Chain depth 2 (target Protego, caster counter): caster's Protego cancels target's; original spell resolves.
- [ ] **H3.** Chain depth 3 (target, caster, target): target's second cancels caster's; original spell blocked.
- [ ] **H4.** Chain depth 4: original spell resolves.
- [ ] **H5.** Chain depth 5: original spell blocked.
- [ ] **H6.** (Odd depth = blocked, even depth = resolves. Verify either depth pattern works.)
- [ ] **H7.** Multi-target spell (Alohomora on 3 opponents): each opponent's reaction happens in sequence, leftward from caster.
- [ ] **H8.** Alohomora, target A has no Protego (auto-take-hit with 2s notification), target B plays Protego, target C has no Protego.
- [ ] **H9.** During Accio chain, the caster's per-target counter-Protego only applies to that specific target, not others.
- [ ] **H10.** During reaction decision (target deciding), OTHER bystander players cannot act (their cards are non-interactive).
- [ ] **H11.** During reaction decision, casters cannot cancel their spell anymore (spell is on the stack, binding).

## I. Win detection timing

- [ ] **I1.** I play a card that completes my 3rd set (no pending stack, no payment queue) → win fires immediately.
- [ ] **I2.** I receive item-payment that completes my 3rd set → win fires AFTER payment_queue fully drains (all debtors paid).
- [ ] **I3.** Alice has 2 complete sets. She casts Obliviate on Bob's complete set. Bob Protegos (depth 1). Alice has no Protego → spell blocked. Alice stays at 2 complete sets. NO false win fired mid-chain.
- [ ] **I4.** Alice has 2 complete sets. She casts Obliviate on Bob's set. Bob Protegos, Alice counter-Protegos (depth 2) → spell resolves. After resolution, Alice has 3 complete sets. Win fires.
- [ ] **I5.** Alice has 3 complete sets. Bob steals one via Levicorpus → Alice now has 2, win is REVOKED (phase back to in_game, winner_player_id cleared).
- [ ] **I6.** Multi-payment Accio: Bob's payment completes Alice's 3rd set; Chintan and Dave still owe. All payments drain FIRST, then win fires.
- [ ] **I7.** All-every-color-wild "complete" column does NOT count toward win (E6).

## J. Deck / discard exhaustion

- [ ] **J1.** Deck has 3 cards, player draws 2 at turn start → deck has 1.
- [ ] **J2.** Deck has 1 card, player draws 2 → draws 1 from deck, reshuffles discard into deck, draws 1 more. Hand correct.
- [ ] **J3.** Deck empty, discard empty → player draws 0 at turn start. No error. Turn proceeds. Player can still play from hand.
- [ ] **J4.** Reshuffle excludes cards currently on pending_stack or payment_queue (they're "in-flight").
- [ ] **J5.** Geminio triggers same reshuffle logic mid-turn.
- [ ] **J6.** Reparo with empty discard → Reparo grayed in hand with tooltip "Discard pile is empty."

## K. Host controls

- [ ] **K1.** Host clicks Pause → everyone sees PAUSED overlay. No RPCs accepted (except resume).
- [ ] **K2.** Resume restores phase = previous_phase with all state intact.
- [ ] **K3.** During a Protego decision by AFK player, host sees "Force Pass" button. Click → target decision = pass.
- [ ] **K4.** During a payment by AFK debtor, host sees "Force Auto-Pay" button. Click → server auto-pays with minimum overpayment algorithm.
- [ ] **K5.** During AFK active turn, host sees "Force End Turn" button. Click → hand discards conservatively to 7, turn advances.
- [ ] **K6.** Host disconnects for 35 seconds → auto-transfer to earliest-joined connected player. Log entry.
- [ ] **K7.** Old host reconnects → joins as regular player, no host badge.
- [ ] **K8.** Host mid-game kick of a player: hand + bank + items all to discard. Seat removed. Game continues if ≥ 2 players remain.
- [ ] **K9.** Host kick triggers auto Full Reset if < 2 players remain.
- [ ] **K10.** Full Reset invalidates all localStorage tokens. Players rejoin as fresh users.

## L. Reconnection

- [ ] **L1.** Active player refreshes tab mid-turn → reconnects, UI restores to exact state (same plays_this_turn, same hand, same turn_player_id).
- [ ] **L2.** Target refreshes during reaction decision → reaction modal reappears.
- [ ] **L3.** Debtor refreshes during payment → payment modal reappears with prior selections if any.
- [ ] **L4.** Bystander refreshes → subscribes to public channel, sees current game state.
- [ ] **L5.** Token invalid (after Full Reset) → name-entry screen on load.

## M. Admin / settings

- [ ] **M1.** Admin page accessible only with valid `host_token` URL param.
- [ ] **M2.** Non-host cannot access `/admin` (returns 403 or redirect).
- [ ] **M3.** Upload PNG to a card → Supabase Storage receives it, card URL updates, all clients see it within 2s.
- [ ] **M4.** Edit card `rules_text` field → saves, all clients see updated text.
- [ ] **M5.** Deck verification panel shows 18+ assertions with green/red status.
- [ ] **M6.** Settings toggle `reparo_spell_destination` to `cast_for_effect` → next Reparo of a spell offers cast option.
- [ ] **M7.** Settings toggle `protego_chain_rule` to `latest_protego_wins_all_for_that_target` → multi-target Protegos behave per new rule.

## N. Accessibility / usability

- [ ] **N1.** Color-blind-friendly: complete-set indicator is NOT just "gold border" — has a text badge "COMPLETE" so the state is readable without color perception.
- [ ] **N2.** Tooltips on every dimmed action explain why it's dimmed (Harry-protected / complete-set / Draco only / cash 0 / etc.).
- [ ] **N3.** Keyboard navigation: tab through hand, enter to open menu, arrows to navigate menu, enter to select.
- [ ] **N4.** Mobile: card sizes tap-friendly (>44pt targets).
- [ ] **N5.** Log is readable without jargon for new players.

## O. Performance

- [ ] **O1.** 5-player game with full item areas doesn't lag (initial load < 2s, RPC responses < 500ms).
- [ ] **O2.** Realtime updates propagate within 1s across tabs.
- [ ] **O3.** No memory leaks — play a full 30-minute game, check browser memory hasn't ballooned.

---

## Final sign-off tests

Before declaring the app ready to play with friends:

- [ ] **Z1.** Completed a full 3-player game start to finish with no rule disputes.
- [ ] **Z2.** Completed a full 5-player game start to finish.
- [ ] **Z3.** Game recovers correctly from a player force-quitting and reconnecting.
- [ ] **Z4.** Game recovers correctly from host dropping and transferring.
- [ ] **Z5.** All 111 cards have art uploaded OR acceptable styled placeholders.
- [ ] **Z6.** Friend group has played at least once and enjoyed it.

---

## Known design choices (not bugs)

- There are NO countdowns on player decisions. If someone AFKs, host uses Force Resolve. This is intentional.
- There is NO in-app chat. Use voice/external chat.
- There is NO identity persistence across sessions. Each session starts fresh on Full Reset.
- Clicking Cast Spell is BINDING — play is consumed even if you cancel during targeting. This is intentional to simplify state.
- No change is given on overpayment — if you pay with a 5 for a 3-pt debt, you lose 2. This is the rulebook's rule.
- Items can be paid as debt at their cash value. This was a commonly-missed rule in early versions.
