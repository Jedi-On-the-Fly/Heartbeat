#!/usr/bin/env node
/**
 * hb-viz.js — HeartBeat DAG visualization
 *
 * Two modes, one renderer (renderBody):
 *  - SNAPSHOT (default): writes a fully SELF-CONTAINED HTML page (zero external
 *    resources, opens locally) — a point-in-time view of the DAG.
 *  - LIVE (--serve): a loopback-only HTTP server whose GET /state re-reads
 *    dag.json + state.json FRESH on every request, so the view always reflects
 *    the current execution state with no regenerate. A browser can't fetch()
 *    sibling JSON over file://, which is why a live view needs a server.
 *
 * Usage: node hb-viz.js <hb-dir> [output.html]           # snapshot
 *        node hb-viz.js <hb-dir> --serve [--port N] [--host H] [--allow-remote]
 *        (snapshot default output: <hb-dir>/dag-view.html; --port 0 = ephemeral)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');

const args = process.argv.slice(2);
let serve = false, allowRemote = false, port = 8787, host = '127.0.0.1';
const pos = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--serve') serve = true;
  else if (a === '--allow-remote') allowRemote = true;
  else if (a === '--port') port = parseInt(args[++i], 10);
  else if (a === '--host') host = args[++i];
  else pos.push(a);
}
const dir = pos[0];
if (!dir) { console.error('Usage: hb-viz.js <hb-dir> [out.html] [--serve [--port N] [--host H]]'); process.exit(2); }
const out = pos[1] ?? path.join(dir, 'dag-view.html');
// The shape contract (T186): no view of a malformed or unreadable plan — refused with ONE line.
function shapeProblem(d) {
  let L; try { L = require(path.join(__dirname, 'hb-lint.js')); if (typeof L.readDagFile !== 'function' || typeof L.shapeErrors !== 'function') throw new Error('outdated'); } catch (e) { return 'dag.json could not be checked (hb-lint.js missing or outdated?)'; }
  const { readDagFile, shapeErrors } = L;
  const r = readDagFile(path.join(d, 'dag.json'));
  return r.error || shapeErrors(r.dag, true)[0] || '';
}
{ const bad = shapeProblem(dir); if (bad) { console.error(`✗ dag.json is structurally invalid: ${bad} — run: node .hb/hb-lint.js .hb/dag.json`); process.exit(1); } }   // shape-guard: reader

const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function readData(d) {
  const J = f => JSON.parse(fs.readFileSync(path.join(d, f), 'utf8'));
  return { dag: J('dag.json'), state: J('state.json') };
}

// The single renderer — both modes derive their view from this.
function renderBody(dag, state) {
  const done   = new Set(state.completed_tasks ?? []);
  const active = new Set(state.active_tasks ?? []);
  const cph    = new Set(state.completed_phases ?? []);
  const gatePassed = new Set();
  for (const p of (dag.phases ?? [])) if (cph.has(p.id) && p.gate_exit) gatePassed.add(p.gate_exit);

  const allTasks = (dag.phases ?? []).flatMap(p => p.tasks ?? []);
  const totalT = allTasks.length;
  const doneT  = allTasks.filter(t => done.has(t.id)).length;
  const pct    = totalT ? Math.round(100 * doneT / totalT) : 0;

  let body = '';
  for (const p of (dag.phases ?? [])) {
    const locked = !!(p.gate_entry && !gatePassed.has(p.gate_entry));
    const pClass = cph.has(p.id) ? 'p-done' : locked ? 'p-locked' : 'p-open';
    body += `<section class="phase ${pClass}"><header><span class="pid">${esc(p.id)}</span> <span class="ptitle">${esc(p.title)}</span>`;
    if (p.gate_entry) body += ` <span class="gate ${gatePassed.has(p.gate_entry) ? 'g-ok' : 'g-wait'}">⛩ ${esc(p.gate_entry)}</span>`;
    body += `</header><div class="tasks">`;
    for (const t of (p.tasks ?? [])) {
      const st = done.has(t.id) ? 'done' : active.has(t.id) ? 'active' : locked ? 'locked' : 'pending';
      const reqs = (t.requires ?? []).map(r =>
        `<span class="req ${done.has(r) ? 'r-ok' : 'r-wait'}">← ${esc(r)}</span>`).join('');
      body += `<div class="task t-${st}"><b>${esc(t.id)}</b> ${esc(t.title)}${reqs}</div>`;
    }
    body += `</div>`;
    if (p.gate_exit) body += `<footer><span class="gate ${gatePassed.has(p.gate_exit) ? 'g-ok' : 'g-wait'}">⛩ ${esc(p.gate_exit)} — ${gatePassed.has(p.gate_exit) ? 'passed' : 'waiting'}</span></footer>`;
    body += `</section>\n`;
  }
  return { body, doneT, totalT, pct };
}

const styleBlock = pct => `
body{font-family:ui-sans-serif,system-ui,sans-serif;background:#0f1115;color:#e6e6e6;margin:0 auto;padding:24px;max-width:860px}
h1{font-size:20px}
.bar{height:10px;background:#23262e;border-radius:6px;overflow:hidden;margin:8px 0 24px}
.bar i{display:block;height:100%;width:${pct}%;background:#4ade80}
.phase{border:1px solid #2a2e38;border-radius:10px;margin:14px 0;padding:12px;background:#151821}
.phase.p-done{border-color:#2f6b46}.phase.p-locked{opacity:.55}
header .pid{color:#8ab4ff;font-weight:700}.ptitle{font-weight:600}
.tasks{margin-top:8px;display:grid;gap:6px}
.task{padding:8px 10px;border-radius:8px;background:#1d212c;border-left:4px solid #555;font-size:14px}
.t-done{border-left-color:#4ade80}.t-active{border-left-color:#fbbf24}
.t-pending{border-left-color:#64748b}.t-locked{border-left-color:#374151;color:#9aa0aa}
.req{margin-left:8px;font-size:12px;padding:1px 6px;border-radius:10px;background:#23262e;color:#9aa0aa}
.req.r-ok{color:#4ade80}
.gate{font-size:12px;padding:2px 8px;border-radius:10px;background:#23262e}
.g-ok{color:#4ade80}.g-wait{color:#fbbf24}
footer{margin-top:8px}.meta{color:#9aa0aa;font-size:12px}`;

// SNAPSHOT — a self-contained page (byte-compatible with the classic output).
function renderPage(dag, state) {
  const { body, doneT, totalT, pct } = renderBody(dag, state);
  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<title>HeartBeat — ${esc(dag._meta?.project ?? 'DAG')}</title>
<style>${styleBlock(pct)}
</style></head><body>
<h1>HeartBeat — ${esc(dag._meta?.project ?? '')} <span class="meta">${doneT}/${totalT} tasks · ${pct}%</span></h1>
<div class="bar"><i></i></div>
${body}
<p class="meta">Generated ${new Date().toISOString()} — hb-viz · self-contained page, no external resources</p>
</body></html>`;
}

// LIVE — the polling shell served at GET / (client sets #app + bar from /state).
function renderShell(dag) {
  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<title>HeartBeat — ${esc(dag._meta?.project ?? 'DAG')} (live)</title>
<style>${styleBlock(0)}
</style></head><body>
<h1>HeartBeat — ${esc(dag._meta?.project ?? '')} <span class="meta" id="hdr"></span></h1>
<div class="bar"><i></i></div>
<div id="app"></div>
<p class="meta">live — re-reads the DAG every 2s (no regenerate)</p>
<script>
async function poll(){
  try{
    const r = await fetch('/state'); if(!r.ok) return;
    const d = await r.json();
    document.getElementById('app').innerHTML = d.html;
    document.querySelector('.bar i').style.width = d.pct + '%';
    document.getElementById('hdr').textContent = d.doneT + '/' + d.totalT + ' tasks · ' + d.pct + '%';
  }catch(e){}
}
poll(); setInterval(poll, 2000);
</script>
</body></html>`;
}

// Security: loopback-only bind + Origin validation — the same DNS-rebinding defence the py MCP
// server applies (accepts 127/8, ::1, localhost; rejects a name like 127.0.0.1.evil.com).
function isLoopbackHost(h) {
  if (!h) return false;
  h = h.replace(/^\[/, '').replace(/\]$/, '');   // URL hostname brackets IPv6: [::1] -> ::1
  if (h === 'localhost') return true;
  if (h === '::1') return true;
  const v4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(h);   // an IP, not a name like 127.0.0.1.evil.com
  return !!v4 && v4[1] === '127';
}
function originOk(origin) {
  if (!origin) return true;   // non-browser clients send no Origin
  try { return isLoopbackHost(new URL(origin).hostname); } catch { return false; }
}

if (!serve) {
  const { dag, state } = readData(dir);
  fs.writeFileSync(out, renderPage(dag, state));
  console.log(`View generated: ${out}`);
} else {
  if (!isLoopbackHost(host) && !allowRemote) {
    console.error(`refusing to bind the viz server to non-loopback host ${host} — pass --allow-remote if you really mean it (the endpoint is unauthenticated)`);
    process.exit(1);
  }
  const server = http.createServer((req, res) => {
    if (!originOk(req.headers.origin)) { res.writeHead(403); res.end('forbidden origin'); return; }
    const url = (req.url || '/').split('?')[0];
    // re-checked on EVERY request: the server re-reads dag.json per request, so a plan broken while it runs is refused too
    { const bad = shapeProblem(dir); if (bad && (url === '/' || url === '/state')) { res.writeHead(409, { 'content-type': 'text/plain; charset=utf-8' }); res.end(`dag.json is structurally invalid: ${bad} — run: node .hb/hb-lint.js .hb/dag.json`); return; } }   // shape-guard: reader
    if (url === '/state') {
      try {
        const { dag, state } = readData(dir);
        const { body, doneT, totalT, pct } = renderBody(dag, state);
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ html: body, doneT, totalT, pct }));
      } catch (e) { res.writeHead(500); res.end('read error'); }
      return;
    }
    if (url === '/') {
      try { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); res.end(renderShell(readData(dir).dag)); }
      catch (e) { res.writeHead(500); res.end('read error'); }
      return;
    }
    res.writeHead(404); res.end('not found');
  });
  server.on('error', e => { console.error(`viz server error: ${e.message}`); process.exit(1); });
  server.listen(port, host, () => {
    const h = host.includes(':') ? `[${host}]` : host;   // bracket IPv6 in the URL
    console.log(`http://${h}:${server.address().port}`);
    console.error(`hb-viz live — ${h}:${server.address().port} (Ctrl-C to stop)`);
  });
}
