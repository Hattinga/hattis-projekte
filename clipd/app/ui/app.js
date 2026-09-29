// clipd window. Talks to the Rust side through invoke() and its events.
const { invoke, convertFileSrc } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (id) => document.getElementById(id);
const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};

const ICON = {
  all: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>',
  game: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M6 9h4M8 7v4M15 10h.01M18 8h.01"/><path d="M7 4h10a5 5 0 0 1 4.9 6l-1 5.2a3 3 0 0 1-5.1 1.5L14 15h-4l-1.8 1.7a3 3 0 0 1-5.1-1.5L2.1 10A5 5 0 0 1 7 4z"/></svg>',
  star: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>',
  starFill: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>',
  desktop: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/></svg>',
  play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.5v15a1 1 0 0 0 1.5.9l12-7.5a1 1 0 0 0 0-1.8l-12-7.5A1 1 0 0 0 7 4.5z"/></svg>',
  pause: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4.5" height="16" rx="1.2"/><rect x="13.5" y="4" width="4.5" height="16" rx="1.2"/></svg>',
  ok: '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-1.2 14.2-4-4 1.4-1.4 2.6 2.6 5.6-5.6 1.4 1.4-7 7z"/>',
  fail: '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/>',
};

// ---------- formatting ----------

const pad = (n) => String(n).padStart(2, '0');
function clock(secs) {
  secs = Math.max(0, secs || 0);
  const m = Math.floor(secs / 60), s = Math.floor(secs % 60);
  return m >= 60 ? `${Math.floor(m / 60)}:${pad(m % 60)}:${pad(s)}` : `${m}:${pad(s)}`;
}
function clockExact(secs) {
  const tenth = Math.floor((secs % 1) * 10);
  return `${clock(secs)},${tenth}`;
}
function when(unix) {
  const d = new Date(unix * 1000), now = new Date();
  const time = d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
  const day = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diff = Math.round((day(now) - day(d)) / 86400000);
  if (diff === 0) return `Heute, ${time}`;
  if (diff === 1) return `Gestern, ${time}`;
  const opts = { day: 'numeric', month: 'short' };
  if (d.getFullYear() !== now.getFullYear()) opts.year = 'numeric';
  return `${d.toLocaleDateString('de-DE', opts)}, ${time}`;
}
const size = (bytes) =>
  bytes >= 1e9 ? `${(bytes / 1e9).toLocaleString('de-DE', { maximumFractionDigits: 1 })} GB`
  : `${(bytes / 1e6).toLocaleString('de-DE', { maximumFractionDigits: 1 })} MB`;
const keyLabel = (spec) =>
  (spec || '').split('+').map((p) => ({ ctrl: 'Strg', control: 'Strg', shift: 'Umschalt', win: 'Win', space: 'Leertaste' }[p.trim().toLowerCase()] || p.trim())).join('+');
const displayName = (name) => {
  const m = /^clip-(\d{4})-(\d\d)-(\d\d)_(\d\d)-(\d\d)-(\d\d)(.*)$/.exec(name);
  return m ? `Clip ${m[4]}:${m[5]}:${m[6]}${m[7]}` : name;
};

// ---------- toast and alert ----------

let toastTimer;
function toast(text, { error = false, action, onAction } = {}) {
  const t = $('toast');
  $('toast-icon').innerHTML = error ? ICON.fail : ICON.ok;
  t.classList.toggle('error', error);
  $('toast-text').textContent = text;
  const b = $('toast-action');
  b.classList.toggle('hidden', !action);
  if (action) {
    b.textContent = action;
    b.onclick = () => { onAction(); t.classList.remove('show'); };
  }
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), error ? 6000 : 3800);
}

function confirmBox(title, text, ok) {
  return new Promise((resolve) => {
    $('alert-title').textContent = title;
    $('alert-text').textContent = text;
    const okBtn = $('alert-ok');
    okBtn.textContent = ok;
    okBtn.className = 'btn primary';
    okBtn.style.background = 'var(--red)';
    const close = (v) => { $('alert').classList.add('hidden'); resolve(v); };
    okBtn.onclick = () => close(true);
    $('alert-cancel').onclick = () => close(false);
    $('alert').classList.remove('hidden');
    okBtn.focus();
  });
}

const fail = (e) => toast(String(e), { error: true });

// ---------- status ----------

