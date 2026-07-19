#!/usr/bin/env node
/**
 * hb-viz.js — HeartBeat DAG visualization
 *
 * Generates a fully SELF-CONTAINED HTML page (zero external resources, opens
 * locally) showing: phases, tasks colored by status (done / active / pending /
 * locked), gates (passed / waiting) and dependencies (requires).
 *
 * Usage: node hb-viz.js <hb-dir> [output.html]
 *        (default: <hb-dir>/dag-view.html)
 */
'use strict';
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('Usage: hb-viz.js <hb-dir> [out.html]'); process.exit(2); }
const out = process.argv[3] ?? path.join(dir, 'dag-view.html');

const J = f => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
const dag = J('dag.json'), state = J('state.json');

const done   = new Set(state.completed_tasks ?? []);
const active = new Set(state.active_tasks ?? []);
const cph    = new Set(state.completed_phases ?? []);
const gatePassed = new Set();
for (const p of (dag.phases ?? [])) if (cph.has(p.id) && p.gate_exit) gatePassed.add(p.gate_exit);

const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
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

const html = `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<title>HeartBeat — ${esc(dag._meta?.project ?? 'DAG')}</title>
<style>
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
footer{margin-top:8px}.meta{color:#9aa0aa;font-size:12px}
</style></head><body>
<h1>HeartBeat — ${esc(dag._meta?.project ?? '')} <span class="meta">${doneT}/${totalT} tasks · ${pct}%</span></h1>
<div class="bar"><i></i></div>
${body}
<p class="meta">Generated ${new Date().toISOString()} — hb-viz · self-contained page, no external resources</p>
</body></html>`;

fs.writeFileSync(out, html);
console.log(`View generated: ${out}`);
