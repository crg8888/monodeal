// Monodeal — shared client types.
// Mirrors the Supabase schema in docs/lovable-prompt-v5.md (Schema, Spell registry,
// Protego state machine, Information-state model). No runtime logic.

// ---------- Primitives ----------

export type Color =
  | 'brown'
  | 'light-blue'
  | 'pink'
  | 'orange'
  | 'light-green'
  | 'black'
  | 'red'
  | 'yellow'
  | 'dark-blue'
  | 'dark-green';

export type CharacterSlug = 'harry' | 'draco' | 'hermione' | 'luna' | 'cedric';

export type CardCategory =
  | 'point'
  | 'item'
  | 'wild_item_two_color'
  | 'wild_item_any_color'
  | 'spell'
  | 'character';

export type SpellEffect =
  | 'accio_brown_light_blue'
  | 'accio_pink_orange'
  | 'accio_light_green_black'
  | 'accio_red_yellow'
  | 'accio_dark_blue_dark_green'
  | 'accio_any'
  | 'alohomora'
  | 'confundo'
  | 'geminio'
  | 'levicorpus'
  | 'obliviate'
  | 'petrificus_totalus'
  | 'protego'
  | 'reparo'
  | 'stupefy'
  | 'wingardium_leviosa';

export type GamePhase = 'lobby' | 'character_select' | 'in_game' | 'paused' | 'finished';

// ---------- Cards ----------

/** Per-color charge table; keys are 1..(set_size-1) and "complete". */
export type ChargeTable = Record<string, number>;

/** Row from `cards` table. */
export interface Card {
  id: string;
  slug: string;
  category: CardCategory;
  title: string;
  cash_value: number | null;
  colors: Color[];
  wild_charge_tables: Partial<Record<Color, ChargeTable>> | null;
  spell_effect: SpellEffect | null;
  spell_allowed_colors: Color[] | null;
  rules_text: string | null;
  flavor_text: string | null;
  art_asset_url: string | null;
}

// ---------- Player state ----------

export interface ItemColumn {
  column_id: string;
  color: Color;
  cards: Array<{ card_id: string; assigned_color: Color }>;
}

/** Public-view row from `players_public` (hand replaced by hand_count). */
export interface Player {
  id: string;
  name: string;
  seat_index: number;
  is_connected: boolean;
  last_seen_at: string;
  chosen_character: CharacterSlug | null;
  protected_color: Color | null;
  petrified: boolean;
  hand_count: number;
  bank: string[];
  item_area: ItemColumn[];
}

// ---------- Pending stack & payments ----------

export type SpellTargetStatus = 'awaiting' | 'awaiting_hit' | 'protected' | 'resolved';

export interface SpellTarget {
  player_id: string;
  status: SpellTargetStatus;
  result_debt?: number;
}

export interface SpellFrame {
  id: string;
  kind: 'spell';
  spell_slug: SpellEffect;
  caster_id: string;
  params: Record<string, string | number | boolean | null>;
  targets: SpellTarget[];
  awaiting_response_from: string | null;
  started_at: string;
}

export interface ProtegoFrame {
  id: string;
  kind: 'protego';
  caster_id: string;
  /** The frame this Protego is countering (id of the frame directly below). */
  blocks_frame_id: string;
  /** Specific target on the spell frame this Protego protects. */
  protects_target_id: string;
  awaiting_response_from: string | null;
  started_at: string;
}

export type PendingStackFrame = SpellFrame | ProtegoFrame;

export type PaymentStatus = 'pending' | 'active' | 'completed' | 'forgiven';

export interface PaymentQueueItem {
  debtor_id: string;
  amount: number;
  recipient_id: string;
  status: PaymentStatus;
}

export interface LogEntry {
  at: string;
  kind: string;
  text: string;
  data?: Record<string, string | number | boolean | null>;
}

// ---------- Settings ----------

export type ProtegoChainRule = 'one_cancels_one' | 'latest_protego_wins_all_for_that_target';
export type CedricDiscardRule = 'top_only';
export type HarryColorTiming = 'choose_once_at_character_select';
export type ReparoSpellDestination = 'bank_as_points' | 'cast_for_effect';
export type PetrificusRemovalSource = 'bank' | 'items';

export interface GameSettings {
  max_players: number;
  protego_chain_rule: ProtegoChainRule;
  cedric_discard_rule: CedricDiscardRule;
  harry_color_timing: HarryColorTiming;
  reparo_spell_destination: ReparoSpellDestination;
  petrificus_removal_sources: PetrificusRemovalSource[];
  host_absent_transfer_seconds: number;
}

// ---------- Public game state ----------

/** Row from `game_state_public` view (deck_order replaced by deck_count). */
export interface GameStatePublic {
  id: number;
  version: number;
  phase: GamePhase;
  host_player_id: string | null;
  turn_player_id: string | null;
  turn_number: number;
  plays_allowed_this_turn: number;
  plays_this_turn: number;
  has_drawn_this_turn: boolean;
  winner_player_id: string | null;
  deck_count: number;
  discard_pile: string[];
  pending_stack: PendingStackFrame[];
  payment_queue: PaymentQueueItem[];
  log: LogEntry[];
  settings: GameSettings;
  started_at: string | null;
  updated_at: string;
}

// ---------- RPC envelope (mirrors supabase-js shape) ----------

export interface RpcError {
  message: string;
  code?: string;
  details?: string | null;
}

export interface RpcResponse<T> {
  data: T | null;
  error: RpcError | null;
}
