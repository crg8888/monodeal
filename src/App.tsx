import { useEffect, useState } from 'react';
import { Routes, Route } from 'react-router-dom';
import { supabase } from './lib/supabase';

function SmokeTest() {
  const [version, setVersion] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [log, setLog] = useState<string[]>([]);

  const fetchVersion = async () => {
    const { data, error } = await supabase
      .from('game_state_public')
      .select('version')
      .eq('id', 1)
      .single();
    if (error) {
      setLog((l) => [...l, `fetch error: ${error.message}`]);
      return;
    }
    setVersion((data as { version: number }).version);
  };

  useEffect(() => {
    fetchVersion();
    const interval = setInterval(fetchVersion, 2000);
    return () => clearInterval(interval);
  }, []);

  const reset = async () => {
    setLoading(true);
    const { error } = await supabase.rpc('reset_game');
    if (error) setLog((l) => [...l, `reset error: ${error.message}`]);
    else setLog((l) => [...l, 'reset → version 0']);
    await fetchVersion();
    setLoading(false);
  };

  const burst = async (n: number) => {
    setLoading(true);
    setLog((l) => [...l, `firing ${n} concurrent increment_counter()...`]);
    const start = performance.now();
    const promises = Array.from({ length: n }, () => supabase.rpc('increment_counter'));
    const results = await Promise.all(promises);
    const elapsed = ((performance.now() - start) / 1000).toFixed(2);
    const errors = results.filter((r) => r.error).length;
    const values = results.map((r) => (r.data as number) ?? 0);
    const max = values.length > 0 ? Math.max(...values) : 0;
    setLog((l) => [...l, `${n} calls in ${elapsed}s · errors=${errors} · max returned=${max}`]);
    await fetchVersion();
    setLoading(false);
  };

  return (
    <div className="min-h-dvh bg-stone-50 p-4 sm:p-8">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-3xl font-bold text-stone-900 mb-1">Monodeal</h1>
        <p className="text-stone-500 mb-6">Slice 0 — concurrency smoke test</p>

        <div className="bg-white rounded-lg border border-stone-200 p-6 mb-4">
          <div className="text-sm text-stone-500">Current version</div>
          <div className="text-5xl font-mono font-bold text-stone-900">{version ?? '—'}</div>
        </div>

        <div className="flex flex-wrap gap-2 mb-4">
          <button
            onClick={reset}
            disabled={loading}
            className="px-4 py-2 bg-stone-900 text-white rounded hover:bg-stone-700 disabled:opacity-50"
          >
            Reset to 0
          </button>
          <button
            onClick={() => burst(100)}
            disabled={loading}
            className="px-4 py-2 bg-emerald-700 text-white rounded hover:bg-emerald-600 disabled:opacity-50"
          >
            Fire 100×
          </button>
          <button
            onClick={() => burst(10)}
            disabled={loading}
            className="px-4 py-2 bg-stone-200 text-stone-900 rounded hover:bg-stone-300 disabled:opacity-50"
          >
            Fire 10× (debug)
          </button>
        </div>

        <div className="bg-white rounded-lg border border-stone-200 p-4 text-sm font-mono text-stone-700">
          <div className="font-bold mb-2">Test plan (T0.1)</div>
          <ol className="list-decimal list-inside space-y-1 text-stone-600">
            <li>Click "Reset to 0".</li>
            <li>Open this URL in a second tab.</li>
            <li>
              Click "Fire 100×" in <strong>both tabs simultaneously</strong>.
            </li>
            <li>
              Final version must equal exactly <strong>200</strong>.
            </li>
          </ol>
          {log.length > 0 && (
            <div className="mt-4 pt-4 border-t border-stone-200 space-y-1">
              {log.map((l, i) => (
                <div key={i}>{l}</div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<SmokeTest />} />
    </Routes>
  );
}
