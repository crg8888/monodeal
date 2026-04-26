import { useEffect, useState } from 'react';
import { Routes, Route } from 'react-router-dom';
import { supabase } from './lib/supabase';
import { useGameStore } from './state/gameStore';
import { getIdentity, clearIdentity, setIdentity } from './lib/identity';
import { NameEntry } from './screens/NameEntry';
import { Lobby } from './screens/Lobby';
import { CharacterSelect } from './screens/CharacterSelect';

function Game() {
  const gameState = useGameStore((s) => s.gameState);
  const players = useGameStore((s) => s.players);
  const startPolling = useGameStore((s) => s.startPolling);
  const error = useGameStore((s) => s.error);
  const [identityReady, setIdentityReady] = useState(false);

  // Reconnect path: on first mount, if we have an identity in localStorage,
  // ping the server to confirm it's still valid (token survives Full Reset?).
  useEffect(() => {
    const stored = getIdentity();
    if (!stored) {
      setIdentityReady(true);
      return;
    }
    void (async () => {
      const { data, error } = await supabase.rpc('reconnect', {
        p_player_id: stored.player_id,
        p_player_token: stored.player_token,
      });
      if (error || !(data as { ok: boolean })?.ok) {
        clearIdentity();
      } else {
        setIdentity(stored);
      }
      setIdentityReady(true);
    })();
  }, []);

  useEffect(() => {
    if (!identityReady) return;
    return startPolling(1500);
  }, [identityReady, startPolling]);

  if (!identityReady || !gameState) {
    return (
      <div className="min-h-dvh bg-stone-50 flex items-center justify-center">
        <div className="text-stone-500 text-sm">Connecting…</div>
        {error && <div className="text-red-600 text-sm mt-2">{error}</div>}
      </div>
    );
  }

  const me = getIdentity();
  const meStillExists = me && players.some((p) => p.id === me.player_id);

  // No identity yet, or server says my id is gone (post-reset). Show name entry.
  if (!me || !meStillExists) {
    if (me && !meStillExists) clearIdentity();
    return <NameEntry />;
  }

  // Routing by phase.
  switch (gameState.phase) {
    case 'lobby':
      return <Lobby />;
    case 'character_select':
      return <CharacterSelect />;
    case 'in_game':
      return <GameTableStub />;
    case 'paused':
      return <PausedStub />;
    case 'finished':
      return <FinishedStub />;
    default:
      return (
        <div className="min-h-dvh flex items-center justify-center">
          Unknown phase: {gameState.phase}
        </div>
      );
  }
}

// Stubs replaced in later slices.
function GameTableStub() {
  return <div className="p-8">In-game UI lands in Slice 3.</div>;
}
function PausedStub() {
  return <div className="p-8 text-center">Game is paused…</div>;
}
function FinishedStub() {
  return <div className="p-8 text-center">Game finished.</div>;
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Game />} />
    </Routes>
  );
}
