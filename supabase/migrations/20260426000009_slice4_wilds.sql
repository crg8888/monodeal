-- Slice 4: wild items + recolor.
-- RPCs: play_wild_item, recolor_wild.
-- Sets containing only every-color wilds remain illegal (handled by
-- _count_complete_columns in Slice 3, which requires at least one card whose
-- category != 'wild_item_any_color' for the set to count as complete).

-- ============================================================================
-- play_wild_item — for wild_item_two_color and wild_item_any_color cards.
-- Same shape as play_item: target an existing same-color column or create new.
-- Counts as 1 play. Triggers _check_win.
-- ============================================================================

create or replace function public.play_wild_item(
  p_actor_id uuid, p_actor_token uuid, p_card_id uuid,
  p_color text, p_target_column_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_drawn bool;
  v_plays int;
  v_max_plays int;
  v_category text;
  v_card_colors text[];
  v_in_hand bool;
  v_set_size int;
  v_item_area jsonb;
  v_new_area jsonb;
  v_new_card jsonb;
  v_target_idx int := -1;
  v_target_col jsonb;
  v_won bool;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id, has_drawn_this_turn,
         plays_this_turn, plays_allowed_this_turn
    into v_phase, v_turn_id, v_drawn, v_plays, v_max_plays from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;
  if not v_drawn then raise exception 'must_draw_first'; end if;
  if v_plays >= v_max_plays then raise exception 'no_plays_left'; end if;

  select category, colors into v_category, v_card_colors from cards where id = p_card_id;
  if v_category is null then raise exception 'unknown_card'; end if;
  if v_category not in ('wild_item_two_color','wild_item_any_color') then
    raise exception 'not_a_wild';
  end if;
  if not (p_color = any(v_card_colors)) then
    raise exception 'illegal_color' using detail = p_color;
  end if;
  select p_card_id = any(hand) into v_in_hand from players where id = p_actor_id;
  if not v_in_hand then raise exception 'card_not_in_hand'; end if;

  select set_size into v_set_size from item_sets where color = p_color;
  if v_set_size is null then raise exception 'unknown_color' using detail = p_color; end if;

  select item_area into v_item_area from players where id = p_actor_id;
  v_new_card := jsonb_build_object('card_id', p_card_id, 'assigned_color', p_color);

  if p_target_column_id is not null then
    for v_target_idx in 0 .. coalesce(jsonb_array_length(v_item_area), 0) - 1 loop
      v_target_col := v_item_area->v_target_idx;
      exit when (v_target_col->>'column_id')::uuid = p_target_column_id;
      v_target_idx := -1;
    end loop;
    if v_target_idx < 0 then raise exception 'unknown_column'; end if;
    if (v_target_col->>'color') != p_color then raise exception 'wrong_column_color'; end if;
    if jsonb_array_length(v_target_col->'cards') >= v_set_size then
      raise exception 'column_complete' using detail = (v_target_col->>'color');
    end if;
  else
    for v_target_idx in 0 .. coalesce(jsonb_array_length(v_item_area), 0) - 1 loop
      v_target_col := v_item_area->v_target_idx;
      if (v_target_col->>'color') = p_color
         and jsonb_array_length(v_target_col->'cards') < v_set_size then
        exit;
      end if;
      v_target_idx := -1;
    end loop;
  end if;

  if v_target_idx < 0 then
    v_new_area := coalesce(v_item_area, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'column_id', gen_random_uuid()::text,
      'color', p_color,
      'cards', jsonb_build_array(v_new_card)
    ));
  else
    v_new_area := jsonb_set(
      v_item_area,
      array[v_target_idx::text, 'cards'],
      (v_item_area->v_target_idx->'cards') || v_new_card
    );
  end if;

  update players set
    hand = array_remove(hand, p_card_id),
    item_area = v_new_area
  where id = p_actor_id;

  update game_state set plays_this_turn = plays_this_turn + 1,
                        version = version + 1, updated_at = now() where id = 1;
  perform _append_log('wild',
    (select name from players where id = p_actor_id) || ' played ' ||
    (select title from cards where id = p_card_id) || ' as ' || p_color);

  v_won := _check_win(p_actor_id);
  return jsonb_build_object('ok', true, 'won', v_won);
end;
$$;
revoke all on function public.play_wild_item(uuid, uuid, uuid, text, uuid) from public;
grant execute on function public.play_wild_item(uuid, uuid, uuid, text, uuid) to anon, authenticated;