let status = null, statusShown = '';
async function refreshStatus(s) {
  status = s || (await invoke('status'));
  // Asked every second, but mostly nothing has changed; then the page stays as it is.
  const key = JSON.stringify(status);
  if (key === statusShown) return;
  statusShown = key;
  const dot = document.querySelector('#status .dot');
  const text = $('status-text'), sub = $('status-sub');
  const rec = status.recordingSecs;
  if (status.state === 'downloading') {
    dot.className = 'dot gray';
    text.textContent = `ffmpeg wird geladen · ${Math.round((status.download || 0) * 100)} %`;
    sub.textContent = 'Nur beim ersten Start, rund 90 MB';
  } else if (status.state === 'starting') {
    dot.className = 'dot gray';
    text.textContent = 'Startet …';
    sub.textContent = 'Grafikkarte und Ton werden eingerichtet';
  } else if (status.state === 'running' && rec != null) {
    dot.className = 'dot red';
    text.textContent = `Aufnahme ${clock(rec)}`;
    sub.textContent = `${keyLabel(status.recordHotkey)} beendet sie`;
  } else if (status.state === 'running') {
    dot.className = 'dot green';
    text.textContent = 'Puffer läuft';
    sub.innerHTML = '';
    sub.append(`${status.codec} · ${status.fps} fps · ${status.gpu}`, el('br'), `${keyLabel(status.hotkey)} speichert ${status.clipSecs} s`);
  } else {
    dot.className = 'dot';
    text.textContent = 'Keine Aufnahme';
    sub.textContent = status.problem ? 'Siehe Hinweis oben' : '';
  }
  const running = status.state === 'running';
  $('save').disabled = !running;
  $('rec').disabled = !running;
  $('rec').classList.toggle('recording', rec != null);
  $('rec-label').textContent = rec != null ? clock(rec) : 'Aufnahme';

  const banner = $('banner');
  const problem = status.problem, warning = status.warning;
  banner.classList.toggle('hidden', !problem && !warning);
  banner.classList.toggle('error', !!problem);
  $('banner-text').textContent = problem || warning || '';
  $('banner-retry').classList.toggle('hidden', !problem);
  $('banner-settings').classList.toggle('hidden', !problem);
  $('empty-text').innerHTML = '';
  $('empty-text').append(
    'Drück ', el('kbd', '', keyLabel(status.hotkey)),
    ` während eines Spiels — clipd speichert die letzten ${status.clipSecs} Sekunden.`,
  );
}

// ---------- library ----------

let clips = [];
const FAVORITES = Symbol('favorites');
let filter = null; // null: all; FAVORITES; otherwise the game folder name
const metaCache = new Map();
const metaQueue = [];
let metaRunning = 0;

function meta(path) {
  if (metaCache.has(path)) return metaCache.get(path);
  const p = new Promise((resolve, reject) => metaQueue.push({ path, resolve, reject }));
  metaCache.set(path, p);
  pumpMeta();
  return p;
}
function pumpMeta() {
  // Two ffmpegs at a time: the thumbnails come quickly without starving the capture.
  while (metaRunning < 2 && metaQueue.length) {
    const job = metaQueue.shift();
    metaRunning++;
    invoke('meta', { path: job.path })
      .then(job.resolve, (e) => { metaCache.delete(job.path); job.reject(e); })
      .finally(() => { metaRunning--; pumpMeta(); });
  }
}

let clipsShown = '';
async function loadClips() {
  const list = await invoke('clips');
  // Every focus asks again; the grid is only rebuilt when something changed,
  // or the day did ("Heute" becomes "Gestern").
  const key = new Date().toDateString() + JSON.stringify(list);
  if (key === clipsShown) return;
  clipsShown = key;
  clips = list;
  renderNav();
  if (!$('detail').classList.contains('hidden')) return;
  renderGrid();
}

function games() {
  const counts = new Map();
  for (const c of clips) counts.set(c.game, (counts.get(c.game) || 0) + 1);
  return [...counts.entries()].sort((a, b) => (a[0] === 'Desktop') - (b[0] === 'Desktop') || a[0].localeCompare(b[0], 'de'));
}

function renderNav() {
  const nav = $('nav');
  nav.innerHTML = '';
  const item = (name, icon, count, value) => {
    const b = el('button');
    b.innerHTML = icon;
    b.append(el('span', 'name', name), el('span', 'count', String(count)));
    b.classList.toggle('active', filter === value);
    b.onclick = () => { filter = value; closeDetail(); renderNav(); renderGrid(); };
    nav.append(b);
  };
  item('Alle Clips', ICON.all, clips.length, null);
  const favs = clips.filter((c) => c.favorite).length;
  if (favs) item('Favoriten', ICON.star, favs, FAVORITES);
  for (const [game, count] of games()) {
    item(game || 'Ohne Ordner', game === 'Desktop' ? ICON.desktop : ICON.game, count, game);
  }
}

