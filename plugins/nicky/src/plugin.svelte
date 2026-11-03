<script>
  import { onMount, onDestroy } from 'svelte';
  import { map } from '@windy/map';
  import store from '@windy/store';
  import { RISKS, prepare, pinSvg, popupHtml } from './pins.mjs';
  import { LEVELS, prepareWindow, popupWindowHtml, selectWindow, utcMillis, validateRisk72 } from './risk72.mjs';

  const SOURCE = 'https://raw.githubusercontent.com/dougease/nicky-windy-public/main/docs/windy/risco_72h.json';
  const STATIC_SOURCE = 'https://raw.githubusercontent.com/dougease/nicky-windy-public/main/paineis_nicky.geojson';
  let markers = [];
  let groups = [];
  let payload;
  let activeFrom = null;
  let generated = '';
  let received = '';
  let staticMode = false;
  let staticGeneratedMs = NaN;
  let displayCount = 0;
  let message = 'Carregando as três janelas de risco…';
  let busy = false;
  let failed = false;
  let controller;
  let timer;
  let disposed = false;
  let serial = 0;

  function clearMarkers() {
    markers.forEach(marker => map.removeLayer(marker));
    markers = [];
    groups = [];
    activeFrom = null;
  }
  function drawStatic(data) {
    const next = prepare(data);
    const generatedMs = Date.parse(next.generated);
    if (!Number.isFinite(generatedMs) || Date.now() - generatedMs > 36 * 3600000 ||
        generatedMs - Date.now() > 3600000) {
      throw new Error('Fotografia anterior vencida ou sem horário confiável.');
    }
    const added = [];
    try {
      for (const group of next.groups) {
        const icon = L.divIcon({
          html: pinSvg(group.risk.color, group.items.length, group.risk.rank < 0),
          iconSize: [36, 48], iconAnchor: [18, 47], popupAnchor: [0, -44],
          className: 'nicky-ooh-pin',
        });
        const marker = new L.Marker([group.lat, group.lon], { icon });
        added.push(marker);
        marker.bindPopup(popupHtml(group, false));
        marker.addTo(map);
      }
    } catch (error) {
      added.forEach(marker => map.removeLayer(marker));
      throw error;
    }
    clearMarkers();
    markers = added;
    groups = next.groups;
    staticMode = true;
    staticGeneratedMs = generatedMs;
    displayCount = next.count;
    generated = next.generated;
    received = new Date().toLocaleString('pt-BR');
    failed = false;
    message = 'Leitura anterior estática. A barra do Windy ainda não altera estas cores; aguardando o primeiro JSON de 72 h.';
  }
  function draw(window) {
    const nextGroups = prepareWindow(window);
    const added = [];
    try {
      for (const group of nextGroups) {
        const icon = L.divIcon({
          html: pinSvg(group.risk.color, group.items.length),
          iconSize: [36, 48], iconAnchor: [18, 47], popupAnchor: [0, -44],
          className: 'nicky-ooh-pin',
        });
        const marker = new L.Marker([group.lat, group.lon], { icon });
        added.push(marker);
        marker.bindPopup(popupWindowHtml(group, window, payload.rodadaUTC));
        marker.addTo(map);
      }
    } catch (error) {
      added.forEach(marker => map.removeLayer(marker));
      throw error;
    }
    clearMarkers();
    markers = added;
    groups = nextGroups;
    activeFrom = window.inicioH;
    displayCount = payload.quantidade;
  }
  function sync(timestamp = store.get('timestamp'), force = false) {
    if (disposed) return;
    if (staticMode) {
      if (Date.now() - staticGeneratedMs > 36 * 3600000) {
        clearMarkers();
        failed = true;
        message = 'Fotografia anterior vencida. Nenhum risco operacional exibido.';
      }
      return;
    }
    if (!payload) return;
    const age = Date.now() - utcMillis(payload.rodadaUTC);
    if (age > 36 * 3600000 || age < -3600000) {
      clearMarkers();
      failed = true;
      message = 'Rodada vencida ou futura. Nenhum painel classificado até nova publicação.';
      return;
    }
    const window = selectWindow(payload, timestamp);
    if (!window) {
      clearMarkers();
      failed = false;
      message = 'Horário fora da janela 0–72 h da rodada Nicky. Nenhuma cor de risco exibida.';
      return;
    }
    if (force || activeFrom !== window.inicioH) draw(window);
    failed = false;
    message = `Janela ${window.inicioH}–${window.fimH} h · ${window.validoDeUTC} a ${window.validoAteUTC} UTC. Cor para todo o período de 24 h.`;
  }
  async function refresh() {
    const id = ++serial;
    controller?.abort();
    controller = new AbortController();
    const current = controller;
    const timeout = setTimeout(() => current.abort(), 20000);
    busy = true;
    try {
      const response = await fetch(SOURCE, { cache: 'no-store', signal: current.signal });
      if (!response.ok && response.status === 404 && !payload) {
        const legacy = await fetch(STATIC_SOURCE, { cache: 'no-store', signal: current.signal });
        if (!legacy.ok) throw new Error(`JSON 72 h ausente; GeoJSON anterior HTTP ${legacy.status}`);
        const snapshot = await legacy.json();
        if (disposed || id !== serial) return;
        drawStatic(snapshot);
        return;
      }
      if (!response.ok) throw new Error(`Resposta HTTP ${response.status}`);
      const next = validateRisk72(await response.json());
      if (disposed || id !== serial) return;
      payload = next;
      staticMode = false;
      generated = next.rodadaUTC;
      received = new Date().toLocaleString('pt-BR');
      sync(store.get('timestamp'), true);
    } catch (error) {
      if (disposed || id !== serial) return;
      const stale = (payload && Date.now() - utcMillis(payload.rodadaUTC) > 36 * 3600000) ||
        (staticMode && Date.now() - staticGeneratedMs > 36 * 3600000);
      if (stale) clearMarkers();
      failed = true;
      message = `Falha ao atualizar: ${error.message}. ${stale || (!payload && !staticMode) ? 'Nenhuma cor operacional exibida.' : 'Última leitura válida preservada até vencer.'}`;
    } finally {
      clearTimeout(timeout);
      if (id === serial) busy = false;
    }
  }
  function locate() {
    if (!groups.length) return;
    const lat = groups.reduce((sum, g) => sum + g.lat, 0) / groups.length;
    const lon = groups.reduce((sum, g) => sum + g.lon, 0) / groups.length;
    map.setView([lat, lon], 10);
  }
  const onTimestamp = timestamp => sync(timestamp);
  onMount(() => {
    store.on('timestamp', onTimestamp);
    refresh();
    timer = setInterval(refresh, 300000);
  });
  onDestroy(() => {
    disposed = true;
    serial++;
    controller?.abort();
    clearInterval(timer);
    store.off('timestamp', onTimestamp);
    clearMarkers();
  });
