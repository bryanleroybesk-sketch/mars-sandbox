/* Life OS — a personal life dashboard.
 * Plain JS, no build step. All data lives on the device (localStorage).
 * Use "More → Export" for backups, or add a cloud sync later (see README).
 */
(() => {
  'use strict';

  // ---------- storage ----------
  const KEY = 'lifeos.v1';
  const AREAS = [
    ['health', 'Health'], ['work', 'Work / Career'], ['money', 'Finances'],
    ['love', 'Partner'], ['social', 'Family & friends'], ['growth', 'Growth'],
    ['peace', 'Peace / Mind'], ['fun', 'Fun & joy'],
  ];
  const TIME_CATS = [
    ['deep', 'Deep work'], ['self', 'Invest in me'], ['partner', 'Partner'],
    ['body', 'Exercise'], ['rest', 'Rest / peace'], ['fun', 'Fun'],
  ];
  const SPEND_CATS = ['Food', 'Transport', 'Home', 'Fun', 'Health', 'Self-growth', 'Partner', 'Other'];

  const defaults = () => ({
    settings: {
      waterGoal: 2500, stepGoal: 10000, sleepGoal: 8, weightGoal: null,
      dailyBudget: 40, currency: '€', focusMinutes: 25, glass: 250,
    },
    days: {},        // 'YYYY-MM-DD' -> day object
    goals: [],       // {id, title, area, why, done, tasks:[{id,t,done}]}
    wheel: {},       // area -> 1..10 (current)
    wheelHistory: [],// [{date, scores}]
    vision: '',      // where I want to be
  });

  let db;
  try { db = Object.assign(defaults(), JSON.parse(localStorage.getItem(KEY) || '{}')); }
  catch { db = defaults(); }
  db.settings = Object.assign(defaults().settings, db.settings);
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(db)); } catch {} };

  // ---------- helpers ----------
  const $ = (s, el = document) => el.querySelector(s);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const uid = () => Math.random().toString(36).slice(2, 10);
  const pad = (n) => String(n).padStart(2, '0');
  const keyOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const todayKey = () => keyOf(new Date());
  const num = (v) => { const n = parseFloat(String(v).replace(',', '.')); return isFinite(n) ? n : null; };
  const pct = (v, g) => Math.max(0, Math.min(100, g ? (v / g) * 100 : 0));
  const money = (n) => `${db.settings.currency}${(Math.round(n * 100) / 100).toFixed(2)}`;
  const fmtMin = (m) => m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`;

  function day(k = todayKey()) {
    if (!db.days[k]) db.days[k] = { water: 0, steps: null, weight: null, sleep: null, mood: null, energy: null,
      time: {}, spend: [], wins: '', gratitude: '', habits: {}, source: {} };
    const d = db.days[k];
    d.time ||= {}; d.spend ||= []; d.habits ||= {}; d.source ||= {};
    return d;
  }
  function lastDays(n) {
    const out = [];
    for (let i = n - 1; i >= 0; i--) { const d = new Date(); d.setDate(d.getDate() - i); out.push(keyOf(d)); }
    return out;
  }
  function toast(msg) {
    const t = $('#toast'); t.textContent = msg; t.hidden = false;
    clearTimeout(toast._t); toast._t = setTimeout(() => (t.hidden = true), 2400);
  }
  function spark(values, color = 'var(--accent)') {
    const pts = values.map((v, i) => [i, v]).filter(p => p[1] != null);
    if (pts.length < 2) return `<div class="muted small">Not enough data yet — keep logging.</div>`;
    const ys = pts.map(p => p[1]); const min = Math.min(...ys), max = Math.max(...ys);
    const W = 300, H = 56, n = values.length - 1 || 1;
    const sx = (i) => (i / n) * (W - 8) + 4;
    const sy = (v) => max === min ? H / 2 : H - 6 - ((v - min) / (max - min)) * (H - 12);
    const d = pts.map((p, i) => `${i ? 'L' : 'M'}${sx(p[0]).toFixed(1)},${sy(p[1]).toFixed(1)}`).join(' ');
    const last = pts[pts.length - 1];
    return `<svg class="spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
      <path d="${d}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>
      <circle cx="${sx(last[0])}" cy="${sy(last[1])}" r="3.5" fill="${color}"/></svg>`;
  }

  // ---------- Apple Health / Shortcut import ----------
  // Accepts text like: "lifeos:steps=8432;weight=72.4;sleep=7.5;water=1500"
  // (also "steps: 8432", newlines, commas as decimal separators).
  const FIELD_ALIASES = { steps: 'steps', weight: 'weight', sleep: 'sleep', water: 'water',
    kg: 'weight', mass: 'weight', bodymass: 'weight', hr: 'restingHr', restinghr: 'restingHr',
    active: 'activeKcal', activekcal: 'activeKcal', energy: 'activeKcal', exercise: 'exerciseMin', hrv: 'hrv' };
  function parseImport(text) {
    const out = {};
    String(text).replace(/^lifeos:/i, '').split(/[;\n&|]+/).forEach(part => {
      const m = part.match(/^\s*([a-z_]+)\s*[:=]\s*([-\d.,]+)/i);
      if (!m) return;
      const field = FIELD_ALIASES[m[1].toLowerCase().replace(/_/g, '')];
      const v = num(m[2]);
      if (field && v != null) out[field] = v;
    });
    return out;
  }
  function applyImport(data, k = todayKey()) {
    const d = day(k); const got = [];
    for (const [f, v] of Object.entries(data)) {
      if (f === 'water') { if (v > d.water) d.water = Math.round(v); }   // never lower manual water
      else if (f === 'sleep') d.sleep = v > 24 ? Math.round(v / 6) / 10 : v; // minutes -> hours
      else if (f === 'steps') d.steps = Math.round(v);
      else d[f] = v;
      d.source[f] = 'health'; got.push(f);
    }
    save(); return got;
  }
  async function syncFromClipboard() {
    try {
      const text = await navigator.clipboard.readText();
      const got = applyImport(parseImport(text));
      if (got.length) { toast(`Imported: ${got.join(', ')}`); render(); }
      else { toast('Clipboard had no Life OS data. Run the Health Shortcut first.'); go('settings'); }
    } catch {
      const text = prompt('Paste the text from your Health Shortcut:');
      if (text) { const got = applyImport(parseImport(text)); toast(got.length ? `Imported: ${got.join(', ')}` : 'Nothing recognised'); render(); }
    }
  }
  // URL import: /?steps=8000&weight=72.4  or  /?import=lifeos:steps=8000;weight=72.4
  (function importFromUrl() {
    const q = new URLSearchParams(location.search); if (![...q.keys()].length) return;
    const data = q.has('import') ? parseImport(q.get('import')) : parseImport([...q].map(([a, b]) => `${a}=${b}`).join(';'));
    const got = applyImport(data, q.get('date') || todayKey());
    history.replaceState(null, '', location.pathname);
    if (got.length) setTimeout(() => toast(`Imported from link: ${got.join(', ')}`), 300);
  })();

  // ---------- views ----------
  const views = {};
  const titles = { today: 'Today', focus: 'Focus', money: 'Money', goals: 'Goals & projects', life: 'My life', settings: 'More' };

  views.today = () => {
    const d = day(), s = db.settings;
    const timeTotal = Object.values(d.time).reduce((a, b) => a + b, 0);
    const moods = ['😞', '😕', '😐', '🙂', '😄'];
    return `
    <div class="card">
      <h2>Water <small>${d.water} / ${s.waterGoal} ml</small></h2>
      <div class="bar water"><i style="width:${pct(d.water, s.waterGoal)}%"></i></div>
      <div class="row" style="margin-top:8px">
        <button class="primary" data-act="water" data-v="${s.glass}">+ Glass (${s.glass} ml)</button>
        <button data-act="water" data-v="500">+500</button>
        <button data-act="water" data-v="-${s.glass}">−</button>
      </div>
    </div>

    <div class="grid2">
      <div class="card">
        <h2>Steps</h2>
        <div class="big">${d.steps != null ? d.steps.toLocaleString() : '—'}</div>
        <div class="bar good"><i style="width:${pct(d.steps || 0, s.stepGoal)}%"></i></div>
        <div class="muted small">goal ${s.stepGoal.toLocaleString()}${d.source.steps ? ' · from Health' : ''}</div>
      </div>
      <div class="card">
        <h2>Weight</h2>
        <div class="big">${d.weight != null ? d.weight + '<span class="small muted"> kg</span>' : '—'}</div>
        <div class="muted small">${s.weightGoal ? 'goal ' + s.weightGoal + ' kg' : 'set a goal in More'}${d.source.weight ? ' · from scale' : ''}</div>
      </div>
      <div class="card">
        <h2>Sleep</h2>
        <div class="big">${d.sleep != null ? d.sleep + '<span class="small muted"> h</span>' : '—'}</div>
        <div class="bar"><i style="width:${pct(d.sleep || 0, s.sleepGoal)}%"></i></div>
      </div>
      <div class="card">
        <h2>Spent today</h2>
        <div class="big">${money(d.spend.reduce((a, x) => a + x.amt, 0))}</div>
        ${budgetBar(d)}
      </div>
    </div>

    <div class="card" style="margin-top:12px">
      <h2>Quick log <small>manual entry</small></h2>
      <div class="inline3">
        <select id="qField"><option value="steps">Steps</option><option value="weight">Weight (kg)</option><option value="sleep">Sleep (h)</option></select>
        <input id="qVal" inputmode="decimal" placeholder="value">
        <button data-act="quick">Save</button>
      </div>
    </div>

    <div class="card">
      <h2>How do I feel?</h2>
      <div class="mood">${moods.map((m, i) => `<button class="${d.mood === i + 1 ? 'on' : ''}" data-act="mood" data-v="${i + 1}">${m}</button>`).join('')}</div>
      <label>Energy: <b>${d.energy ?? '—'}</b>/10</label>
      <input type="range" min="1" max="10" value="${d.energy ?? 5}" data-change="energy">
    </div>

    <div class="card">
      <h2>Where my time went <small>${fmtMin(timeTotal)}</small></h2>
      ${TIME_CATS.map(([k, label]) => `
        <div class="row between" style="padding:4px 0">
          <span>${label} <span class="muted small">${fmtMin(d.time[k] || 0)}</span></span>
          <span class="row">
            <button class="chip" data-act="time" data-k="${k}" data-v="-15">−15</button>
            <button class="chip" data-act="time" data-k="${k}" data-v="15">+15</button>
            <button class="chip" data-act="time" data-k="${k}" data-v="60">+1h</button>
          </span>
        </div>`).join('')}
    </div>

    <div class="card">
      <h2>Habits</h2>
      ${habitList(d)}
    </div>

    <div class="card">
      <h2>Reflection</h2>
      <label>Today's win</label>
      <textarea data-change="wins" placeholder="One thing that went well…">${esc(d.wins)}</textarea>
      <label>Grateful for</label>
      <textarea data-change="gratitude" placeholder="Something or someone…">${esc(d.gratitude)}</textarea>
    </div>`;
  };

  const HABITS = ['Meditate', 'Read 20 min', 'Workout', 'No phone in bed', 'Quality time with partner', 'Plan tomorrow'];
  function habitList(d) {
    const list = db.settings.habits || HABITS;
    return `<ul class="list">${list.map(h => `
      <li class="${d.habits[h] ? 'done' : ''}"><input type="checkbox" data-habit="${esc(h)}" ${d.habits[h] ? 'checked' : ''}><span>${esc(h)}</span></li>`).join('')}
    </ul><div class="muted small" style="margin-top:6px">Edit the habit list in More.</div>`;
  }
  function budgetBar(d) {
    const spent = d.spend.reduce((a, x) => a + x.amt, 0), b = db.settings.dailyBudget;
    const cls = spent > b ? 'bad' : spent > b * 0.8 ? 'warn' : 'good';
    return `<div class="bar ${cls}"><i style="width:${pct(spent, b)}%"></i></div>
      <div class="muted small">${spent <= b ? money(b - spent) + ' left' : money(spent - b) + ' over'} of ${money(b)}</div>`;
  }

  // Focus timer (Pomodoro). State kept in memory + endsAt so it survives tab switches.
  const focus = { endsAt: null, running: false, label: 'deep', remaining: null, iv: null };
  views.focus = () => {
    const mins = db.settings.focusMinutes;
    const rem = focus.running ? Math.max(0, focus.endsAt - Date.now()) : (focus.remaining ?? mins * 60000);
    const todayMin = day().time.deep || 0;
    const week = lastDays(7).reduce((a, k) => a + ((db.days[k]?.time?.deep) || 0), 0);
    return `
    <div class="card center">
      <div class="row" style="justify-content:center">
        ${[15, 25, 50, 90].map(m => `<button class="chip ${mins === m ? 'on' : ''}" data-act="fmins" data-v="${m}">${m}m</button>`).join('')}
      </div>
      <div class="timer" id="timer">${clock(rem)}</div>
      <div class="row" style="justify-content:center">
        <select id="fLabel" style="width:auto">${TIME_CATS.map(([k, l]) => `<option value="${k}" ${focus.label === k ? 'selected' : ''}>${l}</option>`).join('')}</select>
        <button class="primary" data-act="fstart">${focus.running ? 'Pause' : 'Start focus'}</button>
        <button data-act="freset">Reset</button>
      </div>
      <p class="muted small">Tip: turn on iPhone Focus mode (Do Not Disturb) while the timer runs. Finished sessions are added to "Where my time went".</p>
    </div>
    <div class="grid2">
      <div class="card"><h2>Deep work today</h2><div class="big">${fmtMin(todayMin)}</div></div>
      <div class="card"><h2>Last 7 days</h2><div class="big">${fmtMin(week)}</div></div>
    </div>`;
  };
  const clock = (ms) => { const t = Math.ceil(ms / 1000); return `${pad(Math.floor(t / 60))}:${pad(t % 60)}`; };
  function tick() {
    const rem = focus.endsAt - Date.now();
    const el = $('#timer'); if (el) el.textContent = clock(Math.max(0, rem));
    document.title = focus.running ? `${clock(Math.max(0, rem))} · Life OS` : 'Life OS';
    if (rem <= 0) {
      clearInterval(focus.iv); focus.running = false; focus.remaining = null;
      const d = day(); d.time[focus.label] = (d.time[focus.label] || 0) + db.settings.focusMinutes; save();
      if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
      toast(`Session done! +${db.settings.focusMinutes} min logged`); document.title = 'Life OS';
      if (current === 'focus') render();
    }
  }

  views.money = () => {
    const d = day(), s = db.settings;
    const month = lastDays(31).filter(k => k.slice(0, 7) === todayKey().slice(0, 7));
    const monthSpent = month.reduce((a, k) => a + (db.days[k]?.spend || []).reduce((x, y) => x + y.amt, 0), 0);
    const byCat = {};
    month.forEach(k => (db.days[k]?.spend || []).forEach(x => byCat[x.cat] = (byCat[x.cat] || 0) + x.amt));
    const daysInMonth = new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).getDate();
    const monthBudget = s.dailyBudget * daysInMonth;
    const investMe = (byCat['Self-growth'] || 0) + (byCat['Health'] || 0);
    return `
    <div class="card">
      <h2>Today <small>budget ${money(s.dailyBudget)}/day</small></h2>
      ${budgetBar(d)}
      <div class="inline3" style="margin-top:10px">
        <input id="sAmt" inputmode="decimal" placeholder="amount">
        <select id="sCat">${SPEND_CATS.map(c => `<option>${c}</option>`).join('')}</select>
        <button class="primary" data-act="spend">Add</button>
      </div>
      <input id="sNote" placeholder="note (optional)" style="margin-top:8px">
      <ul class="list" style="margin-top:8px">${d.spend.map((x, i) => `
        <li><span>${money(x.amt)}</span><span class="muted small">${esc(x.cat)}${x.note ? ' · ' + esc(x.note) : ''}</span>
        <button class="x" data-act="unspend" data-i="${i}">✕</button></li>`).join('') || '<li class="muted small">No spending logged today.</li>'}</ul>
    </div>
    <div class="card">
      <h2>This month <small>${money(monthSpent)} / ${money(monthBudget)}</small></h2>
      <div class="bar ${monthSpent > monthBudget ? 'bad' : 'good'}"><i style="width:${pct(monthSpent, monthBudget)}%"></i></div>
      <ul class="list" style="margin-top:8px">${Object.entries(byCat).sort((a, b) => b[1] - a[1]).map(([c, v]) => `
        <li><span>${esc(c)}</span><span class="spacer"></span><b>${money(v)}</b></li>`).join('') || '<li class="muted small">Nothing yet this month.</li>'}</ul>
    </div>
    <div class="card">
      <h2>Invested in myself <small>this month</small></h2>
      <div class="big">${money(investMe)}</div>
      <div class="muted small">Spending tagged Self-growth + Health. Aim for something every month — books, courses, gym, therapy.</div>
    </div>`;
  };

  views.goals = () => `
    <div class="card">
      <h2>Where I want to be</h2>
      <textarea data-change="vision" placeholder="In 1–3 years I am… (health, love, money, work, where I live, how I feel)">${esc(db.vision)}</textarea>
    </div>
    <div class="card">
      <h2>New goal / project</h2>
      <input id="gTitle" placeholder="e.g. Run a half marathon, Save €5,000, Launch my side project">
      <div class="inline" style="margin-top:8px">
        <select id="gArea">${AREAS.map(([k, l]) => `<option value="${k}">${l}</option>`).join('')}</select>
        <button class="primary" data-act="addgoal">Add</button>
      </div>
      <input id="gWhy" placeholder="Why does this matter to me?" style="margin-top:8px">
    </div>
    ${db.goals.map(g => {
      const done = g.tasks.filter(t => t.done).length, total = g.tasks.length;
      return `<div class="card">
        <h2><span>${g.done ? '✅ ' : ''}${esc(g.title)}</span><small>${esc(AREAS.find(a => a[0] === g.area)?.[1] || '')}</small></h2>
        ${g.why ? `<div class="muted small">Why: ${esc(g.why)}</div>` : ''}
        <div class="bar"><i style="width:${total ? (done / total) * 100 : 0}%"></i></div>
        <div class="muted small">${done}/${total} steps</div>
        <ul class="list">${g.tasks.map(t => `
          <li class="${t.done ? 'done' : ''}"><input type="checkbox" data-task="${g.id}:${t.id}" ${t.done ? 'checked' : ''}><span>${esc(t.t)}</span>
          <button class="x" data-act="deltask" data-g="${g.id}" data-t="${t.id}">✕</button></li>`).join('')}</ul>
        <div class="inline" style="margin-top:8px">
          <input placeholder="Next step…" data-newtask="${g.id}">
          <button data-act="addtask" data-g="${g.id}">+</button>
        </div>
        <div class="row" style="margin-top:8px">
          <button class="chip" data-act="togglegoal" data-g="${g.id}">${g.done ? 'Reopen' : 'Mark achieved'}</button>
          <button class="chip" data-act="delgoal" data-g="${g.id}">Delete</button>
        </div>
      </div>`;
    }).join('')}`;

  views.life = () => {
    const keys = lastDays(30);
    const col = (f) => keys.map(k => db.days[k]?.[f] ?? null);
    const timeSum = (cat) => keys.reduce((a, k) => a + (db.days[k]?.time?.[cat] || 0), 0);
    const avg = (arr) => { const v = arr.filter(x => x != null); return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null; };
    const w = col('weight').filter(x => x != null);
    const wDelta = w.length > 1 ? (w[w.length - 1] - w[0]).toFixed(1) : null;
    return `
    <div class="card">
      <h2>Life balance wheel <small>rate 1–10</small></h2>
      ${wheelSvg(db.wheel)}
      ${AREAS.map(([k, l]) => `
        <label>${l}: <b>${db.wheel[k] ?? '—'}</b></label>
        <input type="range" min="1" max="10" value="${db.wheel[k] ?? 5}" data-wheel="${k}">`).join('')}
      <button style="margin-top:10px" data-act="snapwheel">Save this month's snapshot</button>
      ${db.wheelHistory.length ? `<div class="muted small" style="margin-top:6px">Last snapshot: ${db.wheelHistory[db.wheelHistory.length - 1].date}</div>` : ''}
    </div>
    <div class="card"><h2>Weight · 30 days <small>${wDelta != null ? (wDelta > 0 ? '+' : '') + wDelta + ' kg' : ''}</small></h2>${spark(col('weight'))}</div>
    <div class="card"><h2>Steps · 30 days <small>avg ${Math.round(avg(col('steps')) || 0).toLocaleString()}</small></h2>${spark(col('steps'), 'var(--good)')}</div>
    <div class="card"><h2>Water · 30 days <small>avg ${Math.round(avg(col('water').map(x => x || null)) || 0)} ml</small></h2>${spark(col('water'), 'var(--water)')}</div>
    <div class="card"><h2>Sleep · 30 days <small>avg ${(avg(col('sleep')) || 0).toFixed(1)} h</small></h2>${spark(col('sleep'))}</div>
    <div class="card"><h2>Mood · 30 days</h2>${spark(col('mood'), 'var(--warn)')}</div>
    <div class="card">
      <h2>Time invested · 30 days</h2>
      <ul class="list">${TIME_CATS.map(([k, l]) => `<li><span>${l}</span><span class="spacer"></span><b>${fmtMin(timeSum(k))}</b></li>`).join('')}</ul>
    </div>`;
  };
  function wheelSvg(scores) {
    const n = AREAS.length, R = 120, C = 150;
    const pt = (i, r) => { const a = (Math.PI * 2 * i) / n - Math.PI / 2; return [C + Math.cos(a) * r, C + Math.sin(a) * r]; };
    const rings = [2, 4, 6, 8, 10].map(v => `<polygon points="${AREAS.map((_, i) => pt(i, R * v / 10).join(',')).join(' ')}" fill="none" stroke="var(--line)"/>`).join('');
    const shape = AREAS.map(([k], i) => pt(i, R * (scores[k] || 0) / 10).join(',')).join(' ');
    const labels = AREAS.map(([, l], i) => { const [x, y] = pt(i, R + 18); return `<text x="${x}" y="${y}" font-size="10" fill="var(--muted)" text-anchor="middle" dominant-baseline="middle">${esc(l.split(' ')[0])}</text>`; }).join('');
    return `<svg class="wheel" viewBox="0 0 300 300">${rings}<polygon points="${shape}" fill="color-mix(in srgb, var(--accent) 30%, transparent)" stroke="var(--accent)" stroke-width="2"/>${labels}</svg>`;
  }

  views.settings = () => {
    const s = db.settings;
    const appUrl = location.origin + location.pathname;
    return `
    <div class="card">
      <h2>My targets</h2>
      ${[['waterGoal', 'Water goal (ml)'], ['glass', 'Glass size (ml)'], ['stepGoal', 'Step goal'], ['sleepGoal', 'Sleep goal (h)'],
         ['weightGoal', 'Target weight (kg)'], ['dailyBudget', 'Daily spending budget'], ['focusMinutes', 'Focus session (min)']]
        .map(([k, l]) => `<label>${l}</label><input inputmode="decimal" data-setting="${k}" value="${s[k] ?? ''}">`).join('')}
      <label>Currency symbol</label><input data-setting="currency" value="${esc(s.currency)}">
      <label>Daily habits (one per line)</label>
      <textarea data-setting="habits">${esc((s.habits || HABITS).join('\n'))}</textarea>
    </div>

    <div class="card">
      <h2>Connect Apple Health, Apple Watch & Xiaomi scale</h2>
      <p class="small">A website can't read Apple Health directly, so an iPhone <b>Shortcut</b> grabs today's numbers and hands them to this app.</p>
      <ol class="steps small">
        <li><b>Xiaomi scale:</b> in the <i>Mi Fitness</i> (or <i>Zepp Life</i>) app → Profile → Apple Health → turn on <i>Weight</i>. Your weigh-ins now land in Apple Health. Apple Watch steps & sleep are already there.</li>
        <li>Open <b>Shortcuts</b> → new shortcut named <i>Life OS Sync</i>. Add <i>Find Health Samples</i> → Steps, Today → <i>Calculate Statistics</i> (Sum). Repeat for Weight (Latest), Sleep (Last night, Sum of hours).</li>
        <li>Add a <b>Text</b> action: <code>lifeos:steps=[Steps];weight=[Weight];sleep=[Sleep]</code> (insert the variables), then <b>Copy to Clipboard</b>.</li>
        <li>Optional: add <b>Open URL</b> → <code>${esc(appUrl)}</code> so it jumps back here.</li>
        <li>Shortcuts → Automation → <i>Time of day</i> (e.g. 21:00, daily, run immediately) → run <i>Life OS Sync</i>.</li>
        <li>Tap <b>⟳ Health</b> at the top of this app — it reads the clipboard and fills in today.</li>
      </ol>
      <p class="muted small">Also works on a computer with a link: <code>${esc(appUrl)}?steps=8000&amp;weight=72.4</code></p>
      <button data-act="sync">Import from clipboard now</button>
    </div>

    <div class="card">
      <h2>Install on your phone</h2>
      <p class="small">iPhone: open this page in <b>Safari</b> → Share → <b>Add to Home Screen</b>. It then opens full-screen like a real app. Android: Chrome menu → Install app.</p>
    </div>

    <div class="card">
      <h2>Backup</h2>
      <p class="muted small">Data is stored only on this device. Export regularly, or import a backup on another device.</p>
      <div class="row">
        <button data-act="export">Export backup</button>
        <button data-act="importfile">Import backup</button>
        <button data-act="wipe">Erase all</button>
      </div>
      <input type="file" id="fileIn" accept="application/json" hidden>
    </div>`;
  };

  // ---------- render & routing ----------
  let current = 'today';
  function render() {
    $('#view').innerHTML = views[current]();
    $('#viewTitle').textContent = titles[current];
    $('#dateLabel').textContent = new Date().toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
    document.querySelectorAll('.tabbar button').forEach(b => b.classList.toggle('active', b.dataset.tab === current));
  }
  function go(tab) { current = tab; try { sessionStorage.setItem('lifeos.tab', tab); } catch {} render(); scrollTo(0, 0); }
  try { const t = sessionStorage.getItem('lifeos.tab'); if (t && views[t]) current = t; } catch {}

  document.querySelector('.tabbar').addEventListener('click', e => { const b = e.target.closest('button'); if (b) go(b.dataset.tab); });
  $('#syncBtn').addEventListener('click', syncFromClipboard);

  // ---------- actions ----------
  const findGoal = (id) => db.goals.find(g => g.id === id);
  const actions = {
    water: (b) => { const d = day(); d.water = Math.max(0, d.water + Number(b.dataset.v)); },
    mood: (b) => { day().mood = Number(b.dataset.v); },
    time: (b) => { const d = day(), k = b.dataset.k; d.time[k] = Math.max(0, (d.time[k] || 0) + Number(b.dataset.v)); },
    quick: () => {
      const f = $('#qField').value, v = num($('#qVal').value); if (v == null) return toast('Enter a number');
      const d = day(); d[f] = f === 'steps' ? Math.round(v) : v; d.source[f] = 'manual'; toast('Saved');
    },
    spend: () => {
      const amt = num($('#sAmt').value); if (amt == null || amt <= 0) return toast('Enter an amount');
      day().spend.push({ amt, cat: $('#sCat').value, note: $('#sNote').value.trim(), at: Date.now() });
    },
    unspend: (b) => { day().spend.splice(Number(b.dataset.i), 1); },
    addgoal: () => {
      const title = $('#gTitle').value.trim(); if (!title) return toast('Give your goal a name');
      db.goals.unshift({ id: uid(), title, area: $('#gArea').value, why: $('#gWhy').value.trim(), done: false, tasks: [] });
    },
    addtask: (b) => {
      const inp = document.querySelector(`[data-newtask="${b.dataset.g}"]`); const t = inp.value.trim(); if (!t) return;
      findGoal(b.dataset.g).tasks.push({ id: uid(), t, done: false });
    },
    deltask: (b) => { const g = findGoal(b.dataset.g); g.tasks = g.tasks.filter(t => t.id !== b.dataset.t); },
    togglegoal: (b) => { const g = findGoal(b.dataset.g); g.done = !g.done; if (g.done) toast('🎉 Goal achieved!'); },
    delgoal: (b) => { if (confirm('Delete this goal?')) db.goals = db.goals.filter(g => g.id !== b.dataset.g); },
    snapwheel: () => { db.wheelHistory.push({ date: todayKey(), scores: { ...db.wheel } }); toast('Snapshot saved'); },
    fmins: (b) => { if (focus.running) return; db.settings.focusMinutes = Number(b.dataset.v); focus.remaining = null; },
    fstart: () => {
      focus.label = $('#fLabel').value;
      if (focus.running) { focus.remaining = focus.endsAt - Date.now(); focus.running = false; clearInterval(focus.iv); }
      else {
        focus.endsAt = Date.now() + (focus.remaining ?? db.settings.focusMinutes * 60000);
        focus.running = true; clearInterval(focus.iv); focus.iv = setInterval(tick, 500);
      }
    },
    freset: () => { clearInterval(focus.iv); focus.running = false; focus.remaining = null; document.title = 'Life OS'; },
    sync: () => { syncFromClipboard(); return 'norender'; },
    export: () => {
      const blob = new Blob([JSON.stringify(db, null, 2)], { type: 'application/json' });
      const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `life-os-backup-${todayKey()}.json`; a.click();
      return 'norender';
    },
    importfile: () => { $('#fileIn').click(); return 'norender'; },
    wipe: () => { if (confirm('Erase ALL data on this device? Export a backup first.')) { db = defaults(); } },
  };
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    const r = actions[b.dataset.act]?.(b);
    save(); if (r !== 'norender') render();
  });

  // inputs that save without re-rendering (so typing isn't interrupted)
  document.addEventListener('input', e => {
    const el = e.target;
    if (el.dataset.change) {
      const f = el.dataset.change;
      if (f === 'vision') db.vision = el.value;
      else if (f === 'energy') { day().energy = Number(el.value); el.previousElementSibling.querySelector('b').textContent = el.value; }
      else day()[f] = el.value;
      save();
    } else if (el.dataset.wheel) {
      db.wheel[el.dataset.wheel] = Number(el.value); save();
      el.previousElementSibling.querySelector('b').textContent = el.value;
      const svg = $('svg.wheel'); if (svg) svg.outerHTML = wheelSvg(db.wheel);
    } else if (el.dataset.setting) {
      const k = el.dataset.setting;
      if (k === 'currency') db.settings.currency = el.value || '€';
      else if (k === 'habits') db.settings.habits = el.value.split('\n').map(x => x.trim()).filter(Boolean);
      else db.settings[k] = num(el.value) ?? (k === 'weightGoal' ? null : db.settings[k]);
      save();
    }
  });
  document.addEventListener('change', e => {
    const el = e.target;
    if (el.dataset.habit) { const d = day(); d.habits[el.dataset.habit] = el.checked; save(); render(); }
    else if (el.dataset.task) {
      const [gid, tid] = el.dataset.task.split(':'); const t = findGoal(gid).tasks.find(x => x.id === tid);
      t.done = el.checked; save(); render();
    } else if (el.id === 'fileIn' && el.files[0]) {
      el.files[0].text().then(txt => {
        try { db = Object.assign(defaults(), JSON.parse(txt)); save(); render(); toast('Backup restored'); }
        catch { toast('That file is not a Life OS backup'); }
      });
    }
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Enter' && e.target.dataset.newtask) document.querySelector(`[data-act="addtask"][data-g="${e.target.dataset.newtask}"]`)?.click();
  });
  // refresh "today" when the app comes back to the foreground on a new day
  document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });

  render();
  if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('sw.js').catch(() => {});
})();
