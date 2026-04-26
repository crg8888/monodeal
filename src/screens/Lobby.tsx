import { supabase } from '../lib/supabase';
import { getIdentity, clearIdentity, isHost } from '../lib/identity';
import { broadcastStateChanged, useGameStore } from '../state/gameStore';

export function Lobby() {
  const gameState = useGameStore((s) => s.gameState);
  const players = useGameStore((s) => s.players);
  const refresh = useGameStore((s) => s.refresh);
  const me = getIdentity();
  const meIsHost = isHost(me, gameState?.host_player_id ?? null);

  const kick = async (targetId: string, name: string) => {
    if (!me) return;
    if (!confirm(`Kick ${name}?`)) return;
    const { error } = await supabase.rpc('kick_player_lobby', {
      p_actor_id: me.player_id,
      p_actor_token: me.player_token,
      p_target_id: targetId,
    });
    if (error) {
      alert(`Kick failed: ${error.message}`);
      return;
    }
    await broadcastStateChanged();
    await refresh();
  };

  const fullReset = async () => {
    if (!me) return;
    if (!confirm('Reset everything? This kicks all players and clears the game.')) return;
    const { error } = await supabase.rpc('host_full_reset', {
      p_actor_id: me.player_id,
      p_actor_token: me.player_token,
    });
    if (error) {
      alert(`Reset failed: ${error.message}`);
      return;
    }
    clearIdentity();
    await broadcastStateChanged();
    await refresh();
  };

  const startGame = async () => {
    if (!me) return;
    const { error } = await supabase.rpc('start_game', {
      p_actor_id: me.player_id,
      p_actor_token: me.player_token,
    });
    if (error) {
      alert(`Start failed: ${error.message}`);
      return;
    }
    await broadcastStateChanged();
    await refresh();
  };

  if (!gameState || !me) return null;
  const canStart = meIsHost && players.length >= 2 && players.length <= 5;

  return (
    <div className="min-h-dvh bg-stone-50 p-4 sm:p-8">
      <div className="max-w-md mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-3xl font-bold text-stone-900">Monodeal</h1>
            <p className="text-stone-500 text-sm">Lobby · {players.length}/5 players</p>
          </div>
          {meIsHost && (
            <span className="text-xs px-2 py-1 bg-amber-100 text-amber-900 rounded font-medium">
              you are host
            </span>
          )}
        </div>

        <div className="bg-white border border-stone-200 rounded-lg p-4 mb-4">
          <h2 className="text-sm font-medium text-stone-700 mb-3">Players</h2>
          <ul className="space-y-2">
            {players.map((p) => (
              <li
                key={p.id}
                className={`flex items-center justify-between p-2 rounded ${
                  p.id === me.player_id ? 'bg-emerald-50' : 'bg-stone-50'
                }`}
              >
                <div className="flex items-center gap-2">
                  <span
                    className={`inline-block w-2 h-2 rounded-full ${
                      p.is_connected ? 'bg-emerald-500' : 'bg-stone-300'
                    }`}
                  />
                  <span className="font-medium text-stone-900">{p.name}</span>
                  {p.id === gameState.host_player_id && (
                    <span className="text-xs text-amber-700">★ host</span>
                  )}
                  {p.id === me.player_id && (
                    <span className="text-xs text-emerald-700">(you)</span>
                  )}
                </div>
                {meIsHost && p.id !== me.player_id && (
                  <button
                    onClick={() => kick(p.id, p.name)}
                    className="text-xs text-red-700 hover:text-red-800 hover:underline"
                  >
                    kick
                  </button>
                )}
              </li>
            ))}
          </ul>
        </div>

        {meIsHost ? (
          <div className="space-y-2">
            <button
              onClick={startGame}
              disabled={!canStart}
              className="w-full px-4 py-3 bg-emerald-700 text-white rounded hover:bg-emerald-600 disabled:opacity-50 disabled:cursor-not-allowed font-medium"
            >
              {players.length < 2
                ? 'Waiting for 2+ players…'
                : `Start game · ${players.length} players (characters random)`}
            </button>
            <button
              onClick={fullReset}
              className="w-full px-4 py-2 text-red-700 hover:bg-red-50 rounded text-sm"
            >
              full reset (kicks everyone)
            </button>
          </div>
        ) : (
          <div className="text-sm text-stone-500 text-center py-4">
            Waiting for host to start the game…
          </div>
        )}
      </div>
    </div>
  );
}
