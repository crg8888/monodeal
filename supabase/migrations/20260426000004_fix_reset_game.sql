-- Fix reset_game: Supabase enforces a "DELETE requires WHERE clause" safety
-- check, so the bare `delete from players` in the original RPC fails with
-- code 21000. Add a trivial WHERE.

create or replace function public.reset_game()
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  perform 1 from game_state where id = 1 for update;

  delete from players where true;

  update game_state set
    version = 0,
    phase = 'lobby',
    host_player_id = null,
    previous_phase = null,
    turn_player_id = null,
    turn_number = 0,
    plays_allowed_this_turn = 3,
    plays_this_turn = 0,
    has_drawn_this_turn = false,
    winner_player_id = null,
    deck_order = '{}',
    discard_pile = '{}',
    pending_stack = '[]'::jsonb,
    payment_queue = '[]'::jsonb,
    log = '[]'::jsonb,
    started_at = null,
    updated_at = now()
  where id = 1;

  return 0;
end;
$$;

revoke all on function public.reset_game() from public;
grant execute on function public.reset_game() to anon, authenticated;