const observer = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    observer.unobserve(e.target);
    const card = e.target, path = card.dataset.path;
    meta(path).then((m) => {
      const img = card.querySelector('img');
      img.onload = () => img.classList.add('loaded');
      img.src = convertFileSrc(m.thumb);
      card.querySelector('.badge').textContent = clock(m.duration);
      card.querySelector('.badge').classList.remove('hidden');
    }).catch(() => {});
  }
}, { rootMargin: '200px' });

function renderGrid() {
  const lib = $('library');
  lib.innerHTML = '';
  const shown = filter === null ? clips : filter === FAVORITES ? clips.filter((c) => c.favorite) : clips.filter((c) => c.game === filter);
  $('title').textContent = filter === null ? 'Alle Clips' : filter === FAVORITES ? 'Favoriten' : (filter || 'Ohne Ordner');
  $('empty').classList.toggle('hidden', shown.length > 0);
  if (!shown.length) return;
  // Grouped by day, newest first.
  let day = null, grid = null;
  for (const c of shown) {
    const d = new Date(c.modified * 1000).toDateString();
    if (d !== day) {
      day = d;
      const label = when(c.modified).split(',')[0];
      lib.append(el('div', 'section-title', label));
      grid = el('div', 'grid');
      lib.append(grid);
    }
    const card = el('div', 'card');
    card.dataset.path = c.path;
    const thumb = el('div', 'thumb');
    thumb.append(el('img'), el('span', 'badge hidden'));
    if (c.favorite) { const s = el('span', 'fav'); s.innerHTML = ICON.starFill; thumb.append(s); }
    const sub = [c.game && filter === null ? c.game : null, size(c.bytes)].filter(Boolean).join(' · ');
    card.append(thumb, el('div', 'title', displayName(c.name)), el('div', 'sub', sub));
    card.onclick = () => openDetail(c);
    grid.append(card);
    observer.observe(card);
  }
}

// ---------- detail ----------

let current = null; // { clip, meta }
let trimIn = 0, trimOut = 0;
const video = $('video');

async function openDetail(clip) {
  current = { clip, meta: null };
  $('library').classList.add('hidden');
  $('empty').classList.add('hidden');
  $('detail').classList.remove('hidden');
  $('back').classList.remove('hidden');
  $('title').textContent = clip.game || 'Clip';
  $('name').value = clip.name;
  starButton();
  invoke('settings').then((s) => $('send').classList.toggle('hidden', !s.discord_webhook)).catch(() => {});
  $('novideo-text').textContent = 'Die Vorschau spielt nur H.264 ab — dieser Clip ist in einem anderen Format.';
  $('info').textContent = `${when(clip.modified)} · ${size(clip.bytes)}`;
  $('novideo').classList.add('hidden');
  $('strip').innerHTML = '';
  setBusy(null);
  $('vol-game').value = 100; $('vol-mic').value = 100;
  updateVolumes();
  video.src = convertFileSrc(clip.path);
  video.load();
  try {
    const m = await meta(clip.path);
    if (current?.clip !== clip) return;
    current.meta = m;
    trimIn = 0; trimOut = m.duration;
    const hasMic = m.audio_tracks > 1;
    $('mix-mic').classList.toggle('hidden', !hasMic);
    $('mix-hint').classList.toggle('hidden', !hasMic);
    $('info').textContent = `${when(clip.modified)} · ${clock(m.duration)} · ${m.width}×${m.height} · ${size(clip.bytes)}${hasMic ? ' · mit Mikrofon' : ''}`;
    drawTimeline();
    invoke('strip', { path: clip.path }).then((frames) => {
      if (current?.clip !== clip) return;
      const strip = $('strip');
      strip.innerHTML = '';
      for (const f of frames) { const i = el('img'); i.src = convertFileSrc(f); strip.append(i); }
    }).catch(() => {});
  } catch (e) { fail(e); }
}

function closeDetail() {
  if ($('detail').classList.contains('hidden')) return;
  video.pause();
  video.removeAttribute('src');
  video.load();
  current = null;
  $('detail').classList.add('hidden');
  $('library').classList.remove('hidden');
  $('back').classList.add('hidden');
  renderGrid();
}

const duration = () => current?.meta?.duration || video.duration || 0;