</script>

<section class="nicky-panel">
  <strong>Nicky OOH · Risco 72 h</strong>
  <p class:error={failed} role="status">{message}</p>
  {#if payload || staticMode}
    <p>{displayCount} painéis · {groups.length} locais{staticMode ? ' (fotografia estática)' : ' na janela'}<br>{staticMode ? 'Geração: ' : 'Rodada: '}{generated}{staticMode ? '' : ' UTC'}<br>Leitura recebida: {received}</p>
  {/if}
  <div class="nicky-actions">
    <button on:click={refresh} disabled={busy}>Atualizar dados</button>
    <button on:click={locate} disabled={!groups.length}>Localizar painéis</button>
  </div>
  <div class="nicky-legend">
    {#each (staticMode ? RISKS : LEVELS) as risk}
      <span><i style:background-color={risk.color}></i>{risk.name}</span>
    {/each}
  </div>
  <p>{staticMode ? 'A fotografia anterior não responde à barra do Windy.' : 'Arraste a barra do Windy: cada cor vale para a janela inteira de 24 h.'} A camada de vento pode usar outro modelo ou rodada. Consulte alertas oficiais antes de mobilizar equipes.</p>
</section>

<style>
  .nicky-panel { padding:12px; max-width:330px; background:#263038ed; color:#fff; border-radius:12px; font:13px/1.45 Arial,sans-serif; }
  p { margin:8px 0; font-size:12px; }
  .error { color:#ffd79b; }
  .nicky-actions { display:flex; flex-wrap:wrap; gap:6px; }
  button { border:1px solid #abb6c4; border-radius:6px; padding:7px; background:#fff; color:#182230; cursor:pointer; font:12px Arial,sans-serif; }
  button:disabled { opacity:.55; cursor:default; }
  .nicky-legend { display:flex; flex-wrap:wrap; gap:7px; margin-top:10px; font-size:11px; }
  .nicky-legend span { display:inline-flex; align-items:center; gap:4px; }
  i { width:11px; height:11px; border-radius:50%; display:inline-block; border:1px solid white; }
  :global(.nicky-ooh-pin) { background:transparent !important; border:0 !important; }
  :global(.nicky-ooh-pin svg) { display:block; filter:drop-shadow(0 2px 2px #0008); }
</style>
