// Monodeal — pure-function rules helpers for client-side display.
//
// Server is authoritative. Nothing here mutates state, calls RPCs, or touches
// localStorage. These helpers exist so the UI can render correct legality,
// payouts, totals, and win-state without round-tripping for every question.
//
// Reference: docs/lovable-prompt-v5.md — "Rules engine", "Item sets",
// and "Spell registry" sections.

import type {
  Card as CardData,
  Color,
  GameSettings,
  ItemColumn,
  Player,
} from '../types/game';

// Re-export GameSettings so dependents can import it from here without
// reaching into types/game directly. (Kept as a type-only re-export.)
export type { GameSettings };

// ---------- Item sets ----------

export interface ItemSet {
  color: Color;
  set_size: number;
  cash_value: number;
  /** Keys: '1', '2', '3', ..., 'complete'. */
  charge_table: Record<string, number>;
}

/**
 * Hardcoded reference data — must mirror the Supabase seed migration
 * (`supabase/migrations/20260426000002_seed_cards.sql`). Spec lines ~263-273.
 * Tests assert this matches the DB row-for-row.
 */
export const ITEM_SETS: Record<Color, ItemSet> = {
  brown: {
    color: 'brown',
    set_size: 2,
    cash_value: 1,
    charge_table: { '1': 1, complete: 2 },
  },
  'light-blue': {
    color: 'light-blue',
    set_size: 3,
    cash_value: 1,
    charge_table: { '1': 1, '2': 2, complete: 3 },
  },
  pink: {
    color: 'pink',
    set_size: 3,
    cash_value: 2,
    charge_table: { '1': 1, '2': 2, complete: 4 },
  },
  orange: {
    color: 'orange',
    set_size: 3,
    cash_value: 2,
    charge_table: { '1': 1, '2': 3, complete: 5 },
  },
  'light-green': {
    color: 'light-green',
    set_size: 2,
    cash_value: 2,
    charge_table: { '1': 1, complete: 2 },
  },
  black: {
    color: 'black',
    set_size: 4,
    cash_value: 2,
    charge_table: { '1': 1, '2': 2, '3': 3, complete: 4 },
  },
  red: {
    color: 'red',
    set_size: 3,
    cash_value: 3,
    charge_table: { '1': 2, '2': 3, complete: 6 },
  },
  yellow: {
    color: 'yellow',
    set_size: 3,
    cash_value: 3,
    charge_table: { '1': 2, '2': 4, complete: 6 },
  },
  'dark-blue': {
    color: 'dark-blue',
    set_size: 2,
    cash_value: 4,
    charge_table: { '1': 3, complete: 8 },
  },
  'dark-green': {
    color: 'dark-green',
    set_size: 3,
    cash_value: 4,
    charge_table: { '1': 2, '2': 4, complete: 7 },
  },
};

const ALL_COLORS: Color[] = [
  'brown',
  'light-blue',
  'pink',
  'orange',
  'light-green',
  'black',
  'red',
  'yellow',
  'dark-blue',
  'dark-green',
];

// ---------- Display helpers ----------

/** Map color slug → Title Case display name (e.g. "light-blue" → "Light Blue"). */
export function colorHumanName(c: Color): string {
  return c
    .split('-')
    .map((part) => (part.length === 0 ? part : part[0].toUpperCase() + part.slice(1)))
    .join(' ');
}

// ---------- Set / column logic ----------

/**
 * A column is complete when it has at least `set_size` cards AND at least one
 * card that is not an every-color wild. Spec lines 460-461 — every-color wilds
 * alone don't count as a complete set.
 */
export function isColumnComplete(
  column: ItemColumn,
  cardLookup: (id: string) => CardData | undefined,
): boolean {
  const setSize = ITEM_SETS[column.color]?.set_size;
  if (setSize === undefined) return false;
  if (column.cards.length < setSize) return false;
  for (const entry of column.cards) {
    const card = cardLookup(entry.card_id);
    if (card && card.category !== 'wild_item_any_color') return true;
  }
  return false;
}

/**
 * Counts items of a given color a player controls, including wilds currently
 * assigned to that color across all their columns. Used for Accio resolution
 * preview ("Brown: you own 2 items → opponents pay 2 each").
 */