function drawTimeline() {
  const d = duration();
  if (!d) return;
  const w = $('timeline').clientWidth;
  const x = (t) => (t / d) * w;
  const a = x(trimIn), b = x(trimOut);
  Object.assign($('frame').style, { left: `${a}px`, width: `${Math.max(b - a, 24)}px` });
  Object.assign($('shade-l').style, { left: '0px', width: `${a}px` });
  Object.assign($('shade-r').style, { left: `${b}px`, width: `${w - b}px` });
  $('grip-in').style.left = `${a - 2}px`;
  $('grip-out').style.left = `${b - 14}px`;
  $('playhead').style.left = `${x(Math.min(Math.max(video.currentTime, 0), d))}px`;
  $('t-cur').textContent = clockExact(video.currentTime || 0);
  const sel = trimOut - trimIn;
  $('t-len').textContent = sel < d - 0.05 ? `Auswahl ${clockExact(sel)}` : clock(d);
}

function timeAt(ev) {
  const r = $('timeline').getBoundingClientRect();
  return Math.min(Math.max((ev.clientX - r.left) / r.width, 0), 1) * duration();
}

function drag(target, onMove) {
  target.addEventListener('pointerdown', (ev) => {
    ev.preventDefault();
    ev.stopPropagation();
    target.setPointerCapture(ev.pointerId);
    onMove(ev);
    const move = (e) => onMove(e);
    const up = () => { target.removeEventListener('pointermove', move); target.removeEventListener('pointerup', up); };
    target.addEventListener('pointermove', move);
    target.addEventListener('pointerup', up);
  });
}
drag($('timeline'), (e) => { video.currentTime = Math.min(Math.max(timeAt(e), trimIn), trimOut); drawTimeline(); });
drag($('grip-in'), (e) => { trimIn = Math.min(timeAt(e), trimOut - 0.5); video.currentTime = trimIn; drawTimeline(); });
drag($('grip-out'), (e) => { trimOut = Math.max(timeAt(e), trimIn + 0.5); video.currentTime = trimOut; drawTimeline(); });

function playIcon() { $('play').innerHTML = video.paused ? ICON.play : ICON.pause; }
function togglePlay() {
  if (video.paused) {
    if (video.currentTime >= trimOut - 0.05 || video.currentTime < trimIn) video.currentTime = trimIn;
    video.play().catch(() => {});
  } else video.pause();
}
$('play').onclick = togglePlay;
video.onclick = togglePlay;
// Keeps the playhead smooth between timeupdate events. Only while playing:
// a loop that asks for every frame keeps the window drawing 60 times a
// second even when nothing moves.
let ticking = false;
function tick() {
  if (current && !video.paused) { drawTimeline(); requestAnimationFrame(tick); } else ticking = false;
}
video.onplay = () => {
  playIcon();
  if (!ticking) { ticking = true; requestAnimationFrame(tick); }
};
video.onpause = playIcon;
video.ontimeupdate = () => {
  if (!video.paused && video.currentTime >= trimOut) { video.pause(); video.currentTime = trimOut; }
  drawTimeline();
};
video.onloadedmetadata = () => {
  if (current && !current.meta) { trimIn = 0; trimOut = video.duration; }
  drawTimeline();
};
video.onloadeddata = () => {
  // WebView2 decodes H.264 only; for HEVC or AV1 it plays the sound over black.
  if (!video.videoWidth) $('novideo').classList.remove('hidden');
};
video.onerror = () => $('novideo').classList.remove('hidden');
playIcon();
window.addEventListener('resize', drawTimeline);

function updateVolumes() {
  for (const id of ['vol-game', 'vol-mic']) {
    const r = $(id);
    r.style.setProperty('--p', `${r.value / 2}%`);
    $(`${id}-val`).textContent = `${r.value} %`;
  }
  video.volume = Math.min($('vol-game').value / 100, 1);
}
$('vol-game').oninput = updateVolumes;
$('vol-mic').oninput = updateVolumes;

const currentEdit = () => ({ start: trimIn, end: trimOut, game_volume: $('vol-game').value / 100, mic_volume: $('vol-mic').value / 100 });

function setBusy(text) {
  $('busy').classList.toggle('hidden', !text);
  $('exports').classList.toggle('hidden', !!text);
  if (text) { $('busy-text').textContent = text; $('busy-bar').style.width = '0%'; }
}
listen('export-progress', (e) => { $('busy-bar').style.width = `${Math.round(e.payload * 100)}%`; });

