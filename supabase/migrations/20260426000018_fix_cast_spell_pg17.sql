-- Same PG 17 strictness as fix_pay_debt_2: two `ANY((select ...))` patterns
-- inside cast_spell (Reparo discard validation + Accio color validation).
-- Replace with EXISTS subqueries.

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

  if v_effect = 'geminio' then
    perform _draw_cards(p_actor_id, 2);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  elsif v_effect = 'reparo' then
    v_reparo_card_id := (p_params->>'from_discard_card_id')::uuid;
    if v_reparo_card_id is null then raise exception 'reparo_pick_required'; end if;
    if not exists(
      select 1 from game_state where id = 1 and v_reparo_card_id = any(discard_pile)
    ) then raise exception 'card_not_in_discard'; end if;

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

  elsif v_effect = 'petrificus_totalus' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    if v_target_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    update players set petrified = true, bank = bank || p_card_id where id = v_target_id;

  elsif v_effect = 'stupefy' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    if v_target_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    v_amounts := jsonb_build_array(jsonb_build_object('debtor_id', v_target_id, 'amount', 5));
    perform _enqueue_debts(p_actor_id, v_amounts);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  elsif v_effect = 'alohomora' then
    for v_opp in select id from players where id != p_actor_id loop
      v_amounts := v_amounts || jsonb_build_array(
        jsonb_build_object('debtor_id', v_opp.id, 'amount', 2)
      );
    end loop;
    perform _enqueue_debts(p_actor_id, v_amounts);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  elsif v_effect like 'accio_%' then
    v_chosen_color := p_params->>'chosen_color';
    if v_chosen_color is null then raise exception 'accio_color_required'; end if;
    if not exists(
      select 1 from cards where id = p_card_id and v_chosen_color = any(spell_allowed_colors)
    ) then raise exception 'illegal_accio_color' using detail = v_chosen_color; end if;
    select count(*)::int into v_caster_count
      from players p, jsonb_array_elements(p.item_area) col,
           jsonb_array_elements(col->'cards') cc
      where p.id = p_actor_id
        and (cc->>'assigned_color') = v_chosen_color;
    declare v_chrg jsonb; v_set_size int;
    begin
      select charge_table, set_size into v_chrg, v_set_size from item_sets where color = v_chosen_color;
      if v_caster_count >= v_set_size then
        v_amount := (v_chrg->>'complete')::int;
      else
        v_amount := coalesce((v_chrg->>v_caster_count::text)::int, 0);
      end if;
    end;
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
