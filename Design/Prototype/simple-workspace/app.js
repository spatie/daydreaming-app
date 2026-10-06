(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const now = new Date().getHours();
  const startsEmpty = new URLSearchParams(location.search).has('empty');
  const yosemite = { id: 'yosemite', name: 'Yosemite Valley', url: 'assets/yosemite-original.jpg', demo: true, width: 2880, height: 1620 };
  const state = {
    picture: startsEmpty ? null : { ...yosemite },
    hour: now, idea: $('idea').value, crop: { zoom: 1, x: 0, y: 0 },
    hasEditedIdea: false, busy: false, rendering: false, running: false, wasStarted: false, activeKey: null,
    cropMode: false, revision: 0, desktopRevision: 0, cropSnapshot: null,
    history: [], timer: null, finishTimer: null, previewCount: 0, firstPreview: false,
  };
  const timeLabel = h => `${String(h).padStart(2, '0')}:00`;
  const recipeKey = () => JSON.stringify([state.picture?.id, state.idea.trim(), state.crop]);
  const cropCopy = crop => ({ ...crop });
  let currentPreviewURL = $('previewImage').src;
  let pointerStart = null;
  const cropPointers = new Map();
  let pinchStart = null, gridTimer = null;

  function condition() {
    const idea = state.idea.toLowerCase();
    if (/snow|winter|frost/.test(idea)) return 'snow';
    if (/rain|storm|wet/.test(idea)) return 'rain';
    if (/fog|mist|haze/.test(idea)) return 'fog';
    return 'clear';
  }
  function period() { return state.hour < 6 || state.hour >= 21 ? 'night' : state.hour >= 16 ? 'evening' : state.hour >= 10 && condition() === 'clear' ? 'day' : 'morning'; }
  function simulatedURL() {
    return state.picture.demo ? `assets/${condition()}-${period()}.webp` : state.picture.url;
  }
  function weatherLabel() { return state.hour >= 16 && state.hour < 21 ? 'Partly cloudy' : 'Clear'; }
  function announce(message) { $('announcer').textContent = message; }
  function updateCropBadge() { $('cropBadge').hidden = state.crop.zoom === 1 && state.crop.x === 0 && state.crop.y === 0; }
  function setSliderTrack(input, value, max = 23, min = 0) { input.style.setProperty('--position', `${(value - min) / (max - min) * 100}%`); }

  function updateTimeline() {
    $('hour').value = state.hour;
    $('hour').setAttribute('aria-valuetext', `${timeLabel(state.hour)}, ${weatherLabel()}, preview`);
    $('hourBubble').textContent = timeLabel(state.hour);
    $('hourBubble').style.left = `calc(8px + (100% - 16px) * ${state.hour / 23})`;
    $('nowButton').hidden = state.hour === now;
    setSliderTrack($('hour'), state.hour);
  }
  function updateConfirmation() {
    $('startButton').hidden = !state.picture;
    $('confirmation').hidden = !state.picture;
    const dirty = state.activeKey !== recipeKey();
    const running = state.running && !dirty;
    $('confirmationCopy').hidden = !state.running && !state.rendering && !state.wasStarted;
    $('runningIndicator').hidden = !state.running;
    $('startButton').classList.toggle('quiet', running);
    $('startButton').disabled = state.busy || state.rendering || state.cropMode;
    $('startButton').title = running ? 'Pause automatic wallpaper updates.' : 'Creates a full-quality wallpaper now and keeps it changing. Uses OpenAI credit in the real app.';
    $('startButton').replaceChildren(document.createTextNode(
      state.rendering ? 'Starting…' : running ? 'Pause' : state.running ? 'Use These Changes' : state.wasStarted && !dirty ? 'Resume My Wallpaper' : 'Start Daydreaming'
    ));
    if (!running && !state.rendering) {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('aria-hidden', 'true');
      const path = document.createElementNS(svg.namespaceURI, 'path'); path.setAttribute('d', 'M5 12h14M13 6l6 6-6 6');
      svg.append(path); $('startButton').append(svg);
    }
    $('confirmationTitle').textContent = state.rendering ? 'Making your desktop wallpaper…'
      : running ? 'Your wallpaper is changing through the day.'
      : state.running ? 'A new idea for your wallpaper.'
      : state.wasStarted && !dirty ? 'Your wallpaper is paused.' : 'Your picture, changing through the day.';
    $('confirmationDetail').textContent = state.rendering ? 'Your original and these ideas will guide every variation.'
      : running ? `Next change around ${timeLabel((now + 1) % 24)} · following the time and weather.`
      : state.running ? 'Confirm to use this picture and idea for future variations.'
      : state.wasStarted && !dirty ? 'Your desktop keeps its last picture until you resume.'
      : 'Start a full-quality wallpaper that follows the time and weather.';
  }
  function setBusy(busy) {
    state.busy = busy;
    $('artwork').classList.toggle('busy', busy);
    $('waiting').hidden = !busy;
    $('waitingText').textContent = state.firstPreview ? 'Making your first preview…' : `Reimagining ${timeLabel(state.hour)}…`;
    $('ideaFeedback').textContent = busy ? 'Refreshing the preview…' : state.hasEditedIdea ? 'In the app, previews use OpenAI credit.' : 'Changes preview automatically.';
    updateConfirmation();
  }
  function positionImage(image, crop = state.crop, cropMode = false) {
    if (!state.picture) return;
    const artwork = $('artwork');
    const width = artwork.clientWidth * (cropMode ? .94 : 1);
    const height = artwork.clientHeight * (cropMode ? .94 : 1);
    const left = cropMode ? artwork.clientWidth * .03 : 0;
    const top = cropMode ? artwork.clientHeight * .03 : 0;
    const naturalW = image.naturalWidth || state.picture.width;
    const naturalH = image.naturalHeight || state.picture.height;
    const scale = Math.max(width / naturalW, height / naturalH) * crop.zoom;
    const displayW = naturalW * scale, displayH = naturalH * scale;
    const x = left + (width - displayW) / 2 + crop.x * Math.max(0, displayW - width) / 2;
    const y = top + (height - displayH) / 2 + crop.y * Math.max(0, displayH - height) / 2;
    Object.assign(image.style, { width: `${displayW}px`, height: `${displayH}px`, left: `${x}px`, top: `${y}px`, transform: 'none' });
    return { displayW, displayH, width, height };
  }
  function applyMockTone() {
    if (!state.picture) return;
    const idea = state.idea.toLowerCase();
    const image = $('previewImage');
    // Uploaded pictures have a local color treatment, never an AI edit.
    let filter = state.picture.demo ? '' : state.hour < 6 || state.hour >= 21 ? 'brightness(.48) saturate(.75)' : state.hour >= 16 ? 'sepia(.25) saturate(1.2) brightness(.96)' : 'brightness(1.02)';
    if (/painting|watercolor|illustrat|dreamy/.test(idea)) filter += ' saturate(.8) contrast(.88)';
    if (/vivid|vibrant|colourful|colorful/.test(idea)) filter += ' saturate(1.5)';
    if (/black and white|monochrome/.test(idea)) filter += ' grayscale(1)';
    if (state.idea !== 'Update my picture according to the current time and weather conditions.') {
      const seed = [...state.idea].reduce((sum, char) => sum + char.charCodeAt(0), 0);
      filter += ` hue-rotate(${seed % 9 - 4}deg) saturate(${.96 + (seed % 10) / 70})`;
    }
    filter += ` brightness(${(.96 + .04 * Math.cos((state.hour - 12) * Math.PI / 12)).toFixed(3)})`;
    image.style.filter = filter;
    $('previewTone').style.opacity = state.picture.demo ? '0' : '.4';
    $('previewTone').style.background = condition() === 'snow' ? '#c5e1ff' : condition() === 'rain' ? '#264e89' : condition() === 'fog' ? '#d1d5dd' : state.hour >= 16 && state.hour < 21 ? '#ffb567' : '#91aace';
    positionImage(image);
  }
  function rememberPreview(url) {
    let picture = state.history.find(item => item.picture.id === state.picture.id);
    if (!picture) {
      picture = { picture: { ...state.picture }, idea: state.idea, crop: cropCopy(state.crop), variations: [] };
      state.history.unshift(picture);
    }
    picture.idea = state.idea; picture.crop = cropCopy(state.crop);
    const key = `${state.hour}:${state.idea}:${JSON.stringify(state.crop)}`;
    const variation = { key, url, hour: state.hour, idea: state.idea, crop: cropCopy(state.crop), filter: $('previewImage').style.filter };
    picture.variations = [variation, ...picture.variations.filter(item => item.key !== key)].slice(0, 4);
    state.history = [picture, ...state.history.filter(item => item !== picture)].slice(0, 8);
    $('historyButton').hidden = false;
  }
  async function renderPreview(revision) {
    if (revision !== state.revision || state.cropMode || !state.picture) return;
    setBusy(true);
    const url = simulatedURL();
    const image = new Image(); image.src = url;
    try { await image.decode(); }
    catch { if (revision === state.revision) { setBusy(false); $('fileError').textContent = 'This picture could not be opened. Try a JPEG or PNG.'; } return; }
    if (revision !== state.revision || state.cropMode) return;
    state.finishTimer = setTimeout(() => {
      if (revision !== state.revision || state.cropMode) return;
      currentPreviewURL = url;
      $('previewImage').src = url;
      $('previewImage').alt = `Simulated preview of ${state.picture.name} at ${timeLabel(state.hour)}`;
      applyMockTone();
      state.previewCount++;
      rememberPreview(url);
      state.firstPreview = false;
      setBusy(false);
      announce(`Preview for ${timeLabel(state.hour)} is ready.`);
    }, state.firstPreview ? 1500 : 650);
  }
  function schedulePreview(delay = 650) {
    clearTimeout(state.timer); clearTimeout(state.finishTimer);
    state.revision++;
    setBusy(false);
    updateTimeline(); updateConfirmation();
    if (state.cropMode || !state.picture) { $('ideaFeedback').textContent = ''; return; }
    $('ideaFeedback').textContent = 'Preview will refresh…';
    const revision = state.revision;
    state.timer = setTimeout(() => renderPreview(revision), delay);
  }
  function showPicture(picture, idea = state.idea, crop = { zoom: 1, x: 0, y: 0 }) {
    state.picture = { ...picture }; state.idea = idea; state.crop = cropCopy(crop);
    updatePictureState();
    $('idea').value = idea; updateCropBadge();
    $('pictureName').textContent = picture.name;
    $('sourceThumbnail').src = picture.url;
    $('sourceThumbnail').alt = `${picture.name}, your original picture`;
    $('previewImage').src = picture.url;
    currentPreviewURL = picture.url;
    $('previewImage').style.filter = '';
    $('previewTone').style.opacity = '0';
    positionImage($('previewImage'));
    $('fileError').textContent = '';
    state.firstPreview = true;
    schedulePreview(0);
    setBusy(true);
  }
  async function acceptFile(file) {
    if (!file || !file.type.startsWith('image/')) {
      $('fileError').textContent = 'Choose a picture, such as a JPEG, PNG or WebP.'; return;
    }
    if (file.size > 30 * 1024 * 1024) { $('fileError').textContent = 'For this prototype, choose a picture under 30 MB.'; return; }
    const url = URL.createObjectURL(file), image = new Image(); image.src = url;
    try { await image.decode(); }
    catch { URL.revokeObjectURL(url); $('fileError').textContent = 'The browser could not open this picture. Try a JPEG or PNG.'; return; }
    if (state.cropMode) closeCrop(false);
    showPicture({ id: crypto.randomUUID(), name: file.name.replace(/\.[^.]+$/, ''), url, demo: false, width: image.naturalWidth, height: image.naturalHeight });
    announce('Picture chosen. Making a preview.');
  }

  $('sourceButton').addEventListener('click', () => $('fileInput').click());
  $('changePicture').addEventListener('click', () => $('fileInput').click());
  $('tryYosemite').addEventListener('click', () => showPicture(yosemite));
  $('fileInput').addEventListener('change', event => { acceptFile(event.target.files[0]); event.target.value = ''; });
  $('idea').addEventListener('input', () => {
    state.idea = $('idea').value; state.hasEditedIdea = true;
    $('characterCount').textContent = `${state.idea.length}/280`;
    schedulePreview(1000);
  });
  $('idea').addEventListener('focus', () => { $('characterCount').hidden = false; $('characterCount').textContent = `${$('idea').value.length}/280`; });
  $('idea').addEventListener('blur', () => { $('characterCount').hidden = true; });
  $('hour').addEventListener('input', () => { state.hour = Number($('hour').value); schedulePreview(); });
  $('nowButton').addEventListener('click', () => { state.hour = now; schedulePreview(150); });
  $('startButton').addEventListener('click', () => {
    if (!state.picture) return;
    if (state.running && state.activeKey === recipeKey()) {
      state.running = false; state.desktopRevision++; updateConfirmation(); announce('Automatic wallpaper updates paused.'); return;
    }
    if (state.busy || state.rendering || state.cropMode) return;
    state.rendering = true;
    const key = recipeKey(), revision = ++state.desktopRevision;
    state.hour = now; schedulePreview(0); updateConfirmation();
    setTimeout(() => {
      if (revision !== state.desktopRevision) return;
      state.activeKey = key; state.running = true; state.wasStarted = true; state.rendering = false;
      updateConfirmation(); announce('Prototype wallpaper started. It will keep changing with the time and weather.');
    }, 1300);
  });

  let dragDepth = 0;
  document.addEventListener('dragenter', event => {
    if (!Array.from(event.dataTransfer?.types || []).includes('Files')) return;
    event.preventDefault(); dragDepth++; $('dropOverlay').hidden = false;
  });
  document.addEventListener('dragover', event => {
    if (Array.from(event.dataTransfer?.types || []).includes('Files')) { event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; }
  });
  document.addEventListener('dragleave', () => { if (--dragDepth <= 0) { dragDepth = 0; $('dropOverlay').hidden = true; } });
  document.addEventListener('drop', event => {
    event.preventDefault(); dragDepth = 0; $('dropOverlay').hidden = true;
    const file = Array.from(event.dataTransfer?.files || []).find(file => file.type.startsWith('image/'));
    acceptFile(file);
  });

  function openCrop() {
    if (!state.picture) return;
    clearTimeout(state.timer); clearTimeout(state.finishTimer); state.revision++; setBusy(false);
    state.cropSnapshot = cropCopy(state.crop); state.cropMode = true;
    $('app').classList.add('cropping');
    $('cropWorkspace').hidden = false; $('cropControls').hidden = false;
    $('timeline').hidden = true; $('confirmation').hidden = true; $('cropConfirmation').hidden = false;
    $('cropImage').src = state.picture.url;
    $('idea').disabled = true; $('sourceButton').disabled = true;
    $('cropButton').disabled = true; $('historyButton').disabled = true;
    $('changePicture').disabled = true;
    $('cropButton').hidden = true;
    $('previewLabel').textContent = 'Crop your original';
    $('zoom').value = state.crop.zoom; setSliderTrack($('zoom'), state.crop.zoom, 4, 1);
    $('cropImage').decode().then(() => positionImage($('cropImage'), state.crop, true));
    $('cropWorkspace').tabIndex = 0; $('cropWorkspace').setAttribute('aria-label', 'Drag to position your original. Use arrow keys to move it.');
    updateCropCopy();
    $('cropWorkspace').focus();
  }
  function closeCrop(save) {
    const changed = JSON.stringify(state.crop) !== JSON.stringify(state.cropSnapshot);
    if (!save) state.crop = cropCopy(state.cropSnapshot);
    state.cropMode = false;
    cropPointers.clear(); pointerStart = null; pinchStart = null;
    clearTimeout(gridTimer); $('cropWorkspace').classList.remove('interacting');
    $('app').classList.remove('cropping');
    $('cropWorkspace').hidden = true; $('cropControls').hidden = true;
    $('timeline').hidden = false; $('confirmation').hidden = false; $('cropConfirmation').hidden = true;
    for (const id of ['idea', 'sourceButton', 'cropButton', 'historyButton', 'changePicture']) $(id).disabled = false;
    $('cropButton').hidden = false;
    $('previewLabel').textContent = 'Preview';
    updateTimeline(); applyMockTone(); updateConfirmation(); updateCropBadge();
    if (save && changed) schedulePreview(100);
    $('cropButton').focus();
  }
  function updateCropCopy() {
    const changed = JSON.stringify(state.crop) !== JSON.stringify(state.cropSnapshot);
    $('cropConfirmation').querySelector('p').textContent = changed ? 'Done makes a new preview. Uses OpenAI credit in the app.' : 'Drag to frame your picture. Your idea stays the same.';
  }
  function updateZoom(value) {
    state.crop.zoom = Math.max(1, Math.min(4, value));
    $('zoom').value = state.crop.zoom; setSliderTrack($('zoom'), state.crop.zoom, 4, 1);
    positionImage($('cropImage'), state.crop, true); updateCropCopy();
    $('cropWorkspace').classList.add('interacting');
    clearTimeout(gridTimer);
    gridTimer = setTimeout(() => { if (!cropPointers.size) $('cropWorkspace').classList.remove('interacting'); }, 350);
  }
  $('cropButton').addEventListener('click', openCrop);
  $('doneCrop').addEventListener('click', () => closeCrop(true));
  $('cancelCrop').addEventListener('click', () => closeCrop(false));
  $('zoom').addEventListener('input', () => updateZoom(Number($('zoom').value)));
  $('zoomIn').addEventListener('click', () => updateZoom(state.crop.zoom * 1.15));
  $('zoomOut').addEventListener('click', () => updateZoom(state.crop.zoom / 1.15));
  $('resetCrop').addEventListener('click', () => { state.crop = { zoom: 1, x: 0, y: 0 }; updateZoom(1); });
  $('cropWorkspace').addEventListener('pointerdown', event => {
    cropPointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (cropPointers.size === 1) pointerStart = { x: event.clientX, y: event.clientY, crop: cropCopy(state.crop) };
    if (cropPointers.size === 2) {
      const [a, b] = [...cropPointers.values()];
      pinchStart = { distance: Math.hypot(a.x - b.x, a.y - b.y), zoom: state.crop.zoom };
      pointerStart = null;
    }
    $('cropWorkspace').setPointerCapture(event.pointerId); $('cropWorkspace').classList.add('interacting');
  });
  $('cropWorkspace').addEventListener('pointermove', event => {
    if (!cropPointers.has(event.pointerId)) return;
    cropPointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (cropPointers.size === 2 && pinchStart) {
      const [a, b] = [...cropPointers.values()];
      updateZoom(pinchStart.zoom * Math.hypot(a.x - b.x, a.y - b.y) / Math.max(1, pinchStart.distance));
      return;
    }
    if (!pointerStart) return;
    const layout = positionImage($('cropImage'), pointerStart.crop, true);
    state.crop.x = Math.max(-1, Math.min(1, pointerStart.crop.x + (event.clientX - pointerStart.x) * 2 / Math.max(1, layout.displayW - layout.width)));
    state.crop.y = Math.max(-1, Math.min(1, pointerStart.crop.y + (event.clientY - pointerStart.y) * 2 / Math.max(1, layout.displayH - layout.height)));
    positionImage($('cropImage'), state.crop, true); updateCropCopy();
  });
  function endDrag(event) {
    cropPointers.delete(event.pointerId); pinchStart = null;
    if (cropPointers.size === 1) {
      const [{ x, y }] = [...cropPointers.values()]; pointerStart = { x, y, crop: cropCopy(state.crop) };
    } else { pointerStart = null; $('cropWorkspace').classList.remove('interacting'); }
  }
  $('cropWorkspace').addEventListener('pointerup', endDrag); $('cropWorkspace').addEventListener('pointercancel', endDrag);
  $('cropWorkspace').addEventListener('wheel', event => {
    event.preventDefault(); updateZoom(state.crop.zoom * Math.exp(-Math.max(-.2, Math.min(.2, event.deltaY * .002))));
  }, { passive: false });
  document.addEventListener('keydown', event => {
    if (!state.cropMode) return;
    if (event.key === 'Escape') { event.preventDefault(); closeCrop(false); }
    else if (event.key === 'Enter' && !['BUTTON', 'INPUT'].includes(document.activeElement.tagName)) { event.preventDefault(); closeCrop(true); }
    else if (document.activeElement === $('cropWorkspace')) {
      const directions = { ArrowLeft: [-.04, 0], ArrowRight: [.04, 0], ArrowUp: [0, -.04], ArrowDown: [0, .04] };
      if (directions[event.key]) {
        event.preventDefault(); const [x, y] = directions[event.key];
        state.crop.x = Math.max(-1, Math.min(1, state.crop.x + x)); state.crop.y = Math.max(-1, Math.min(1, state.crop.y + y));
        positionImage($('cropImage'), state.crop, true); updateCropCopy();
      }
    }
  });

  function renderHistory() {
    $('historyList').replaceChildren();
    for (const entry of state.history) {
      const card = document.createElement('article'); card.className = 'history-item';
      const button = document.createElement('button'); button.className = 'history-pick';
      const image = document.createElement('img'); image.src = entry.picture.url; image.alt = entry.picture.name;
      const info = document.createElement('div'), title = document.createElement('strong'), idea = document.createElement('p');
      title.textContent = entry.picture.name; idea.textContent = entry.idea || 'Follow the time and weather.';
      info.append(title, idea); button.append(image, info);
      button.addEventListener('click', () => { $('historyDialog').close(); showPicture(entry.picture, entry.idea, entry.crop); });
      card.append(button);
      if (entry.variations.length) {
        const strip = document.createElement('div'); strip.className = 'history-variations';
        for (const variation of entry.variations) {
          const pick = document.createElement('button'), thumb = document.createElement('img'), time = document.createElement('span');
          thumb.src = variation.url; thumb.alt = ''; thumb.style.filter = variation.filter || ''; time.textContent = timeLabel(variation.hour);
          pick.title = `Return to this picture and idea from ${timeLabel(variation.hour)}`; pick.append(thumb, time);
          pick.addEventListener('click', () => { $('historyDialog').close(); state.hour = variation.hour; showPicture(entry.picture, variation.idea, variation.crop); });
          strip.append(pick);
        }
        card.append(strip);
      }
      $('historyList').append(card);
    }
  }
  $('historyButton').addEventListener('click', () => { renderHistory(); $('historyDialog').showModal(); });
  $('closeHistory').addEventListener('click', () => $('historyDialog').close());
  $('historyDialog').addEventListener('click', event => { if (event.target === $('historyDialog')) $('historyDialog').close(); });
  $('resetDemo').addEventListener('click', () => location.reload());
  new ResizeObserver(() => {
    if (state.cropMode) positionImage($('cropImage'), state.crop, true);
    else if (state.picture) positionImage($('previewImage'));
  }).observe($('artwork'));
  $('previewImage').addEventListener('load', applyMockTone);
  function updatePictureState() {
    const empty = !state.picture;
    $('app').classList.toggle('no-picture', empty);
    $('emptySource').hidden = !empty;
    $('emptyPreview').hidden = !empty;
    $('sourceThumbnail').hidden = empty;
    $('previewImage').hidden = empty;
    $('previewTone').hidden = empty;
    $('pictureName').hidden = empty;
    $('changePicture').hidden = empty;
    $('dropHint').hidden = empty;
    $('cropButton').hidden = empty;
    $('timeline').hidden = empty;
    $('historyButton').hidden = !state.history.length;
    if (empty) $('ideaFeedback').textContent = '';
  }
  if (state.picture) {
    currentPreviewURL = simulatedURL(); $('previewImage').src = currentPreviewURL;
    rememberPreview(currentPreviewURL);
  }
  updatePictureState(); updateTimeline(); updateConfirmation();
  // Exposes read-only state for verifying this local prototype, with no network backend.
  window.daydreamingDemo = { get state() { return { picture: state.picture?.name ?? null, hour: state.hour, idea: state.idea, crop: cropCopy(state.crop), cropMode: state.cropMode, busy: state.busy, running: state.running, previewCount: state.previewCount, historyCount: state.history.length }; } };
})();
