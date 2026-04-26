import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { setIdentity, getCachedName } from '../lib/identity';
import { broadcastStateChanged, useGameStore } from '../state/gameStore';

export function NameEntry() {
  const [name, setName] = useState(getCachedName());
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const refresh = useGameStore((s) => s.refresh);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    const { data, error } = await supabase.rpc('join_lobby', { p_name: name });
    if (error) {
      const map: Record<string, string> = {
        name_required: 'Please enter a name.',
        name_too_long: 'Name is too long (30 chars max).',
        lobby_closed: 'Game already in progress.',
        lobby_full: 'Lobby is full.',
      };
      setError(map[error.message] ?? error.message);
      setSubmitting(false);
      return;
    }
    const result = data as {
      player_id: string;
      player_token: string;
      assigned_name: string;
      is_host: boolean;
    };
    setIdentity({
      player_id: result.player_id,
      player_token: result.player_token,
      name: result.assigned_name,
    });
    await broadcastStateChanged();
    await refresh();
    setSubmitting(false);
  };

  return (
    <div className="min-h-dvh bg-stone-50 flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <h1 className="text-4xl font-bold text-stone-900 mb-1 text-center">Monodeal</h1>
        <p className="text-stone-500 mb-8 text-center">Magical Monopoly Deal for friends</p>
        <form onSubmit={submit} className="bg-white border border-stone-200 rounded-lg p-6 shadow-sm">
          <label className="block text-sm font-medium text-stone-700 mb-2">Your name</label>
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Chintan"
            className="w-full px-3 py-2 border border-stone-300 rounded focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-transparent"
            disabled={submitting}
            maxLength={30}
          />
          {error && <div className="text-sm text-red-600 mt-2">{error}</div>}
          <button
            type="submit"
            disabled={submitting || name.trim().length === 0}
            className="w-full mt-4 px-4 py-2 bg-emerald-700 text-white rounded hover:bg-emerald-600 disabled:opacity-50 disabled:cursor-not-allowed font-medium"
          >
            {submitting ? 'Joining...' : 'Join lobby'}
          </button>
        </form>
        <p className="text-xs text-stone-500 mt-4 text-center">
          Anyone with this URL can join. No login.
        </p>
      </div>
    </div>
  );
}