-- ============================================================================
-- recolor_wild — free action during own turn. Moves an already-played wild
-- between columns. Doesn't increment plays_this_turn. Source column shrinks
-- (removed entirely if it becomes empty); target column is created/joined as
-- usual.
-- ============================================================================

create or replace function public.recolor_wild(
  p_actor_id uuid, p_actor_token uuid, p_card_id uuid,
  p_new_color text, p_target_column_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_category text;
  v_card_colors text[];
  v_set_size int;
  v_item_area jsonb;
  v_new_area jsonb;
  v_src_idx int := -1;
  v_src_col jsonb;
  v_target_idx int := -1;
  v_target_col jsonb;
  v_new_card jsonb;
  v_won bool;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id into v_phase, v_turn_id from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;

  select category, colors into v_category, v_card_colors from cards where id = p_card_id;
  if v_category not in ('wild_item_two_color','wild_item_any_color') then
    raise exception 'not_a_wild';
  end if;
  if not (p_new_color = any(v_card_colors)) then
    raise exception 'illegal_color' using detail = p_new_color;
  end if;

  select set_size into v_set_size from item_sets where color = p_new_color;
  if v_set_size is null then raise exception 'unknown_color' using detail = p_new_color; end if;

  select item_area into v_item_area from players where id = p_actor_id;

  -- Find source column containing this card.
  for v_src_idx in 0 .. coalesce(jsonb_array_length(v_item_area), 0) - 1 loop
    if exists (
      select 1 from jsonb_array_elements(v_item_area->v_src_idx->'cards') c
      where (c->>'card_id')::uuid = p_card_id
    ) then exit; else v_src_idx := -1; end if;
  end loop;
  if v_src_idx < 0 then raise exception 'card_not_in_item_area'; end if;
  v_src_col := v_item_area->v_src_idx;

  -- Remove from source column.
  v_new_area := jsonb_set(
    v_item_area,
    array[v_src_idx::text, 'cards'],
    (
      select coalesce(jsonb_agg(c), '[]'::jsonb)
      from jsonb_array_elements(v_src_col->'cards') c
      where (c->>'card_id')::uuid != p_card_id
    )
  );
  -- Drop source column entirely if it's now empty.
  if jsonb_array_length(v_new_area->v_src_idx->'cards') = 0 then
    v_new_area := (v_new_area - v_src_idx);
  end if;

  v_new_card := jsonb_build_object('card_id', p_card_id, 'assigned_color', p_new_color);

  -- Find target column.
  if p_target_column_id is not null then
    for v_target_idx in 0 .. coalesce(jsonb_array_length(v_new_area), 0) - 1 loop
      v_target_col := v_new_area->v_target_idx;
      exit when (v_target_col->>'column_id')::uuid = p_target_column_id;
      v_target_idx := -1;
    end loop;
    if v_target_idx < 0 then raise exception 'unknown_column'; end if;
    if (v_target_col->>'color') != p_new_color then raise exception 'wrong_column_color'; end if;
    if jsonb_array_length(v_target_col->'cards') >= v_set_size then
      raise exception 'column_complete' using detail = p_new_color;
    end if;
  else
    for v_target_idx in 0 .. coalesce(jsonb_array_length(v_new_area), 0) - 1 loop
      v_target_col := v_new_area->v_target_idx;
      if (v_target_col->>'color') = p_new_color
         and jsonb_array_length(v_target_col->'cards') < v_set_size then
        exit;
      end if;
      v_target_idx := -1;
    end loop;
  end if;

  if v_target_idx < 0 then
    v_new_area := coalesce(v_new_area, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'column_id', gen_random_uuid()::text,
      'color', p_new_color,
      'cards', jsonb_build_array(v_new_card)
    ));
  else
    v_new_area := jsonb_set(
      v_new_area,
      array[v_target_idx::text, 'cards'],
      (v_new_area->v_target_idx->'cards') || v_new_card
    );
  end if;

  update players set item_area = v_new_area where id = p_actor_id;
  update game_state set version = version + 1, updated_at = now() where id = 1;
  perform _append_log('recolor',
    (select name from players where id = p_actor_id) || ' recolored ' ||
    (select title from cards where id = p_card_id) || ' to ' || p_new_color);

  v_won := _check_win(p_actor_id);
  return jsonb_build_object('ok', true, 'won', v_won);
end;
$$;
revoke all on function public.recolor_wild(uuid, uuid, uuid, text, uuid) from public;
grant execute on function public.recolor_wild(uuid, uuid, uuid, text, uuid) to anon, authenticated;
