<script>
  import { onMount, onDestroy } from 'svelte';
  import { map } from '@windy/map';
  import { RISKS, prepare, pinSvg, popupHtml } from './pins.mjs';
  import { demoData } from './demoData.mjs';

  const SOURCE = 'https://raw.githubusercontent.com/dougease/nicky-windy-public/main/paineis_nicky.geojson';
  let markers = [];
  let groups = [];
  let count = 0;
  let generated = '';
  let received = '';
  let message = 'Carregando os dados Nicky…';
  let busy = false;
  let simulated = false;
  let failed = false;
  let controller;
  let timer;
  let disposed = false;
  let serial = 0;

  function draw(data, demo) {
    const next = prepare(data, demo);
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
        marker.bindPopup(popupHtml(group, demo));
        marker.addTo(map);
      }
    } catch (error) {
      added.forEach(marker => map.removeLayer(marker));
      throw error;
    }
    markers.forEach(marker => map.removeLayer(marker));
    markers = added;
    groups = next.groups;
    count = next.count;
    generated = next.generated;
    received = new Date().toLocaleString('pt-BR');
    simulated = demo;
    failed = false;
    message = demo ? 'TESTE VISUAL — cinco níveis simulados.' : 'Última leitura carregada. Atualização a cada 5 minutos.';
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
      if (!response.ok) throw new Error(`Resposta HTTP ${response.status}`);
      const data = await response.json();
      if (disposed || id !== serial) return;
      draw(data, false);
    } catch (error) {
      if (disposed || id !== serial) return;
      failed = true;
      message = `Falha ao atualizar: ${error.message}. ${count ? 'Os pins exibem a última leitura carregada.' : 'Nenhum dado operacional foi carregado.'}`;
    } finally {
      clearTimeout(timeout);
      if (id === serial) busy = false;
    }
  }
  function demo() {
    serial++;
    controller?.abort();
    busy = false;
    draw(demoData, true);
  }
  function locate() {
    if (!groups.length) return;
    const lat = groups.reduce((sum, g) => sum + g.lat, 0) / groups.length;
    const lon = groups.reduce((sum, g) => sum + g.lon, 0) / groups.length;
    map.setView([lat, lon], 10);
  }
  onMount(() => {
    refresh();
    timer = setInterval(() => { if (!simulated) refresh(); }, 300000);
  });
  onDestroy(() => {
    disposed = true;
    serial++;
    controller?.abort();
    clearInterval(timer);
    markers.forEach(marker => map.removeLayer(marker));
  });
</script>

<section class="nicky-panel">
  <strong>Nicky OOH · Risco dos painéis</strong>
  <p class:error={failed} role="status">{message}</p>
  {#if count}
    <p>{count} painéis · {groups.length} locais<br>Geração da fonte: {generated}<br>Leitura recebida: {received}</p>
  {/if}
  <div class="nicky-actions">
    <button on:click={refresh} disabled={busy}>Dados atuais</button>
    <button on:click={demo}>Testar 5 cores</button>
    <button on:click={locate} disabled={!count}>Localizar painéis</button>
  </div>
  <div class="nicky-legend">
    {#each RISKS as risk}
      <span><i style:background-color={risk.color}></i>{risk.name}</span>
    {/each}
    <span><i style="background-color:#6B7280"></i>Sem classificação</span>
  </div>
  <p>Locais com vários painéis mostram o maior risco conhecido e a quantidade. Clique no pin para ver todos. Risco não recalculado pela linha do tempo do Windy.</p>
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
