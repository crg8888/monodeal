-- Slice 0: schema, RLS, public views.
-- Source: docs/lovable-prompt-v5.md, "Schema" section.

-- ============================================================================
-- Tables
-- ============================================================================

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

-- item_area shape: [{ column_id, color, cards: [{ card_id, assigned_color }] }]
-- Players may have multiple columns of the same color (Obliviate defense).

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

-- ============================================================================
-- Public views (exclude private fields: deck_order, hand, token)
-- ============================================================================

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

-- Run views with elevated privileges so they bypass RLS on the underlying
-- tables. Anon reads game_state_public/players_public; raw tables stay locked.
alter view game_state_public set (security_invoker = false);
alter view players_public set (security_invoker = false);

-- ============================================================================
-- RLS: deny anon writes; reference tables (cards, item_sets) read-only public.
-- ============================================================================

alter table game_state enable row level security;
alter table players enable row level security;
alter table item_sets enable row level security;
alter table cards enable row level security;

-- Strip default grants Supabase puts on public tables, then re-grant minimal.
revoke all on table game_state from anon, authenticated;
revoke all on table players from anon, authenticated;
revoke all on table item_sets from anon, authenticated;
revoke all on table cards from anon, authenticated;

grant select on table cards to anon, authenticated;
grant select on table item_sets to anon, authenticated;
grant select on table game_state_public to anon, authenticated;
grant select on table players_public to anon, authenticated;

-- Reference tables: explicit select-all policies (RLS is on, so we need them).
create policy cards_select_all on cards for select to anon, authenticated using (true);
create policy item_sets_select_all on item_sets for select to anon, authenticated using (true);

-- game_state and players: NO policies. RLS denies all anon access to raw rows.
-- Mutations only through SECURITY DEFINER RPCs that validate player_token.

-- ============================================================================
-- Singleton row
-- ============================================================================

insert into game_state (id) values (1) on conflict (id) do nothing;
