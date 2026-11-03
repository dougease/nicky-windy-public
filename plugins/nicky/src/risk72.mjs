import { escapeHtml } from './pins.mjs';

export const LEVELS = Object.freeze([
  { name: 'Acompanhar', color: '#2E8B57', rank: 0 },
  { name: 'Verificar ≥54 km/h', color: '#E85D04', rank: 1 },
  { name: 'Verificar ≥90 km/h', color: '#C94C4C', rank: 2 },
]);
const HOUR = 3600000;

export function utcMillis(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/.test(value)) {
    throw new Error('Horário UTC inválido.');
  }
  const time = Date.parse(value.replace(' ', 'T') + 'Z');
  if (!Number.isFinite(time) || new Date(time).toISOString().replace('T', ' ').slice(0, 19) !== value) {
    throw new Error('Horário UTC inválido.');
  }
  return time;
}

export function classifyProb(p54, p90) {
  if (p90 >= 10) return LEVELS[2];
  if (p54 >= 30) return LEVELS[1];
  return LEVELS[0];
}

export function validateRisk72(data, now = Date.now()) {
  if (data?.versao !== 1 || !Number.isInteger(data.quantidade) || data.quantidade < 1 ||
      !Array.isArray(data.janelas) || data.janelas.length !== 3) {
    throw new Error('Arquivo de 72 h ausente ou incompatível.');
  }
  const start = utcMillis(data.rodadaUTC);
  if (!Number.isFinite(now) || now - start > 36 * HOUR || start - now > HOUR) {
    throw new Error('Rodada vencida ou futura. Nenhum risco será exibido.');
  }
  const codes = new Set();
  const places = new Map();
  for (const [index, window] of data.janelas.entries()) {
    const from = index * 24;
    if (window?.inicioH !== from || window?.fimH !== from + 24 ||
        utcMillis(window.validoDeUTC) !== start + from * HOUR ||
        utcMillis(window.validoAteUTC) !== start + (from + 24) * HOUR ||
        !Array.isArray(window.paineis) || window.paineis.length !== data.quantidade) {
      throw new Error('Janelas de previsão incompletas ou inconsistentes.');
    }
    const seen = new Set();
    for (const p of window.paineis) {
      if (typeof p?.code !== 'string' || !p.code.trim() || seen.has(p.code) ||
          !Number.isFinite(p.lat) || !Number.isFinite(p.lon) ||
          Math.abs(p.lat) > 90 || Math.abs(p.lon) > 180) {
        throw new Error('Painel ou coordenada inválida na previsão.');
      }
      seen.add(p.code);
      for (const key of ['ecmwf54', 'gefs54', 'ecmwf90', 'gefs90']) {
        if (!Number.isFinite(p[key]) || p[key] < 0 || p[key] > 100) {
          throw new Error('Probabilidade inválida na previsão.');
        }
      }
      if (p.ecmwf90 > p.ecmwf54 || p.gefs90 > p.gefs54) {
        throw new Error('Limiar de rajada inconsistente.');
      }
      if (index === 0) {
        codes.add(p.code);
        places.set(p.code, [p.lat, p.lon]);
      } else if (!codes.has(p.code) || places.get(p.code)[0] !== p.lat ||
                 places.get(p.code)[1] !== p.lon) {
        throw new Error('Painéis diferentes entre janelas.');
      }
    }
  }
  return data;
}

export function selectWindow(data, timestamp) {
  if (!Number.isFinite(timestamp)) return null;
  const hours = (timestamp - utcMillis(data.rodadaUTC)) / HOUR;
  if (hours < 0 || hours >= 72) return null;
  return data.janelas[Math.floor(hours / 24)];
}

export function prepareWindow(window) {
  const groups = new Map();
  for (const p of window.paineis) {
    const risk = classifyProb(Math.max(p.ecmwf54, p.gefs54), Math.max(p.ecmwf90, p.gefs90));
    const key = `${p.lon},${p.lat}`;
    if (!groups.has(key)) groups.set(key, { lon: p.lon, lat: p.lat, items: [], risk });
    const group = groups.get(key);
    group.items.push({ ...p, risk });
    if (risk.rank > group.risk.rank) group.risk = risk;
  }
  return [...groups.values()];
}

export function popupWindowHtml(group, window, rodadaUTC) {
  const itemHtml = group.items.map(item => `<hr><b>${escapeHtml(item.code)}</b><br>${escapeHtml(item.risk.name)}<br>ECMWF ≥54: ${item.ecmwf54.toFixed(1)}% · ≥90: ${item.ecmwf90.toFixed(1)}%<br>GEFS ≥54: ${item.gefs54.toFixed(1)}% · ≥90: ${item.gefs90.toFixed(1)}%`).join('');
  return `<div style="color:#182230;max-width:330px;max-height:300px;overflow:auto"><strong>Nicky OOH — triagem 72 h</strong><br>Janela ${window.inicioH}–${window.fimH} h · rodada ${escapeHtml(rodadaUTC)} UTC${itemHtml}<hr><small>Cor para a janela inteira de 24 h; o vento de fundo do Windy pode ter outra rodada. Confira alertas oficiais.</small></div>`;
}
