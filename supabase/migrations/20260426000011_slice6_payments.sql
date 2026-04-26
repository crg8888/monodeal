-- Slice 6: debt payments — Stupefy, Alohomora, Accio + pay_debt.
-- Still no Protego (Slice 7). cast_spell extended to enqueue payment debts.
-- payment_queue resolves leftward from caster (increasing seat_index, wrapping).
--
-- Spec (lines 466-474):
--   - No change. Overpayment lost.
--   - If total available < debt: debtor must pay everything.
--   - If total available = 0: forgiven silently.
--   - Bank cards → recipient bank. Items → recipient item_area (preserve color).

-- ============================================================================
-- _player_available_cash — bank + items, EXCLUDING every-color wilds (cash 0,
-- can't be used to pay).
-- ============================================================================

create or replace function public._player_available_cash(p_player_id uuid)
returns int
language plpgsql security definer set search_path = public stable
as $$
declare
  v_bank uuid[];
  v_area jsonb;
  v_total int := 0;
  v_card_ids uuid[];
  v_id uuid;
  v_cash int;
  v_cat text;
begin
  select bank, item_area into v_bank, v_area from players where id = p_player_id;
  -- Bank cards (all carry cash).
  for v_id in select unnest(v_bank) loop
    select coalesce(cash_value, 0) into v_cash from cards where id = v_id;
    v_total := v_total + v_cash;
  end loop;
  -- Item cards (excluding every-color wilds).
  for v_id in
    select (cc->>'card_id')::uuid
    from jsonb_array_elements(coalesce(v_area, '[]'::jsonb)) col,
         jsonb_array_elements(col->'cards') cc
  loop
    select category, coalesce(cash_value, 0) into v_cat, v_cash from cards where id = v_id;
    if v_cat != 'wild_item_any_color' then
      v_total := v_total + v_cash;
    end if;
  end loop;
  return v_total;
end;
$$;
revoke all on function public._player_available_cash(uuid) from public;

-- ============================================================================
-- _enqueue_debt — append debts in leftward turn-order from caster.
-- ============================================================================

create or replace function public._enqueue_debts(
  p_caster_id uuid, p_amounts jsonb
) returns void
language plpgsql security definer set search_path = public
as $$
-- p_amounts: [{ debtor_id, amount }, ...]. Status is auto-set: first non-zero
-- becomes 'active', others 'pending', or 'forgiven' if 0.
declare
  v_caster_seat int;
  v_ordered jsonb;
  v_debt jsonb;
  v_amount int;
  v_avail int;
  v_status text;
  v_first_active_set bool := false;
begin
  select seat_index into v_caster_seat from players where id = p_caster_id;

  -- Order debts leftward from caster: opponents sorted so seats > caster come
  -- first, then wrap to those <= caster (excluding caster).
  with by_seat as (
    select (d->>'debtor_id')::uuid as debtor_id,
           (d->>'amount')::int as amount,
           p.seat_index
    from jsonb_array_elements(p_amounts) d
    join players p on p.id = (d->>'debtor_id')::uuid
  )
  select coalesce(jsonb_agg(jsonb_build_object('debtor_id', debtor_id, 'amount', amount)
           order by case when seat_index > v_caster_seat then 0 else 1 end, seat_index),
         '[]'::jsonb)
    into v_ordered
    from by_seat;

  for v_debt in select * from jsonb_array_elements(v_ordered) loop
    v_amount := (v_debt->>'amount')::int;
    v_avail := _player_available_cash((v_debt->>'debtor_id')::uuid);
    if v_avail = 0 or v_amount = 0 then
      v_status := 'forgiven';
    elsif not v_first_active_set then
      v_status := 'active';
      v_first_active_set := true;
    else
      v_status := 'pending';
    end if;
    update game_state set
      payment_queue = payment_queue || jsonb_build_array(jsonb_build_object(
        'debtor_id', v_debt->>'debtor_id',
        'recipient_id', p_caster_id,
        'amount', v_amount,
        'status', v_status
      )) where id = 1;
    if v_status = 'forgiven' then
      perform _append_log('payment',
        (select name from players where id = (v_debt->>'debtor_id')::uuid)
        || ' forgiven (nothing to pay)');
    end if;
  end loop;
end;
$$;
revoke all on function public._enqueue_debts(uuid, jsonb) from public;

-- ============================================================================
-- _advance_payment_queue — when current active debt completes, mark next
-- 'pending' debt as 'active'. Also auto-forgives any 'pending' whose debtor
-- now has 0 available (could happen mid-queue if their bank was emptied).
-- Returns true if queue is fully drained (all completed/forgiven).
-- ============================================================================

create or replace function public._advance_payment_queue()
returns bool
language plpgsql security definer set search_path = public
as $$
declare
  v_queue jsonb;
  v_new_queue jsonb := '[]'::jsonb;
  v_e jsonb;
  v_status text;
  v_active_set bool := false;
  v_avail int;
  v_drained bool := true;
begin
  select payment_queue into v_queue from game_state where id = 1;
  for v_e in select * from jsonb_array_elements(v_queue) loop
    v_status := v_e->>'status';
    if v_status in ('completed','forgiven') then
      v_new_queue := v_new_queue || v_e;
    elsif v_status = 'active' then
      v_new_queue := v_new_queue || v_e;
      v_active_set := true;
      v_drained := false;
    elsif v_status = 'pending' then
      v_avail := _player_available_cash((v_e->>'debtor_id')::uuid);
      if v_avail = 0 then
        v_new_queue := v_new_queue || jsonb_set(v_e, '{status}', '"forgiven"');
      elsif not v_active_set then
        v_new_queue := v_new_queue || jsonb_set(v_e, '{status}', '"active"');
        v_active_set := true;
        v_drained := false;
      else
        v_new_queue := v_new_queue || v_e;
        v_drained := false;
      end if;
    else
      v_new_queue := v_new_queue || v_e;
    end if;
  end loop;
  update game_state set payment_queue = v_new_queue where id = 1;
  return v_drained;
end;
$$;
revoke all on function public._advance_payment_queue() from public;

-- ============================================================================
-- pay_debt — debtor pays the active debt with selected cards.
-- Selected cards must be in their bank or item_area. If selected_total < amount
-- AND debtor still has unpicked cash, reject. Empty queue triggers win check
-- on each recipient.
-- ============================================================================

create or replace function public.pay_debt(
  p_actor_id uuid, p_actor_token uuid, p_card_ids uuid[]
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_queue jsonb;
  v_active_idx int := -1;
  v_active jsonb;
  v_amount int;
  v_recipient uuid;
  v_total_paid int := 0;
  v_avail int;
  v_id uuid;
  v_cat text;
  v_cash int;
  v_color text;
  v_assigned text;
  v_drained bool;
  v_recipients_to_check uuid[];
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select payment_queue into v_queue from game_state where id = 1;
  -- Find current active for this actor.
  for v_active_idx in 0 .. coalesce(jsonb_array_length(v_queue), 0) - 1 loop
    v_active := v_queue->v_active_idx;
    if (v_active->>'debtor_id')::uuid = p_actor_id and (v_active->>'status') = 'active' then
      exit;
    end if;
    v_active_idx := -1;
  end loop;
  if v_active_idx < 0 then raise exception 'no_active_debt'; end if;

  v_amount := (v_active->>'amount')::int;
  v_recipient := (v_active->>'recipient_id')::uuid;
  v_avail := _player_available_cash(p_actor_id);

  -- Validate every selected card is in bank or items, and compute total.
  foreach v_id in array p_card_ids loop
    if v_id = any((select bank from players where id = p_actor_id)) then
      select coalesce(cash_value, 0) into v_cash from cards where id = v_id;
      v_total_paid := v_total_paid + v_cash;
    elsif _column_idx_of(p_actor_id, v_id) >= 0 then
      select category, coalesce(cash_value, 0) into v_cat, v_cash from cards where id = v_id;
      if v_cat = 'wild_item_any_color' then raise exception 'cannot_pay_with_any_wild'; end if;
      v_total_paid := v_total_paid + v_cash;
    else
      raise exception 'card_not_payable' using detail = v_id::text;
    end if;
  end loop;

  -- If debtor underpays, must include EVERYTHING they have.
  if v_total_paid < v_amount and v_total_paid < v_avail then
    raise exception 'must_pay_all_available' using detail = format('paid=%s avail=%s amount=%s',
      v_total_paid, v_avail, v_amount);
  end if;

  -- Move cards.
  foreach v_id in array p_card_ids loop
    if v_id = any((select bank from players where id = p_actor_id)) then
      update players set bank = array_remove(bank, v_id) where id = p_actor_id;
      update players set bank = bank || v_id where id = v_recipient;
    else
      -- Item: take from column, add to recipient with same assigned_color.
      select item_area->v_color->>'color' into v_color from players where id = p_actor_id;
      -- get assigned_color
      select cc->>'assigned_color' into v_assigned
        from players p, jsonb_array_elements(p.item_area) col,
             jsonb_array_elements(col->'cards') cc
        where p.id = p_actor_id and (cc->>'card_id')::uuid = v_id;
      perform _take_item_from_column(p_actor_id, v_id);
      perform _add_item_to_player(v_recipient, v_id, coalesce(v_assigned, v_color));
    end if;
  end loop;

  -- Mark this debt completed.
  v_queue := jsonb_set(v_queue, array[v_active_idx::text, 'status'],
                      to_jsonb(case when v_total_paid >= v_amount then 'completed' else 'completed_partial' end));
  update game_state set payment_queue = v_queue where id = 1;

  perform _append_log('payment',
    (select name from players where id = p_actor_id) || ' paid ' || v_total_paid ||
    ' to ' || (select name from players where id = v_recipient) ||
    case when v_total_paid < v_amount then ' (partial — ' || v_amount - v_total_paid || ' forgiven)' else '' end);

  -- Advance.
  v_drained := _advance_payment_queue();

  -- Win check on every recipient + caster (when queue drains).
  if v_drained then
    select array_agg(distinct (e->>'recipient_id')::uuid)
      into v_recipients_to_check
      from jsonb_array_elements(v_queue) e;
    if v_recipients_to_check is not null then
      foreach v_id in array v_recipients_to_check loop
        perform _check_win(v_id);
      end loop;
    end if;
    -- Empty queue once drained.
    update game_state set payment_queue = '[]'::jsonb where id = 1;
  end if;

  update game_state set version = version + 1, updated_at = now() where id = 1;
  return jsonb_build_object('ok', true, 'drained', v_drained);
end;
$$;
revoke all on function public.pay_debt(uuid, uuid, uuid[]) from public;
grant execute on function public.pay_debt(uuid, uuid, uuid[]) to anon, authenticated;

-- ============================================================================
-- Extend cast_spell for stupefy, alohomora, accio_*. Replaces the prior version.
-- ============================================================================

create or replace function public.cast_spell(
  p_actor_id uuid, p_actor_token uuid, p_card_id uuid,
  p_params jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_drawn bool;
  v_plays int;
  v_max_plays int;
  v_in_hand bool;
  v_category text;
  v_effect text;
  v_settings jsonb;
  v_target_id uuid;
  v_target_card_id uuid;
  v_my_card_id uuid;
  v_target_idx int;
  v_my_idx int;
  v_target_color text;
  v_my_color text;
  v_won bool := false;
  v_reparo_card_id uuid;
  v_reparo_cat text;
  v_reparo_color text;
  v_dest_color_param text;
  v_result jsonb := '{}'::jsonb;
  v_amounts jsonb := '[]'::jsonb;
  v_opp record;
  v_amount int;
  v_chosen_color text;
  v_count int;
  v_caster_count int;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id, has_drawn_this_turn,
         plays_this_turn, plays_allowed_this_turn, settings
    into v_phase, v_turn_id, v_drawn, v_plays, v_max_plays, v_settings
    from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;
  if not v_drawn then raise exception 'must_draw_first'; end if;
  if v_plays >= v_max_plays then raise exception 'no_plays_left'; end if;

  select category, spell_effect into v_category, v_effect from cards where id = p_card_id;
  if v_category != 'spell' then raise exception 'not_a_spell'; end if;
  if v_effect = 'protego' then raise exception 'protego_is_reactive'; end if;

  select p_card_id = any(hand) into v_in_hand from players where id = p_actor_id;
  if not v_in_hand then raise exception 'card_not_in_hand'; end if;

  update players set hand = array_remove(hand, p_card_id) where id = p_actor_id;

  -- ===========================================================================
  -- GEMINIO
  -- ===========================================================================
  if v_effect = 'geminio' then
    perform _draw_cards(p_actor_id, 2);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- REPARO
  -- ===========================================================================
  elsif v_effect = 'reparo' then
    v_reparo_card_id := (p_params->>'from_discard_card_id')::uuid;
    if v_reparo_card_id is null then raise exception 'reparo_pick_required'; end if;
    if not (v_reparo_card_id = any(
      (select discard_pile from game_state where id = 1)
    )) then raise exception 'card_not_in_discard'; end if;

    select category, colors[1] into v_reparo_cat, v_reparo_color
      from cards where id = v_reparo_card_id;
    update game_state set discard_pile = array_remove(discard_pile, v_reparo_card_id) where id = 1;

    if v_reparo_cat = 'item' then
      perform _add_item_to_player(p_actor_id, v_reparo_card_id, v_reparo_color);
    elsif v_reparo_cat in ('wild_item_two_color','wild_item_any_color') then
      v_dest_color_param := p_params->>'dest_color';
      if v_dest_color_param is null then raise exception 'wild_color_required'; end if;
      perform _add_item_to_player(p_actor_id, v_reparo_card_id, v_dest_color_param);
    elsif v_reparo_cat = 'point' then
      update players set bank = bank || v_reparo_card_id where id = p_actor_id;
    elsif v_reparo_cat = 'spell' then
      if exists(select 1 from cards where id = v_reparo_card_id and spell_effect = 'petrificus_totalus') then
        update players set bank = bank || v_reparo_card_id where id = p_actor_id;
      elsif (v_settings->>'reparo_spell_destination') = 'bank_as_points' then
        update players set bank = bank || v_reparo_card_id where id = p_actor_id;
      else
        update players set hand = hand || v_reparo_card_id where id = p_actor_id;
      end if;
    end if;
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- LEVICORPUS
  -- ===========================================================================
  elsif v_effect = 'levicorpus' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    v_target_card_id := (p_params->>'target_card_id')::uuid;
    if v_target_id is null or v_target_card_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    v_target_idx := _column_idx_of(v_target_id, v_target_card_id);
    if v_target_idx < 0 then raise exception 'item_not_found'; end if;
    select item_area->v_target_idx->>'color' into v_target_color from players where id = v_target_id;
    if _is_harry_protected(v_target_id, v_target_color) then raise exception 'harry_protected'; end if;
    if _column_is_complete(v_target_id, v_target_idx) and not _is_draco_active(p_actor_id) then
      raise exception 'cannot_take_from_complete';
    end if;
    v_result := _take_item_from_column(v_target_id, v_target_card_id);
    perform _add_item_to_player(p_actor_id, v_target_card_id, v_result->>'assigned_color');
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- WINGARDIUM
  -- ===========================================================================
  elsif v_effect = 'wingardium_leviosa' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    v_target_card_id := (p_params->>'target_card_id')::uuid;
    if v_target_id is null or v_target_card_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    v_target_idx := _column_idx_of(v_target_id, v_target_card_id);
    if v_target_idx < 0 then raise exception 'item_not_found'; end if;
    select item_area->v_target_idx->>'color' into v_target_color from players where id = v_target_id;
    if _is_harry_protected(v_target_id, v_target_color) then raise exception 'harry_protected'; end if;
    if _column_is_complete(v_target_id, v_target_idx) and not _is_draco_active(p_actor_id) then
      raise exception 'cannot_take_from_complete';
    end if;
    perform _take_item_from_column(v_target_id, v_target_card_id);
    update game_state set discard_pile = discard_pile || v_target_card_id || p_card_id where id = 1;

  -- ===========================================================================
  -- CONFUNDO
  -- ===========================================================================
  elsif v_effect = 'confundo' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    v_target_card_id := (p_params->>'target_card_id')::uuid;
    v_my_card_id := (p_params->>'my_card_id')::uuid;
    if v_target_id is null or v_target_card_id is null or v_my_card_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    v_target_idx := _column_idx_of(v_target_id, v_target_card_id);
    v_my_idx := _column_idx_of(p_actor_id, v_my_card_id);
    if v_target_idx < 0 or v_my_idx < 0 then raise exception 'item_not_found'; end if;
    select item_area->v_target_idx->>'color' into v_target_color from players where id = v_target_id;
    select item_area->v_my_idx->>'color' into v_my_color from players where id = p_actor_id;
    if _is_harry_protected(v_target_id, v_target_color) then raise exception 'harry_protected'; end if;
    if _column_is_complete(v_target_id, v_target_idx) and not _is_draco_active(p_actor_id) then
      raise exception 'cannot_take_from_complete_target';
    end if;
    if _column_is_complete(p_actor_id, v_my_idx) then raise exception 'cannot_take_from_complete_self'; end if;
    v_result := _take_item_from_column(v_target_id, v_target_card_id);
    v_target_color := v_result->>'assigned_color';
    v_result := _take_item_from_column(p_actor_id, v_my_card_id);
    v_my_color := v_result->>'assigned_color';
    perform _add_item_to_player(p_actor_id, v_target_card_id, v_target_color);
    perform _add_item_to_player(v_target_id, v_my_card_id, v_my_color);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- OBLIVIATE
  -- ===========================================================================
  elsif v_effect = 'obliviate' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    v_target_color := p_params->>'target_color';
    if v_target_id is null or v_target_color is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    if _is_harry_protected(v_target_id, v_target_color) then raise exception 'harry_protected'; end if;
    declare v_complete_idx int := -1; v_n int; v_cards_in jsonb;
    begin
      select item_area into v_result from players where id = v_target_id;
      for v_target_idx in 0 .. coalesce(jsonb_array_length(v_result), 0) - 1 loop
        if (v_result->v_target_idx->>'color') = v_target_color
           and _column_is_complete(v_target_id, v_target_idx) then
          v_complete_idx := v_target_idx; exit;
        end if;
      end loop;
      if v_complete_idx < 0 then raise exception 'no_complete_column' using detail = v_target_color; end if;
      v_cards_in := v_result->v_complete_idx->'cards';
      v_result := v_result - v_complete_idx;
      update players set item_area = v_result where id = v_target_id;
      v_n := jsonb_array_length(v_cards_in);
      for v_target_idx in 0 .. v_n - 1 loop
        perform _add_item_to_player(
          p_actor_id,
          (v_cards_in->v_target_idx->>'card_id')::uuid,
          v_cards_in->v_target_idx->>'assigned_color'
        );
      end loop;
    end;
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- PETRIFICUS — attaches; doesn't go to discard.
  -- ===========================================================================
  elsif v_effect = 'petrificus_totalus' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    if v_target_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    update players set petrified = true, bank = bank || p_card_id where id = v_target_id;

  -- ===========================================================================
  -- STUPEFY — 1 opponent pays 5.
  -- ===========================================================================
  elsif v_effect = 'stupefy' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    if v_target_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    v_amounts := jsonb_build_array(jsonb_build_object('debtor_id', v_target_id, 'amount', 5));
    perform _enqueue_debts(p_actor_id, v_amounts);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- ALOHOMORA — each opponent pays 2.
  -- ===========================================================================
  elsif v_effect = 'alohomora' then
    for v_opp in select id from players where id != p_actor_id loop
      v_amounts := v_amounts || jsonb_build_array(
        jsonb_build_object('debtor_id', v_opp.id, 'amount', 2)
      );
    end loop;
    perform _enqueue_debts(p_actor_id, v_amounts);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- ACCIO — caster picks color; charge from caster's count of that color.
  -- Each opponent owes the same amount.
  -- ===========================================================================
  elsif v_effect like 'accio_%' then
    v_chosen_color := p_params->>'chosen_color';
    if v_chosen_color is null then raise exception 'accio_color_required'; end if;
    -- Validate chosen_color is in spell_allowed_colors.
    if not (v_chosen_color = any(
      (select spell_allowed_colors from cards where id = p_card_id)
    )) then
      raise exception 'illegal_accio_color' using detail = v_chosen_color;
    end if;
    -- Count caster's items in that color (using assigned_color).
    select count(*)::int into v_caster_count
      from players p, jsonb_array_elements(p.item_area) col,
           jsonb_array_elements(col->'cards') cc
      where p.id = p_actor_id
        and (cc->>'assigned_color') = v_chosen_color;
    -- Look up charge from item_sets.
    declare v_chrg jsonb; v_set_size int;
    begin
      select charge_table, set_size into v_chrg, v_set_size from item_sets where color = v_chosen_color;
      if v_caster_count >= v_set_size then
        v_amount := (v_chrg->>'complete')::int;
      else
        v_amount := coalesce((v_chrg->>v_caster_count::text)::int, 0);
      end if;
    end;
    -- Each opponent owes v_amount.
    for v_opp in select id from players where id != p_actor_id loop
      v_amounts := v_amounts || jsonb_build_array(
        jsonb_build_object('debtor_id', v_opp.id, 'amount', v_amount)
      );
    end loop;
    perform _enqueue_debts(p_actor_id, v_amounts);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;
    perform _append_log('accio',
      (select name from players where id = p_actor_id) ||
      ' Accios ' || v_chosen_color || ' (charge ' || v_amount || ')');

  end if;

  update game_state set
    plays_this_turn = plays_this_turn + 1,
    version = version + 1,
    updated_at = now()
  where id = 1;
  perform _append_log('cast',
    (select name from players where id = p_actor_id) || ' cast ' || v_effect);

  v_won := _check_win(p_actor_id);
  return jsonb_build_object('ok', true, 'won', v_won);
end;
$$;
revoke all on function public.cast_spell(uuid, uuid, uuid, jsonb) from public;
grant execute on function public.cast_spell(uuid, uuid, uuid, jsonb) to anon, authenticated;
