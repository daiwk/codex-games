'use strict';

(() => {
  const byId = (id) => document.getElementById(id);
  const stage = byId('stage');
  const canvas = byId('canvas');
  const cover = byId('cover');
  const launch = byId('start-btn');
  const loading = byId('load-progress');
  const progress = byId('progress');
  const status = byId('status');
  const error = byId('error');
  const note = byId('browser-note');
  const nativeFetch = window.fetch.bind(window);
  const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  let phase = 'cover';
  let noticeTimer;
  let pointerLockPending = false;
  let pointerLockTimer;

  function resizeCanvas() {
    const { width, height } = canvas.getBoundingClientRect();
    if (width <= 0 || height <= 0) return;
    const scale = Math.min(window.devicePixelRatio || 1, 1.5, 2880 / width, 1800 / height);
    const bufferWidth = Math.round(width * scale);
    const bufferHeight = Math.round(height * scale);
    if (canvas.width !== bufferWidth) canvas.width = bufferWidth;
    if (canvas.height !== bufferHeight) canvas.height = bufferHeight;
  }

  new ResizeObserver(resizeCanvas).observe(canvas);
  window.addEventListener('resize', resizeCanvas);
  resizeCanvas();

  window.render_game_to_text = () => JSON.stringify({
    loading: phase,
    ...(window.__stonewallState || { ready: phase === 'ready', phase }),
  });
  window.stonewallState = (json) => { window.__stonewallState = JSON.parse(json); };
  window.stonewallPointerLocked = () => document.pointerLockElement === canvas;
  window.stonewallReleasePointer = () => {
    if (window.stonewallPointerLocked()) document.exitPointerLock();
  };
  // Godot drives its own simulation clock.
  window.advanceTime = (ms) => delay(Math.max(0, ms));
  window.stonewallReady = () => {
    if (phase !== 'loading') return;
    phase = 'ready';
    cover.hidden = true;
    resizeCanvas();
    canvas.focus({ preventScroll: true });
  };

  function showNotice(message) {
    clearTimeout(noticeTimer);
    note.textContent = message;
    note.hidden = false;
    noticeTimer = setTimeout(() => { note.hidden = true; }, 6500);
  }

  function pointerLockFailed() {
    if (!pointerLockPending) return;
    clearTimeout(pointerLockTimer);
    pointerLockPending = false;
    showNotice('浏览器未能锁定鼠标。对战中可按 Tab 重试，或在独立浏览器窗口打开此页面。');
  }

  function requestGamePointerLock() {
    if (phase !== 'ready' || pointerLockPending || window.stonewallPointerLocked()) return;
    clearTimeout(pointerLockTimer);
    pointerLockPending = true;
    pointerLockTimer = setTimeout(() => {
      pointerLockPending = false;
      if (window.__stonewallState?.menu) window.stonewallReleasePointer();
    }, 1400);
    try {
      const request = canvas.requestPointerLock();
      request?.catch(pointerLockFailed);
    } catch {
      pointerLockFailed();
    }
  }

  function isMenuButtonAt(clientX, clientY) {
    const menu = window.__stonewallState?.menu;
    if (!menu?.width || !menu.height || !Array.isArray(menu.buttons)) return false;
    const bounds = canvas.getBoundingClientRect();
    const scale = Math.min(bounds.width / menu.width, bounds.height / menu.height);
    if (scale <= 0) return false;
    const x = (clientX - bounds.left - (bounds.width - menu.width * scale) * 0.5) / scale;
    const y = (clientY - bounds.top - (bounds.height - menu.height * scale) * 0.5) / scale;
    return menu.buttons.some(([left, top, width, height]) =>
      x >= left && x <= left + width && y >= top && y <= top + height);
  }

  async function toggleFullscreen() {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await stage.requestFullscreen();
      if (phase === 'ready') canvas.focus({ preventScroll: true });
    } catch {
      showNotice('这个浏览器窗口无法进入全屏。');
    }
  }

  const fullscreenButton = byId('fullscreen-btn');
  fullscreenButton.hidden = !document.fullscreenEnabled;
  fullscreenButton.addEventListener('click', toggleFullscreen);
  document.addEventListener('fullscreenchange', () => {
    fullscreenButton.textContent = document.fullscreenElement ? '退出全屏' : '全屏';
    resizeCanvas();
  });
  window.addEventListener('keydown', (event) => {
    if (event.ctrlKey || event.metaKey || event.altKey) return;
    const canvasInput = event.isTrusted && event.target === canvas;
    const mode = window.__stonewallState?.phase;
    const menu = window.__stonewallState?.menu;
    const pointerLocked = window.stonewallPointerLocked();
    if (canvasInput && event.code === 'Tab' && (mode === 'active' || pointerLocked)) {
      event.preventDefault();
      if (!event.repeat && !pointerLocked) requestGamePointerLock();
      return;
    }
    if (event.repeat) return;
    if (event.code === 'KeyF') {
      event.preventDefault();
      event.stopImmediatePropagation();
      void toggleFullscreen();
    } else if (canvasInput && menu) {
      const choosingUnit = mode === 'takeover' || mode === 'switch';
      const selectUnit = choosingUnit && /^[1-7]$/.test(event.key) && Number(event.key) <= menu.choice_count;
      const cancelSwitch = mode === 'switch' && (event.code === 'KeyQ' || event.code === 'Escape');
      const restart = event.code === 'KeyR' && ['paused', 'result', 'takeover', 'switch'].includes(mode);
      if (restart || (menu.capture !== false && (event.key === 'Enter' || selectUnit || cancelSwitch))) {
        requestGamePointerLock();
      }
    }
  }, true);

  canvas.addEventListener('contextmenu', (event) => event.preventDefault());
  canvas.addEventListener('keydown', (event) => {
    if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(event.code)) event.preventDefault();
  });
  document.addEventListener('mouseup', (event) => {
    if (event.isTrusted && event.button === 0 && event.target === canvas &&
        window.__stonewallState?.menu?.capture !== false && isMenuButtonAt(event.clientX, event.clientY)) {
      requestGamePointerLock();
    }
  }, true);
  document.addEventListener('pointerlockchange', () => {
    pointerLockPending = false;
    if (!window.stonewallPointerLocked()) clearTimeout(pointerLockTimer);
  });
  document.addEventListener('pointerlockerror', pointerLockFailed);

  if (!matchMedia('(any-pointer: fine)').matches && matchMedia('(any-pointer: coarse)').matches) {
    byId('device-note').hidden = false;
  }

  async function fetchChunk(chunk, url, version, signal) {
    const target = new URL(chunk.file, url);
    target.searchParams.set('v', version);
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const response = await nativeFetch(target, { signal, cache: attempt ? 'reload' : 'default' });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const buffer = await response.arrayBuffer();
        if (chunk.bytes != null && buffer.byteLength !== chunk.bytes) throw new Error('资源大小不符');
        return new Uint8Array(buffer);
      } catch (cause) {
        if (signal.aborted) throw cause;
        if (attempt === 2) throw new Error('游戏资源下载未完成，请重新载入。', { cause });
        status.textContent = '正在重试下载游戏资源…';
        await delay(350 * (attempt + 1));
      }
    }
  }

  async function installAssetLoader() {
    if (!('DecompressionStream' in window)) {
      throw new Error('当前浏览器无法解压游戏资源，请使用新版桌面浏览器。');
    }
    const manifestResponse = await nativeFetch('assets-manifest.json', { cache: 'no-cache' });
    if (!manifestResponse.ok) throw new Error('游戏资源清单加载失败，请重新载入。');
    const manifest = await manifestResponse.json();
    const assetNames = ['game.wasm', 'game.pck'];
    const fileSizes = Object.fromEntries(assetNames.map((name) => {
      const asset = manifest.assets?.[name];
      if (!asset?.decoded_bytes || !asset?.type || (!asset.file && !asset.chunks?.length)) {
        throw new Error('游戏资源清单不完整，请重新载入。');
      }
      return [name, asset.decoded_bytes];
    }));

    window.fetch = (input, init) => {
      const url = new URL(input instanceof Request ? input.url : input, document.baseURI);
      const name = url.pathname.split('/').pop();
      const asset = url.origin === location.origin && assetNames.includes(name) ? manifest.assets[name] : null;
      if (!asset) return nativeFetch(input, init);
      const signal = init?.signal || (input instanceof Request ? input.signal : null);
      const chunks = asset.chunks || [{ file: asset.file, bytes: asset.download_bytes }];
      const transfer = new AbortController();
      if (signal?.aborted) transfer.abort(signal.reason);
      else signal?.addEventListener('abort', () => transfer.abort(signal.reason), { once: true });
      let index = 0;
      const compressed = new ReadableStream({
        async pull(controller) {
          if (index === chunks.length) {
            controller.close();
            return;
          }
          controller.enqueue(await fetchChunk(chunks[index], url, asset.sha256, transfer.signal));
          index++;
        },
        cancel(reason) { transfer.abort(reason); },
      }, { highWaterMark: 0 });
      return Promise.resolve(new Response(compressed.pipeThrough(new DecompressionStream('gzip')), {
        headers: {
          'Content-Type': asset.type,
          'Content-Length': String(asset.decoded_bytes),
        },
      }));
    };
    return fileSizes;
  }

  function showError(cause) {
    phase = 'error';
    loading.hidden = true;
    error.textContent = cause?.message || '游戏启动失败，请重新载入。';
    error.hidden = false;
    cover.hidden = false;
    launch.textContent = '重新载入';
    launch.hidden = false;
    launch.focus();
    console.error(cause);
  }

  launch.addEventListener('click', () => location.reload());

  async function start() {
    if (phase !== 'cover') return;
    phase = 'loading';
    loading.hidden = false;
    try {
      if (typeof Engine === 'undefined') throw new Error('游戏引擎加载失败，请重新载入。');
      if (!Engine.isWebGLAvailable(2)) {
        throw new Error('当前窗口无法使用 WebGL 2。请开启硬件加速，或在桌面浏览器中打开。');
      }
      const fileSizes = await installAssetLoader();
      const engine = new Engine({
        executable: 'game',
        canvas,
        canvasResizePolicy: 0,
        fileSizes,
        focusCanvas: true,
        locale: 'zh_CN',
        onProgress(current, total) {
          if (total <= 0) return;
          const percent = Math.min(99, Math.round(100 * current / total));
          progress.value = percent;
          status.textContent = percent >= 95 ? '正在启动游戏…' : `正在载入游戏资源… ${percent}%`;
        },
        onPrintError: (message) => console.error('[Godot]', message),
        onExit: (code) => {
          if (code) showError(new Error('游戏运行中断，请重新载入。'));
        },
      });
      await engine.startGame();
      window.stonewallReady();
    } catch (cause) {
      showError(cause);
    }
  }

  void start();
})();
