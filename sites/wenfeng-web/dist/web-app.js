'use strict';
(() => {
  const $ = (id) => document.getElementById(id);
  const canvas = $('canvas');
  const cover = $('cover');
  const startButton = $('start-btn');
  const status = $('status');
  let engine;
  let starting = false;
  let ready = false;
  let stage = 'cover';
  let displayedControls;
  const heldPointers = new Map();

  // Policy 0 leaves the backing buffer to this page. Match real display pixels
  // while keeping the game's 1280×800 logical UI and the CSS aspect ratio.
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
    const query = matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`);
    query.addEventListener('change', () => {
      resizeCanvas();
      watchPixelRatio();
    }, { once: true });
  }
  watchPixelRatio();
  resizeCanvas();

  const command = (...args) => window.wenfengCommand?.(...args);
  const focusGame = () => canvas.focus({ preventScroll: true });
  window.render_game_to_text = () => JSON.stringify({ loading: stage, ...(window.__wenfengState || { ready: false, phase: 'loading' }) });
  // Godot owns the simulation clock; advance real frames instead of faking state.
  window.advanceTime = (ms) => new Promise((resolve) => setTimeout(resolve, Math.max(0, ms)));

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
    const mode = data.combat_mode === 'mounted' ? 'mounted' : 'foot';
    const mounted = mode === 'mounted';
    const horse = data.horse_color || data.player?.horse_color || 'white';
    const enemyHorse = data.enemy_horse_color || data.enemy?.horse_color || 'brown';
    const horseName = color => color === 'brown' ? '棕马' : '白马';
    const controls = `${mode}:${horse}:${enemyHorse}`;
    if (displayedControls !== controls) {
      displayedControls = controls;
      document.body.dataset.combatMode = mode;
      $('controls-footer').innerHTML = mounted
        ? 'WASD 控马 <i>·</i> J / K 马上攻击 <i>·</i> Space 冲刺 <i>·</i> Q / E / U 技能'
        : 'WASD 移动 <i>·</i> J / K 攻击 <i>·</i> Space 闪避 <i>·</i> Q / E / U 技能';
      $('help-mode').textContent = mounted
        ? `选将菜单切换模式与马色。当前马战 · 己方${horseName(horse)} / 对手${horseName(enemyHorse)}`
        : '仅选将菜单：切换步战 / 马战。当前步战';
      $('help-movement').textContent = mounted ? '控马移动与转向，松开方向仍有惯性' : '步战移动，自动面向对手';
      $('help-light').textContent = mounted ? '马上轻击，连续按下衔接三段连招' : '轻击，连续按下衔接三段连招';
      $('help-heavy').textContent = mounted ? '马上重击，造成更高伤害与格挡压力' : '重击，造成更高伤害与格挡压力';
      $('help-dodge').textContent = mounted ? '骑马短时冲刺；骑速与冲刺冷却显示在生命条下方' : '沿移动方向闪避；静止时向后撤';
      canvas.setAttribute('aria-label', mounted
        ? `3D 马战。己方${horseName(horse)}，对手${horseName(enemyHorse)}。WASD 控马，J 马上轻击，K 马上重击，L 格挡，空格冲刺，Q E 技能，U 绝技。选将菜单按 B 切换模式或点击选择马色。`
        : '3D 步战。WASD 移动，J 轻击，K 重击，L 格挡，空格闪避，Q E 技能，U 绝技。选将菜单按 B 切换模式。');
    }
    const cooldown = Math.max(0, Number(data.player?.mount_charge_cooldown) || 0);
    $('touch-dodge').textContent = mounted && cooldown > 0.05 ? `冲刺 ${cooldown.toFixed(1)}` : mounted ? '冲刺' : '闪避';
    $('touch-dodge').setAttribute('aria-label', mounted
      ? cooldown > 0.05 ? `骑马冲刺，冷却 ${cooldown.toFixed(1)} 秒` : '骑马冲刺'
      : '闪避');
    $('sound-btn').textContent = data.muted ? '声音 关' : '声音 开';
    $('sound-btn').setAttribute('aria-pressed', String(data.muted));
    $('pause-btn').textContent = data.paused ? '继续' : '暂停';
    $('pause-btn').disabled = data.phase === 'menu' || data.phase === 'match_end';
    $('touch-controls').hidden = !matchMedia('(pointer: coarse)').matches || cover.hidden === false || data.phase !== 'fight' || data.paused;
  };
  window.wenfengClose = () => {
    releaseTouches();
    cover.hidden = false;
    document.body.dataset.playing = 'false';
    startButton.hidden = false;
    startButton.innerHTML = '再次入场 <span>→</span>';
    $('touch-controls').hidden = true;
    startButton.focus();
  };

  async function installCompressedAssets() {
    if (!('DecompressionStream' in window)) throw new Error('当前浏览器版本较旧，请使用新版 Chrome、Edge、Firefox 或 Safari。');
    const nativeFetch = window.fetch.bind(window);
    const response = await nativeFetch('assets-manifest.json', { cache: 'no-cache' });
    if (!response.ok) throw new Error('游戏资源清单加载失败，请刷新后重试。');
    const manifest = await response.json();
    window.fetch = async function(input, init) {
      const url = new URL(input instanceof Request ? input.url : input, document.baseURI);
      const key = url.pathname.split('/').pop();
      const asset = url.origin === location.origin ? manifest.assets[key] : null;
      if (!asset) return nativeFetch(input, init);
      const chunks = asset.chunks || [{ file: asset.file }];
      let index = 0;
      let reader;
      // One gzip stream split into hosting-sized files. Read sequentially so
      // neither mobile browsers nor the local server need a second full copy.
      const compressed = new ReadableStream({
        async pull(controller) {
          while (index < chunks.length) {
            if (!reader) {
              const response = await nativeFetch(new URL(chunks[index].file, url), init);
              if (!response.ok || !response.body) throw new Error('游戏资源下载失败，请检查网络后重试。');
              reader = response.body.getReader();
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
      const decoded = compressed.pipeThrough(new DecompressionStream('gzip'));
      return new Response(decoded, {
        status: 200,
        headers: { 'Content-Type': asset.type, 'Content-Length': String(asset.decoded_bytes) },
      });
    };
  }

  async function start() {
    if (starting) return;
    if (ready) { window.wenfengReady(); return; }
    starting = true;
    stage = 'loading';
    startButton.hidden = true;
    $('error').hidden = true;
    $('load-progress').hidden = false;
    status.textContent = '正在准备庭院…';
    try {
      if (typeof Engine === 'undefined' || !Engine.isWebGLAvailable(2)) throw new Error('当前设备未启用 WebGL 2，请开启浏览器硬件加速后重试。');
      await installCompressedAssets();
      resizeCanvas();
      const config = {
        ...window.WENFENG_CONFIG,
        canvas,
        canvasResizePolicy: 0,
        locale: 'zh_CN',
        focusCanvas: true,
        onProgress(current, total) {
          const ratio = total > 0 ? Math.min(0.98, current / total) : 0.1;
          $('progress-fill').style.width = `${Math.round(ratio * 100)}%`;
          status.textContent = ratio > 0.95 ? '资源就绪，正在布置庭院…' : `正在载入兵刃与武将… ${Math.round(ratio * 100)}%`;
        },
        onPrintError(message) { console.error('[Godot]', message); },
        onExit(code) {
          if (code) showError(new Error('游戏运行中断，请刷新后重试。'));
        },
      };
      engine = new Engine(config);
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
    $('error').textContent = error?.message || '暂时无法进入庭院，请刷新后重试。';
    $('error').hidden = false;
    startButton.innerHTML = '重新载入 <span>↻</span>';
    startButton.hidden = false;
    startButton.onclick = () => location.reload();
    console.error(error);
  }

  async function fullscreen() {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await $('stage').requestFullscreen();
      focusGame();
    } catch (error) {
      console.warn('该浏览器暂不支持全屏。', error.message);
    }
  }
  startButton.addEventListener('click', start);
  $('fullscreen-btn').addEventListener('click', fullscreen);
  $('sound-btn').addEventListener('click', () => { command('mute'); focusGame(); });
  $('pause-btn').addEventListener('click', () => { releaseTouches(); command('pause'); focusGame(); });
  $('help-btn').addEventListener('click', () => { releaseTouches(); command('blur'); $('help-dialog').showModal(); });
  $('help-dialog').addEventListener('close', () => ready && cover.hidden && focusGame());
  document.addEventListener('fullscreenchange', () => {
    $('fullscreen-btn').innerHTML = document.fullscreenElement ? '退出全屏 <span>↙</span>' : '全屏 <span>↗</span>';
  });
  canvas.addEventListener('contextmenu', (event) => event.preventDefault());
  canvas.addEventListener('keydown', (event) => {
    if (event.code === 'KeyF' && !event.repeat) {
      event.preventDefault();
      event.stopImmediatePropagation();
      fullscreen();
    } else if (['Space','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Tab'].includes(event.code)) {
      event.preventDefault();
    }
  }, true);

  function releaseTouches() {
    for (const { action, button } of heldPointers.values()) {
      command('input', action, false);
      button.classList.remove('held');
    }
    heldPointers.clear();
  }
  document.querySelectorAll('[data-action]').forEach((button) => {
    const action = button.dataset.action;
    button.addEventListener('pointerdown', (event) => {
      event.preventDefault();
      button.setPointerCapture(event.pointerId);
      heldPointers.set(event.pointerId, { action, button });
      button.classList.add('held');
      command('input', action, true);
    });
    const release = (event) => {
      if (!heldPointers.has(event.pointerId)) return;
      heldPointers.delete(event.pointerId);
      const stillHeld = [...heldPointers.values()].some((item) => item.action === action);
      if (!stillHeld) {
        command('input', action, false);
        button.classList.remove('held');
      }
    };
    button.addEventListener('pointerup', release);
    button.addEventListener('pointercancel', release);
    button.addEventListener('lostpointercapture', release);
  });
  window.addEventListener('blur', () => { releaseTouches(); command('blur'); });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { releaseTouches(); command('blur'); }
  });
  matchMedia('(pointer: coarse)').addEventListener('change', () => window.wenfengStateChanged());
})();
