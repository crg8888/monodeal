import { create } from 'zustand';
import { supabase } from '../lib/supabase';
import type { GameStatePublic, Player, Card as CardData } from '../types/game';

interface GameStore {
  gameState: GameStatePublic | null;
  players: Player[];
  cards: Record<string, CardData>;
  loading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  startPolling: (intervalMs?: number) => () => void;
  cardLookup: (id: string) => CardData | undefined;
}

export const useGameStore = create<GameStore>((set, get) => ({
  gameState: null,
  players: [],
  cards: {},
  loading: false,
  error: null,

  cardLookup: (id: string) => get().cards[id],

  refresh: async () => {
    set({ loading: true, error: null });
    try {
      const [gameRes, playersRes, cardsRes] = await Promise.all([
        supabase.from('game_state_public').select('*').eq('id', 1).single(),
        supabase.from('players_public').select('*').order('seat_index'),
        // Cards are static reference data; fetch once and cache.
        get().cards && Object.keys(get().cards).length > 0
          ? Promise.resolve({ data: null, error: null })
          : supabase.from('cards').select('*'),
      ]);
      if (gameRes.error) throw gameRes.error;
      if (playersRes.error) throw playersRes.error;

      const update: Partial<GameStore> = {
        gameState: gameRes.data as GameStatePublic,
        players: (playersRes.data ?? []) as Player[],
        loading: false,
      };
      if (cardsRes.data) {
        const cardMap: Record<string, CardData> = {};
        for (const c of cardsRes.data as CardData[]) cardMap[c.id] = c;
        update.cards = cardMap;
      }
      set(update);
    } catch (e) {
      set({ loading: false, error: (e as Error).message });
    }
  },

  startPolling: (intervalMs = 1500) => {
    void get().refresh();
    const id = setInterval(() => void get().refresh(), intervalMs);

    // Also subscribe to broadcasts so other tabs' RPCs surface immediately.
    const ch = supabase.channel('game:public');
    ch.on('broadcast', { event: 'state-changed' }, () => void get().refresh());
    void ch.subscribe();

    return () => {
      clearInterval(id);
      void supabase.removeChannel(ch);
    };
  },
}));

// Fire after every successful mutating RPC so peers refresh immediately
// instead of waiting for their next poll tick.
export async function broadcastStateChanged() {
  try {
    await supabase.channel('game:public').send({
      type: 'broadcast',
      event: 'state-changed',
      payload: {},
    });
  } catch {
    // Broadcast failure is non-fatal; peers will pick it up on next poll.
  }
}
