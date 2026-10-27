export const RISKS = Object.freeze([
  { name: 'Normal', color: '#2E8B57' },
  { name: 'Atenção', color: '#E1C542' },
  { name: 'Preparação', color: '#FF9900' },
  { name: 'Alerta', color: '#E85D04' },
  { name: 'Crítico', color: '#C94C4C' },
]);
export const UNKNOWN = Object.freeze({ name: 'Sem classificação', color: '#6B7280' });
export function classify(value) {
  const normalized = String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().toLowerCase();
  const index = RISKS.findIndex(r => r.name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase() === normalized);
  return { ...(index < 0 ? UNKNOWN : RISKS[index]), rank: index };
}
export const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

export function prepare(data, simulated = false) {
  if (data?.type !== 'FeatureCollection' || !Array.isArray(data.features) || !data.features.length) throw new Error('GeoJSON vazio ou inválido.');
  const groups = new Map();
  for (const feature of data.features) {
    const c = feature.geometry?.coordinates;
    if (feature.geometry?.type !== 'Point' || !Array.isArray(c) || c.length < 2 ||
        !Number.isFinite(c[0]) || !Number.isFinite(c[1]) || Math.abs(c[0]) > 180 || Math.abs(c[1]) > 90) throw new Error('O GeoJSON contém coordenadas inválidas. Última leitura preservada.');
    const p = feature.properties ?? {};
    if (!simulated && (p.teste === true || p.risco_simulado != null)) throw new Error('Dados de teste não podem ser apresentados como leitura operacional.');
    const risk = classify(simulated ? p.risco_simulado : p.risco);
    const item = { code: String(p.code ?? feature.id ?? p.name ?? 'Sem código'), risk, action: String(p.acao ?? ''), models: String(p.modelo ?? ''), ecmwf: String(p.rodada_ecmwf ?? ''), gefs: String(p.rodada_gefs ?? '') };
    const key = `${c[0]},${c[1]}`;
    if (!groups.has(key)) groups.set(key, { lon: c[0], lat: c[1], items: [], risk });
    const group = groups.get(key);
    group.items.push(item);
    if (risk.rank > group.risk.rank) group.risk = risk;
  }
  return { groups: [...groups.values()], count: data.features.length, generated: String(data.generated_at ?? 'Não informada') };
}

export function pinSvg(color, count = 1, unknown = false) {
  if (![...RISKS.map(r => r.color), UNKNOWN.color].includes(color)) throw new Error('Cor não permitida');
  const label = count > 1 ? String(count) : unknown ? '?' : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="48" viewBox="0 0 48 64" aria-hidden="true"><path d="M24 61C20 51 5 37 5 23a19 19 0 1 1 38 0c0 14-15 28-19 38Z" fill="${color}" stroke="#fff" stroke-width="2.5"/><circle cx="24" cy="22" r="10" fill="#fff"/>${label ? `<text x="24" y="26" text-anchor="middle" font-family="Arial" font-size="12" font-weight="bold" fill="#182230">${label}</text>` : ''}</svg>`;
}
export function popupHtml(group, simulated) {
  return `<div style="color:#182230;max-width:300px;max-height:260px;overflow:auto"><strong>${simulated ? 'TESTE — níveis simulados' : 'Nicky OOH — risco operacional'}</strong>${group.items.map(item => `<hr><b>${escapeHtml(item.code)}</b><br>Nível: ${escapeHtml(item.risk.name)}${item.action ? `<br>Ação: ${escapeHtml(item.action)}` : ''}${item.models ? `<br>Modelos: ${escapeHtml(item.models)}` : ''}${item.ecmwf ? `<br>Rodada ECMWF: ${escapeHtml(item.ecmwf)}` : ''}${item.gefs ? `<br>Rodada GEFS: ${escapeHtml(item.gefs)}` : ''}`).join('')}<hr><small>Classificação da última geração Nicky. Mover o horário do Windy não recalcula o risco.</small></div>`;
}
