import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateRisk72, selectWindow, prepareWindow, popupWindowHtml, utcMillis } from '../src/risk72.mjs';

const start = '2026-11-03 00:00:00';
const base = utcMillis(start);
function fixture() {
  return {
    versao: 1, rodadaUTC: start, quantidade: 2,
    janelas: [0, 24, 48].map((from, i) => ({
      inicioH: from, fimH: from + 24,
      validoDeUTC: new Date(base + from * 3600000).toISOString().replace('T', ' ').slice(0, 19),
      validoAteUTC: new Date(base + (from + 24) * 3600000).toISOString().replace('T', ' ').slice(0, 19),
      paineis: [
        { code: 'A', lat: -26.9, lon: -48.7, ecmwf54: i === 1 ? 40 : 0, gefs54: 0, ecmwf90: 0, gefs90: 0 },
        { code: 'B', lat: -26.9, lon: -48.7, ecmwf54: 15, gefs54: i === 2 ? 20 : 0, ecmwf90: 0, gefs90: i === 2 ? 10 : 0 },
      ],
    })),
  };
}

test('barra do Windy troca somente nas fronteiras de 24 horas', () => {
  const data = validateRisk72(fixture(), base + 5 * 3600000);
  assert.equal(selectWindow(data, base + 24 * 3600000 - 1).inicioH, 0);
  assert.equal(selectWindow(data, base + 24 * 3600000).inicioH, 24);
  assert.equal(selectWindow(data, base + 48 * 3600000).inicioH, 48);
  assert.equal(selectWindow(data, base + 72 * 3600000), null);
  assert.equal(selectWindow(data, base - 1), null);
});

test('cores usam o maior limiar conhecido por local e exibem ambos os modelos', () => {
  const data = validateRisk72(fixture(), base + 5 * 3600000);
  const a = prepareWindow(data.janelas[0]);
  const b = prepareWindow(data.janelas[1]);
  const c = prepareWindow(data.janelas[2]);
  assert.equal(a.length, 1);
  assert.equal(a[0].risk.name, 'Acompanhar');
  assert.equal(b[0].risk.name, 'Verificar ≥54 km/h');
  assert.equal(c[0].risk.name, 'Verificar ≥90 km/h');
  assert.match(popupWindowHtml(c[0], data.janelas[2], data.rodadaUTC), /GEFS ≥54/);
});

test('rejeita rodada vencida e janela ou painel incompleto', () => {
  assert.throws(() => validateRisk72(fixture(), base + 37 * 3600000), /vencida/);
  const missing = fixture();
  missing.janelas[1].paineis.pop();
  assert.throws(() => validateRisk72(missing, base + 5 * 3600000), /incompletas/);
  const swapped = fixture();
  swapped.janelas[2].paineis[1].code = 'C';
  assert.throws(() => validateRisk72(swapped, base + 5 * 3600000), /diferentes/);
});

test('não aceita percentuais artificiais nem HTML vindo do JSON', () => {
  const bad = fixture();
  bad.janelas[0].paineis[0].ecmwf90 = 5;
  assert.throws(() => validateRisk72(bad, base + 5 * 3600000), /inconsistente/);
  const data = fixture();
  data.janelas.forEach(w => { w.paineis[0].code = '<img onerror=alert(1)>'; });
  validateRisk72(data, base + 5 * 3600000);
  const html = popupWindowHtml(prepareWindow(data.janelas[0])[0], data.janelas[0], data.rodadaUTC);
  assert.ok(!html.includes('<img'));
});
