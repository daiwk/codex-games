'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const canvas = $('canvas');
  const cover = $('cover');
  const startButton = $('start-btn');
  const heldPointers = new Map();
  const coarsePointer = matchMedia('(pointer: coarse)');
  let starting = false;
  let ready = false;
  let stage = 'cover';
  let noticeTimer;

  function resizeCanvas() {
    const bounds = canvas.getBoundingClientRect();
    if (!bounds.width || !bounds.height) return;
    const scale = Math.min(window.devicePixelRatio || 1, 2, 3840 / bounds.width, 2400 / bounds.height);
    const width = Math.max(1, Math.round(bounds.width * scale));
    const height = Math.max(1, Math.round(bounds.height * scale));
    if (canvas.width !== width) canvas.width = width;
    if (canvas.height !== height) canvas.height = height;
  }
  new ResizeObserver(resizeCanvas).observe(canvas);
  window.addEventListener('resize', resizeCanvas);
  function watchPixelRatio() {
    matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`).addEventListener('change', () => {
      resizeCanvas();
      watchPixelRatio();
    }, { once: true });
  }
  watchPixelRatio();
  resizeCanvas();

  // The shared game publishes this bridge; UI and hosting remain independent.
  const command = (...args) => window.wenfengCommand?.(...args);
  const focusGame = () => canvas.focus({ preventScroll: true });
  window.render_game_to_text = () => JSON.stringify({ loading: stage, ...(window.__wenfengState || { ready: false, game_mode: 'rpg', phase: 'loading' }) });
  window.advanceTime = ms => new Promise(resolve => setTimeout(resolve, Math.max(0, ms)));

  try {
    const raw = localStorage.getItem('changban-rpg-save-v1');
    const saved = raw && raw.length <= 65536 ? JSON.parse(raw) : null;
    if (saved?.version === 1 && Number.isFinite(saved.level) && saved.level >= 1) {
      startButton.innerHTML = '继续征程 <span>→</span>';
      $('save-note').textContent = `发现旧日行装 · 等级 ${saved.level} · 征程保存在当前浏览器`;
    }
  } catch (_) {
    // Private browsing or an invalid older save should never prevent starting.
  }

  window.wenfengReady = () => {
    ready = true;
    starting = false;
    stage = 'ready';
    cover.hidden = true;
    $('load-progress').hidden = true;
    document.body.dataset.playing = 'true';
    $('pause-btn').disabled = false;
    $('sound-btn').disabled = false;
    resizeCanvas();
    focusGame();
    window.wenfengStateChanged();
  };

  window.wenfengStateChanged = () => {
    const data = window.__wenfengState;
    if (!data) return;
    window.__changbanState = data;
    const playing = ready && cover.hidden;
    const exploring = playing && data.phase === 'explore' && !data.paused && !data.dead;
    $('pause-btn').textContent = data.paused ? '继续' : '暂停';
    $('pause-btn').disabled = !playing || !!data.dead;
    $('sound-btn').textContent = data.muted ? '声音 关' : '声音 开';
    $('sound-btn').setAttribute('aria-pressed', String(!!data.muted));
    $('touch-controls').hidden = !coarsePointer.matches || !exploring;
    $('touch-shortcuts').hidden = !coarsePointer.matches || !playing || data.phase === 'dialogue';
    $('touch-interact').disabled = !exploring || !data.interaction;
    $('touch-interact').setAttribute('aria-label', data.interaction ? `交互：${data.interaction}` : '靠近人物或驿站后交互');
    $('touch-inventory').setAttribute('aria-pressed', String(!!data.inventory_open));
    $('touch-map').setAttribute('aria-pressed', String(!!data.map_open));
    $('dialogue-actions').hidden = !playing || data.phase !== 'dialogue' || !!data.paused;
    if (!exploring && heldPointers.size) releaseTouches();
  };

  window.wenfengClose = () => {
    releaseTouches();
    cover.hidden = false;
    document.body.dataset.playing = 'false';
    startButton.hidden = false;
    startButton.innerHTML = '继续征程 <span>→</span>';
    $('touch-controls').hidden = true;
    $('touch-shortcuts').hidden = true;
    $('dialogue-actions').hidden = true;
    startButton.focus();
  };

  async function installCompressedAssets() {
    if (!('DecompressionStream' in window)) throw new Error('当前浏览器版本较旧，请使用新版 Chrome、Edge、Firefox 或 Safari。');
    const nativeFetch = window.fetch.bind(window);
    const response = await nativeFetch('assets-manifest.json', { cache: 'no-cache' });
    if (!response.ok) throw new Error('行装清单加载失败，请刷新后重试。');
    const manifest = await response.json();
    window.fetch = async function(input, init) {
      const url = new URL(input instanceof Request ? input.url : input, document.baseURI);
      const key = url.pathname.split('/').pop();
      const asset = url.origin === location.origin ? manifest.assets[key] : null;
      if (!asset) return nativeFetch(input, init);
      const chunks = asset.chunks || [{ file: asset.file }];
      let index = 0;
      let reader;
      const compressed = new ReadableStream({
        async pull(controller) {
          while (index < chunks.length) {
            if (!reader) {
              const part = await nativeFetch(new URL(chunks[index].file, url), init);
              if (!part.ok || !part.body) throw new Error('行装下载失败，请检查网络后重试。');
              reader = part.body.getReader();
            }
            const { value, done } = await reader.read();
            if (!done) { controller.enqueue(value); return; }
            reader.releaseLock();
            reader = undefined;
            index++;
          }
          controller.close();
        },
        async cancel(reason) { if (reader) await reader.cancel(reason); },
      });
      return new Response(compressed.pipeThrough(new DecompressionStream('gzip')), {
        status: 200,
        headers: { 'Content-Type': asset.type, 'Content-Length': String(asset.decoded_bytes) },
      });
    };
  }

  async function start() {
    if (starting) return;
    if (ready) {
      if (window.__wenfengState?.paused) command('resume');
      window.wenfengReady();
      return;
    }
    starting = true;
    stage = 'loading';
    startButton.hidden = true;
    $('error').hidden = true;
    $('load-progress').hidden = false;
    $('status').textContent = '正在准备行装…';
    try {
      if (typeof Engine === 'undefined' || !Engine.isWebGLAvailable(2)) throw new Error('当前设备未启用 WebGL 2，请开启浏览器硬件加速后重试。');
      await installCompressedAssets();
      resizeCanvas();
      const engine = new Engine({
        ...window.CHANGBAN_CONFIG,
        canvas,
        canvasResizePolicy: 0,
        locale: 'zh_CN',
        focusCanvas: true,
        onProgress(current, total) {
          const ratio = total > 0 ? Math.min(0.98, current / total) : 0.1;
          $('progress-fill').style.width = `${Math.round(ratio * 100)}%`;
          $('status').textContent = ratio > 0.95 ? '行装已备，正在铺展山河…' : `正在载入坐骑与兵器… ${Math.round(ratio * 100)}%`;
        },
        onPrintError(message) { console.error('[Godot]', message); },
        onExit(code) { if (code) showError(new Error('征程暂时中断，请刷新后重试。')); },
      });
      await engine.startGame();
    } catch (error) {
      showError(error);
    }
  }

  function showError(error) {
    starting = false;
    stage = 'error';
    cover.hidden = false;
    $('load-progress').hidden = true;
    $('error').textContent = error?.message || '暂时无法启程，请刷新后重试。';
    $('error').hidden = false;
    startButton.innerHTML = '重新载入 <span>↻</span>';
    startButton.hidden = false;
    startButton.onclick = () => location.reload();
    console.error(error);
  }

  function notice(text) {
    clearTimeout(noticeTimer);
    $('browser-notice').textContent = text;
    $('browser-notice').hidden = false;
    noticeTimer = setTimeout(() => { $('browser-notice').hidden = true; }, 3500);
  }

  async function fullscreen() {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else if ($('stage').requestFullscreen) await $('stage').requestFullscreen();
      else notice('此浏览器暂不支持全屏，可横屏游玩。');
      focusGame();
    } catch (_) {
      notice('暂时无法进入全屏，可继续在当前窗口游玩。');
    }
  }
  startButton.addEventListener('click', start);
  $('fullscreen-btn').addEventListener('click', fullscreen);
  $('sound-btn').addEventListener('click', () => { command('mute'); focusGame(); });
  $('pause-btn').addEventListener('click', () => { releaseTouches(); command('pause'); focusGame(); });
  $('help-btn').addEventListener('click', () => { releaseTouches(); if (ready) command('blur'); $('help-dialog').showModal(); });
  $('help-dialog').addEventListener('close', () => { if (ready && cover.hidden) focusGame(); });
  document.addEventListener('fullscreenchange', () => {
    $('fullscreen-btn').innerHTML = document.fullscreenElement ? '退出全屏 <span>↙</span>' : '全屏 <span>↗</span>';
    resizeCanvas();
  });
  canvas.addEventListener('contextmenu', event => event.preventDefault());
  canvas.addEventListener('keydown', event => {
    // F, I, M and N belong to the RPG. Fullscreen is only the explicit button.
    if (ready && ['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Tab'].includes(event.code)) event.preventDefault();
  }, true);

  function releaseTouches() {
    const held = [...heldPointers.values()];
    heldPointers.clear();
    for (const { action, button } of held) {
      button.classList.remove('held');
      command('input', action, false);
    }
  }
  document.querySelectorAll('[data-action]').forEach(button => {
    const action = button.dataset.action;
    button.addEventListener('pointerdown', event => {
      event.preventDefault();
      button.setPointerCapture(event.pointerId);
      heldPointers.set(event.pointerId, { action, button });
      button.classList.add('held');
      command('input', action, true);
    });
    const release = event => {
      if (!heldPointers.has(event.pointerId)) return;
      heldPointers.delete(event.pointerId);
      if (![...heldPointers.values()].some(item => item.action === action)) {
        button.classList.remove('held');
        command('input', action, false);
      }
    };
    for (const event of ['pointerup', 'pointercancel', 'lostpointercapture']) button.addEventListener(event, release);
  });
  document.querySelectorAll('[data-command]').forEach(button => {
    button.addEventListener('click', () => {
      releaseTouches();
      command(button.dataset.command);
      focusGame();
    });
  });
  window.addEventListener('blur', () => { releaseTouches(); if (ready) command('blur'); });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { releaseTouches(); if (ready) command('blur'); }
  });
  coarsePointer.addEventListener('change', () => window.wenfengStateChanged());
})();