async function exportClip(target) {
  if (!current) return;
  const clip = current.clip;
  video.pause();
  setBusy({ discord: 'Für Discord verkleinern …', gif: 'GIF erstellen …', vertical: 'Hochformat erstellen …' }[target] || 'Zuschneiden …');
  try {
    const out = await invoke('export', { path: clip.path, edit: currentEdit(), target });
    await loadClips();
    const name = out.split(/[\\/]/).pop();
    if (target === 'discord') {
      await invoke('copy_file', { path: out }).catch(() => {});
      toast(`${name} liegt in der Zwischenablage — in Discord mit Strg+V einfügen`, { action: 'Zeigen', onAction: () => invoke('reveal', { path: out }) });
    } else {
      toast(`Gespeichert als ${name}`, { action: 'Öffnen', onAction: () => { const c = clips.find((x) => x.path === out); if (c) openDetail(c); } });
    }
  } catch (e) { fail(e); }
  setBusy(null);
}
$('trim').onclick = () => exportClip('trim');
$('more').onchange = () => { const v = $('more').value; $('more').selectedIndex = 0; if (v) exportClip(v); };
$('send').onclick = async () => {
  if (!current) return;
  video.pause();
  setBusy('An Discord senden …');
  try {
    await invoke('send_discord', { path: current.clip.path, edit: currentEdit() });
    await loadClips();
    toast('Im Discord-Kanal gepostet');
  } catch (e) { fail(e); }
  setBusy(null);
};
$('discord').onclick = () => exportClip('discord');

function starButton() {
  const on = !!current?.clip.favorite;
  $('star').innerHTML = on ? ICON.starFill : ICON.star;
  $('star').classList.toggle('on', on);
  $('star').title = on ? 'Kein Favorit mehr' : 'Favorit — wird beim Aufräumen nie gelöscht';
}
$('star').onclick = async () => {
  if (!current) return;
  const on = !current.clip.favorite;
  try {
    await invoke('set_favorite', { path: current.clip.path, on });
    current.clip = { ...current.clip, favorite: on };
    starButton();
    await loadClips();
  } catch (e) { fail(e); }
};

$('copy').onclick = () => current && invoke('copy_file', { path: current.clip.path })
  .then(() => toast('Datei kopiert — in Discord oder im Explorer mit Strg+V einfügen')).catch(fail);
$('reveal').onclick = () => current && invoke('reveal', { path: current.clip.path }).catch(fail);
$('open-external').onclick = () => current && invoke('open_external', { path: current.clip.path }).catch(fail);
$('delete').onclick = async () => {
  if (!current) return;
  const ok = await confirmBox('Clip löschen?', `„${displayName(current.clip.name)}“ wandert in den Papierkorb.`, 'Löschen');
  if (!ok) return;
  const path = current.clip.path;
  closeDetail();
  try { await invoke('delete', { path }); await loadClips(); toast('In den Papierkorb gelegt'); } catch (e) { fail(e); }
};

async function commitName() {
  if (!current) return;
  const name = $('name').value.trim();
  if (!name || name === current.clip.name) { $('name').value = current.clip.name; return; }
  try {
    const path = await invoke('rename', { path: current.clip.path, name });
    video.pause();
    const t = video.currentTime;
    current.clip = { ...current.clip, path, name: path.split(/[\\/]/).pop().replace(/\.mp4$/i, '') };
    $('name').value = current.clip.name;
    metaCache.delete(path);
    await loadClips();
    video.src = convertFileSrc(path);
    video.currentTime = t;
  } catch (e) { fail(e); $('name').value = current.clip.name; }
}
$('name').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') $('name').blur();
  if (e.key === 'Escape') { $('name').value = current.clip.name; $('name').blur(); }
  e.stopPropagation();
});
$('name').addEventListener('blur', commitName);

// ---------- toolbar ----------

$('back').onclick = closeDetail;
$('save').onclick = () => invoke('save_clip').catch(fail);
$('rec').onclick = () => invoke('toggle_recording').then(() => refreshStatus()).catch(fail);
$('folder').onclick = () => invoke('open_clips_folder').catch(fail);
$('gear').onclick = () => openSettings();
$('banner-retry').onclick = () => invoke('restart_capture');
$('banner-settings').onclick = () => openSettings();

listen('status', (e) => refreshStatus(e.payload));
listen('saved', async (e) => {
  await loadClips();
  const { path, secs, kind } = e.payload;
  const c = clips.find((x) => x.path === path);
  const what = kind === 'recording' ? 'Aufnahme' : 'Clip';
  toast(`${what} gespeichert${c && c.game ? ` · ${c.game}` : ''}${secs ? ` · ${clock(secs)}` : ''}`,
    { action: 'Ansehen', onAction: () => c && openDetail(c) });
});
listen('failed', (e) => fail(e.payload));

