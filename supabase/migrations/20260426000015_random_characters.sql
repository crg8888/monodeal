-- Switch to random character allocation. start_game can now be called
-- directly from the 'lobby' phase, skipping the manual character-select step.
-- Each player gets a random unique character; Harry's protected_color is also
-- randomized.
--
-- The old 'character_select' phase + choose_character / set_protected_color
-- RPCs remain in place for forward-compat but are no longer wired into the UI.

create or replace function public.start_game(
  p_actor_id uuid, p_actor_token uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_host_id uuid;
  v_phase text;
  v_total int;
  v_locked int;
  v_first_player uuid;
  v_chars text[] := array['harry','draco','hermione','luna','cedric'];
  v_colors text[] := array['brown','light-blue','pink','orange','light-green',
                            'black','red','yellow','dark-blue','dark-green'];
  v_player_ids uuid[];
  v_random_color text;
  i int;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select host_player_id, phase into v_host_id, v_phase from game_state where id = 1;
  if p_actor_id != v_host_id then raise exception 'not_host'; end if;
  if v_phase not in ('lobby', 'character_select') then
    raise exception 'wrong_phase' using detail = v_phase;
  end if;

  select count(*) into v_total from players;
  if v_total < 2 then raise exception 'need_two_players'; end if;
  if v_total > 5 then raise exception 'too_many_players'; end if;

  if v_phase = 'lobby' then
    -- Random allocation of characters + Harry's color.
    select array_agg(c order by random()) into v_chars from unnest(v_chars) c;
    select array_agg(id order by seat_index) into v_player_ids from players;
    for i in 1 .. v_total loop
      update players set chosen_character = v_chars[i],
                         protected_color = null,
                         petrified = false
        where id = v_player_ids[i];
    end loop;
    -- Random color for whoever got Harry.
    v_random_color := v_colors[1 + floor(random() * array_length(v_colors, 1))::int];
    update players set protected_color = v_random_color
      where chosen_character = 'harry';
  else
    -- Legacy character_select path: trust existing chosen_character + protected_color.
    select count(*) filter (where chosen_character is not null) into v_locked from players;
    if v_locked < v_total then raise exception 'players_not_ready'; end if;
    if exists(select 1 from players where chosen_character = 'harry' and protected_color is null) then
      raise exception 'harry_color_unset';
    end if;
  end if;

  perform _shuffle_and_deal();

  select id into v_first_player from players order by random() limit 1;

  update game_state set
    phase = 'in_game',
    turn_player_id = v_first_player,
    turn_number = 1,
    plays_allowed_this_turn = _compute_plays_allowed(v_first_player),
    plays_this_turn = 0,
    has_drawn_this_turn = false,
    started_at = now(),
    version = version + 1,
    updated_at = now()
  where id = 1;
  perform _append_log('phase', 'game starts (turn 1) — characters randomized');
  return jsonb_build_object('ok', true, 'first_player', v_first_player);
end;
$$;
revoke all on function public.start_game(uuid, uuid) from public;
grant execute on function public.start_game(uuid, uuid) to anon, authenticated;
