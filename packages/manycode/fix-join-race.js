'use strict';
// smoke.js loses a race on a loaded builder, and it is a dropped frame rather
// than a slow one — no amount of extra timeout fixes it.
//
// joinWs() resolves its promise on the 'ok' frame; the caller then attaches
// collectUntil()'s listener in the await continuation. Frames only reach that
// continuation if they land in a later event-loop turn. On an idle machine
// they do: 'ok' arrives, then the replay a turn later. On a builder running
// twenty other derivations the host is descheduled between writes, so the
// kernel coalesces 'ok', the replay and the title frame into a single read —
// ws emits all three synchronously, the microtask that attaches the collector
// runs after the last of them, and the replay carrying MARKER_READY is gone
// before anyone is listening. It surfaces as
//
//   FAIL direct: timeout waiting for "MARKER_READY"; got: ""
//
// from whichever subtest lost the race that run.
//
// Fix: accumulate from the first frame, in the listener joinWs installs before
// the handshake, and let collectUntil read that buffer — including the case
// where the needle is already in it.
//
// The deadlines are deliberately left at upstream's 4-5s. Raising them fixes
// nothing — a frame that was never observed does not arrive later — and on a
// 4-cpu runner model under 2x oversubscription the suite passes with them
// untouched. So if this ever fails with a timeout again, it is a new problem
// and worth diagnosing rather than padding. edges.js is left alone entirely:
// it never failed in CI, and it paces itself against hosted `bash -c 'sleep
// N'` sessions, so its deadlines are coupled to those lifetimes.
//
// Upstream is dormant (last commit 2026-07-17), so no fix is coming from
// there. Delete this file and its postPatch line if the suites ever collect
// from socket open themselves.
//   https://github.com/unworld11/manycode/tree/master/test
const fs = require('fs');

const [file] = process.argv.slice(2);
let src = fs.readFileSync(file, 'utf8');

// Anchored on the exact upstream text: a version bump that rewrites these
// helpers should fail the build loudly rather than silently skip the fix.
const replacements = [
  [
    `function collectUntil(ws, needle, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    let acc = '';
    const to = setTimeout(() => reject(new Error(\`timeout waiting for \${JSON.stringify(needle)}; got: \${JSON.stringify(acc.slice(-300))}\`)), timeoutMs);
    ws.on('message', (data, isBinary) => {
      if (isBinary) acc += data.toString('utf8');
      else {
        const m = JSON.parse(data);
        if (m.t === 'replay' && m.d) acc += Buffer.from(m.d, 'base64').toString('utf8');
        if (m.t === 'err') { clearTimeout(to); reject(new Error('err: ' + m.msg)); }
      }
      if (acc.includes(needle)) { clearTimeout(to); resolve(acc); }
    });
  });
}`,
    `function collectUntil(ws, needle, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    // ws._acc has been filling since the socket opened, so the needle may
    // already have arrived alongside the join handshake.
    if (ws._acc.includes(needle)) { resolve(ws._acc); return; }
    const to = setTimeout(() => reject(new Error(\`timeout waiting for \${JSON.stringify(needle)}; got: \${JSON.stringify(ws._acc.slice(-300))}\`)), timeoutMs);
    const onMessage = (data, isBinary) => {
      if (!isBinary) {
        const m = JSON.parse(data);
        if (m.t === 'err') { clearTimeout(to); ws.off('message', onMessage); reject(new Error('err: ' + m.msg)); return; }
      }
      if (ws._acc.includes(needle)) { clearTimeout(to); ws.off('message', onMessage); resolve(ws._acc); }
    };
    ws.on('message', onMessage);
  });
}`,
  ],
  [
    `    const ws = new WebSocket(url);
    const to = setTimeout(() => reject(new Error('join timeout')), 5000);
    ws.on('open', () => ws.send(JSON.stringify({ t: 'join', code, name, cols: 100, rows: 30 })));
    ws.on('message', (data, isBinary) => {
      if (isBinary) return;
      const m = JSON.parse(data);`,
    `    const ws = new WebSocket(url);
    // Session output, buffered from the first frame rather than from whenever
    // a collector gets attached.
    ws._acc = '';
    const to = setTimeout(() => reject(new Error('join timeout')), 5000);
    ws.on('open', () => ws.send(JSON.stringify({ t: 'join', code, name, cols: 100, rows: 30 })));
    ws.on('message', (data, isBinary) => {
      if (isBinary) { ws._acc += data.toString('utf8'); return; }
      const m = JSON.parse(data);
      if (m.t === 'replay' && m.d) ws._acc += Buffer.from(m.d, 'base64').toString('utf8');`,
  ],
];

for (const [from, to] of replacements) {
  if (!src.includes(from)) {
    throw new Error(`${file}: no match for upstream text starting "${from.split('\n')[0]}" — the suite changed, revisit the join race`);
  }
  src = src.split(from).join(to);
}

fs.writeFileSync(file, src);