// ---------- settings ----------

let draft = null;
const QUALITY = [[18, 'Hoch'], [22, 'Ausgewogen'], [27, 'Sparsam']];

function segmented(options, value, onPick) {
  const s = el('div', 'seg');
  for (const [v, label] of options) {
    const b = el('button', v === value ? 'on' : '', label);
    b.onclick = () => { onPick(v); s.querySelectorAll('button').forEach((x) => x.classList.toggle('on', x === b)); };
    s.append(b);
  }
  return s;
}
function toggle(value, onChange) {
  const l = el('label', 'switch');
  const i = el('input'); i.type = 'checkbox'; i.checked = value;
  i.onchange = () => onChange(i.checked);
  l.append(i, el('span'));
  return l;
}
function popup(options, value, onChange) {
  const w = el('div', 'select');
  const s = el('select');
  for (const [v, label] of options) {
    const o = el('option', '', label); o.value = String(v);
    if (String(v) === String(value)) o.selected = true;
    s.append(o);
  }
  s.onchange = () => onChange(s.value);
  w.append(s);
  return w;
}
function row(label, control, small) {
  const r = el('div', 'row');
  const l = el('div', 'label', label);
  if (small) l.append(el('small', '', small));
  r.append(l);
  if (control) r.append(control);
  return r;
}
function group(title, rows, foot) {
  const frag = document.createDocumentFragment();
  frag.append(el('div', 'group-title', title));
  const g = el('div', 'group');
  rows.filter(Boolean).forEach((r) => g.append(r));
  frag.append(g);
  if (foot) frag.append(el('div', 'footnote', foot));
  return frag;
}

// Turns a key press into the spec the Rust side parses ("Ctrl+Alt+C").
function specOf(e) {
  const code = e.code;
  let key = null;
  if (/^Key[A-Z]$/.test(code)) key = code.slice(3);
  else if (/^Digit\d$/.test(code)) key = code.slice(5);
  else if (/^F\d{1,2}$/.test(code)) key = code;
  else key = { Space: 'Space', Insert: 'Insert', Delete: 'Delete', Home: 'Home', End: 'End', PageUp: 'PageUp', PageDown: 'PageDown', Pause: 'Pause', PrintScreen: 'Print', ArrowLeft: 'Left', ArrowRight: 'Right', ArrowUp: 'Up', ArrowDown: 'Down' }[code] || null;
  if (!key) return null;
  const mods = [e.ctrlKey && 'Ctrl', e.altKey && 'Alt', e.shiftKey && 'Shift', e.metaKey && 'Win'].filter(Boolean);
  if (!mods.length) return null;
  return [...mods, key].join('+');
}
function keycap(value, onChange, allowEmpty) {
  const b = el('button', 'keycap', value ? keyLabel(value) : 'Aus');
  b.onclick = () => {
    b.classList.add('listening');
    b.textContent = 'Tasten drücken …';
    const done = (spec) => {
      window.removeEventListener('keydown', onKey, true);
      b.classList.remove('listening');
      if (spec !== undefined) { value = spec; onChange(spec); }
      b.textContent = value ? keyLabel(value) : 'Aus';
    };
    const onKey = (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (e.key === 'Escape') return done();
      if (allowEmpty && (e.key === 'Backspace' || e.key === 'Delete') && !e.ctrlKey && !e.altKey) return done('');
      const spec = specOf(e);
      if (spec) done(spec);
    };
    window.addEventListener('keydown', onKey, true);
  };
  return b;
}