export function countItemsForColor(player: Player, color: Color): number {
  let count = 0;
  for (const column of player.item_area) {
    for (const entry of column.cards) {
      if (entry.assigned_color === color) count += 1;
    }
  }
  return count;
}

// ---------- Charge / payout ----------

/**
 * Charge-table lookup. If `count` >= the color's set_size, returns the
 * "complete" charge; otherwise the keyed entry, defaulting to 0 when absent.
 */
export function chargeFor(color: Color, count: number): number {
  const set = ITEM_SETS[color];
  if (!set) return 0;
  if (count <= 0) return 0;
  if (count >= set.set_size) return set.charge_table.complete ?? 0;
  return set.charge_table[String(count)] ?? 0;
}

/**
 * The Accio payout the caster would extract from each opponent for this color.
 * Counts wilds assigned to the color. Returns 0 if the caster controls 0
 * matching items (cast still proceeds; UI surfaces a warning).
 */
export function accioPayoutFor(caster: Player, color: Color): number {
  const count = countItemsForColor(caster, color);
  return chargeFor(color, count);
}

// ---------- Cash value / payment ----------

/**
 * Cash value of a card from the caller's perspective, for UI totals only —
 * the server uses its own canonical value during payment resolution.
 *
 * - Two-color wilds: max of the two colors' `complete` charge if a
 *   `wild_charge_tables` map is present; otherwise fall back to `cash_value`.
 * - Every-color wilds: 0 (cannot be used to pay).
 * - Other cards: `cash_value` if set, else 0.
 */
export function displayCashValue(card: CardData): number {
  if (card.category === 'wild_item_any_color') return 0;
  if (card.category === 'wild_item_two_color') {
    if (card.wild_charge_tables) {
      let max = 0;
      for (const tbl of Object.values(card.wild_charge_tables)) {
        const v = tbl?.complete;
        if (typeof v === 'number' && v > max) max = v;
      }
      if (max > 0) return max;
    }
    return card.cash_value ?? 0;
  }
  return card.cash_value ?? 0;
}

/**
 * Total a player could pay with right now: bank cash plus item cash, excluding
 * every-color wilds (cash 0, can't be used as payment per spec). Used to
 * pre-flight payment modals and skip them when the answer is 0 (spec lines
 * 467-469).
 */
export function availableForPayment(
  player: Player,
  cardLookup: (id: string) => CardData | undefined,
): number {
  let total = 0;
  for (const id of player.bank) {
    const c = cardLookup(id);
    if (c) total += displayCashValue(c);
  }
  for (const column of player.item_area) {
    for (const entry of column.cards) {
      const c = cardLookup(entry.card_id);
      if (!c) continue;
      if (c.category === 'wild_item_any_color') continue; // cash 0, unpayable
      total += displayCashValue(c);
    }
  }
  return total;
}

// ---------- Turn / character ----------

/**
 * Plays allowed this turn for the player based solely on character + petrified
 * state. Hermione gets 4 while not petrified; everyone else (including a
 * petrified Hermione) gets 3. The server is still authoritative for the live
 * `plays_allowed_this_turn` value on `game_state`.
 */
export function playsAllowed(player: Player): number {
  if (player.chosen_character === 'hermione' && !player.petrified) return 4;
  return 3;
}

// ---------- Win condition ----------

/**
 * True when the player has 3 distinct-color complete sets — the win condition
 * (spec line 461). Multiple complete columns of the same color count as one
 * toward this total.
 */
export function isWinning(
  player: Player,
  cardLookup: (id: string) => CardData | undefined,
): boolean {
  const completedColors = new Set<Color>();
  for (const column of player.item_area) {
    if (isColumnComplete(column, cardLookup)) {
      completedColors.add(column.color);
    }
  }
  return completedColors.size >= 3;
}

// ---------- Targeting helpers ----------

/**
 * Colors a card may be assigned to when played as an item. Two-color wilds
 * return their two declared colors; every-color wilds return all 10; regular
 * items return their `colors` array (typically a single entry).
 */
export function legalColorsFor(card: CardData): Color[] {
  if (card.category === 'wild_item_any_color') return [...ALL_COLORS];
  if (card.category === 'wild_item_two_color') return [...card.colors];
  return [...card.colors];
}