async function openSettings() {
  // All three at once; the devices take longest (one ffmpeg per monitor).
  const [settings, devices, autostart] = await Promise.all([
    invoke('settings'),
    invoke('devices').catch(() => ({ speakers: [], microphones: [], monitors: [] })),
    invoke('plugin:autostart|is_enabled').catch(() => false),
  ]);
  draft = settings;
  let autostartWanted = autostart;
  const body = $('settings-body');
  body.innerHTML = '';

  const monitors = devices.monitors.length ? devices.monitors.map(([i, s]) => [i, `Bildschirm ${i + 1} (${s.replace('x', '×')})`]) : [[0, 'Bildschirm 1']];
  const q = QUALITY.reduce((best, [v]) => (Math.abs(v - draft.quality) < Math.abs(best - draft.quality) ? v : best), 22);
  body.append(group('Aufnahme', [
    row('Bildschirm', popup(monitors, draft.monitor, (v) => (draft.monitor = +v))),
    row('Bildrate', segmented([[30, '30 fps'], [60, '60 fps']], draft.fps === 30 ? 30 : 60, (v) => (draft.fps = v))),
    row('Qualität', segmented(QUALITY, q, (v) => (draft.quality = v))),
    row('Format', segmented([['h264', 'H.264'], ['hevc', 'HEVC']], draft.codec, (v) => (draft.codec = v)), 'Nur H.264 spielt die Vorschau hier ab'),
    row('Grafikkarte', popup([['auto', 'Automatisch'], ['nvidia', 'NVIDIA'], ['amd', 'AMD']], draft.gpu, (v) => (draft.gpu = v))),
    row('Nur das Spielfenster', toggle(draft.capture === 'game', (v) => (draft.capture = v ? 'game' : 'screen')), 'Was über dem Spiel aufpoppt, landet in keinem Clip'),
    row('Mauszeiger aufnehmen', toggle(draft.draw_mouse, (v) => (draft.draw_mouse = v))),
  ]));

  const lengths = [10, 15, 20, 30, 45, 60, 90, 120, 180, 300];
  if (!lengths.includes(draft.clip_secs)) lengths.push(draft.clip_secs);
  lengths.sort((a, b) => a - b);
  const pathLabel = el('span', 'path', draft.out_dir || 'clips (neben clipd)');
  const change = el('button', 'btn', 'Ändern …');
  change.onclick = async () => {
    const dir = await invoke('plugin:dialog|open', { options: { directory: true, title: 'Ordner für Clips' } }).catch(() => null);
    if (dir) { draft.out_dir = dir; pathLabel.textContent = dir; }
  };
  const where = el('div', 'row');
  where.append(el('div', 'label', 'Speicherort'), pathLabel, change);
  const lengthLabel = (s) => (s < 60 ? `${s} Sekunden` : `${s / 60} ${s === 60 ? 'Minute' : 'Minuten'}`);
  const longs = [60, 90, 120, 180, 300, 600];
  if (!longs.includes(draft.long_clip_secs)) longs.push(draft.long_clip_secs);
  longs.sort((a, b) => a - b);
  body.append(group('Clips', [
    row('Clip-Länge', popup(lengths.map((s) => [s, lengthLabel(s)]), draft.clip_secs, (v) => (draft.clip_secs = +v))),
    row('Langer Clip', popup(longs.map((s) => [s, lengthLabel(s)]), draft.long_clip_secs, (v) => (draft.long_clip_secs = +v)), 'Auf eigener Taste, siehe Tastenkürzel'),
    row('Nach Spiel sortieren', toggle(draft.game_folders, (v) => (draft.game_folders = v)), 'Jedes Spiel bekommt einen eigenen Ordner'),
    row('Ton beim Speichern', toggle(draft.save_sound, (v) => (draft.save_sound = v))),
    row('Hinweis im Spiel', toggle(draft.overlay, (v) => (draft.overlay = v)), 'Kurz oben rechts, taucht in keinem Clip auf'),
    where,
  ]));

  const speakers = [['', 'Standardgerät'], ...devices.speakers.map((d) => [d, d])];
  if (draft.audio_device && !devices.speakers.includes(draft.audio_device)) speakers.push([draft.audio_device, draft.audio_device]);
  const mics = [['', 'Standardmikrofon'], ...devices.microphones.map((d) => [d, d])];
  if (draft.mic_device && !devices.microphones.includes(draft.mic_device)) mics.push([draft.mic_device, draft.mic_device]);
  body.append(group('Ton', [
    row('Spielton aufnehmen', toggle(draft.audio, (v) => (draft.audio = v))),
    row('Wiedergabegerät', popup(speakers, draft.audio_device, (v) => (draft.audio_device = v))),
    row('Mikrofon aufnehmen', toggle(draft.mic, (v) => (draft.mic = v)), 'Eigene Spur, beim Schneiden getrennt regelbar'),
    row('Mikrofon', popup(mics, draft.mic_device, (v) => (draft.mic_device = v))),
  ], 'Aufgenommen wird, was du hörst: Steht Windows auf 0 % oder stumm, bleiben die Clips still.'));

  body.append(group('Tastenkürzel', [
    row('Clip speichern', keycap(draft.hotkey, (v) => (draft.hotkey = v), false)),
    row('Aufnahme starten/beenden', keycap(draft.record_hotkey, (v) => (draft.record_hotkey = v), true), 'Rücktaste schaltet es ab'),
    row('Langen Clip speichern', keycap(draft.long_hotkey, (v) => (draft.long_hotkey = v), true), 'Rücktaste schaltet es ab'),
  ], 'Die Tasten gelten überall, auch wenn ein Spiel im Vordergrund ist.'));

  const days = [[0, 'Nie'], [7, 'Nach 7 Tagen'], [14, 'Nach 14 Tagen'], [30, 'Nach 30 Tagen'], [90, 'Nach 90 Tagen']];
  if (!days.some(([d]) => d === draft.keep_days)) days.push([draft.keep_days, `Nach ${draft.keep_days} Tagen`]);
  const gbs = [[0, 'Kein Limit'], [10, '10 GB'], [25, '25 GB'], [50, '50 GB'], [100, '100 GB']];
  if (!gbs.some(([g]) => g === draft.max_gb)) gbs.push([draft.max_gb, `${draft.max_gb} GB`]);
  body.append(group('Aufräumen', [
    row('Alte Clips löschen', popup(days, draft.keep_days, (v) => (draft.keep_days = +v))),
    row('Höchstens', popup(gbs, draft.max_gb, (v) => (draft.max_gb = +v)), 'Darüber gehen die ältesten'),
  ], 'Favoriten ⭐ bleiben immer. Aufgeräumt wird nach jedem neuen Clip.'));

  const hook = el('input', 'text-input');
  hook.type = 'url';
  hook.placeholder = 'https://discord.com/api/webhooks/…';
  hook.value = draft.discord_webhook || '';
  hook.spellcheck = false;
  hook.oninput = () => (draft.discord_webhook = hook.value.trim());
  const hookRow = el('div', 'row');
  hookRow.append(el('div', 'label', 'Discord-Webhook'), hook);
  body.append(group('Teilen', [hookRow], 'In Discord: Kanal bearbeiten → Integrationen → Webhooks → Webhook-URL kopieren. Dann schickt „An Discord senden“ den Clip direkt in diesen Kanal.'));

  body.append(group('Allgemein', [
    row('Mit Windows starten', toggle(autostart, (v) => (autostartWanted = v)), 'clipd startet unsichtbar im Infobereich'),
  ]));

  $('settings-save').onclick = async () => {
    draft.buffer_secs = Math.max(draft.buffer_secs, draft.clip_secs);
    try {
      await invoke('save_settings', { settings: draft });
      if (autostartWanted !== autostart) await invoke(autostartWanted ? 'plugin:autostart|enable' : 'plugin:autostart|disable');
      closeSettings();
      toast('Gesichert — die Aufnahme startet neu');
    } catch (e) { fail(e); }
  };
  $('sheet').classList.remove('hidden');
}
function closeSettings() { $('sheet').classList.add('hidden'); }
$('settings-cancel').onclick = closeSettings;

// ---------- keys ----------

window.addEventListener('keydown', (e) => {
  if (e.ctrlKey && e.key === ',') { e.preventDefault(); openSettings(); return; }
  if (e.key === 'Escape') {
    if (!$('alert').classList.contains('hidden')) return $('alert-cancel').click();
    if (!$('sheet').classList.contains('hidden')) return closeSettings();
    return closeDetail();
  }
  if (!current || !$('sheet').classList.contains('hidden')) return;
  if (e.key === ' ') { e.preventDefault(); togglePlay(); }
  if (e.key === 'i' || e.key === 'I') { trimIn = Math.min(video.currentTime, trimOut - 0.5); drawTimeline(); }
  if (e.key === 'o' || e.key === 'O') { trimOut = Math.max(video.currentTime, trimIn + 0.5); drawTimeline(); }
  if (e.key === 'ArrowLeft') { video.currentTime = Math.max(0, video.currentTime - (e.shiftKey ? 5 : 1 / 60)); drawTimeline(); }
  if (e.key === 'ArrowRight') { video.currentTime = Math.min(duration(), video.currentTime + (e.shiftKey ? 5 : 1 / 60)); drawTimeline(); }
});
// No browser context menu in an app window.
window.addEventListener('contextmenu', (e) => { if (e.target.tagName !== 'INPUT') e.preventDefault(); });

// ---------- start ----------

refreshStatus();
loadClips();
// The recording timer and the volume warning change without an event.
// Nobody sees them while the window is minimised, so it asks only when shown.
setInterval(() => { if (!document.hidden) refreshStatus().catch(() => {}); }, 1000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshStatus().catch(() => {}); });
window.addEventListener('focus', () => loadClips());
