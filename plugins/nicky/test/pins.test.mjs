import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RISKS, prepare, classify, pinSvg, popupHtml } from '../src/pins.mjs';
const feature = (risk, code = 'A', coords = [-48.7,-26.9]) => ({ type:'Feature', geometry:{type:'Point',coordinates:coords}, properties:{risco:risk,code} });
const collection = features => ({type:'FeatureCollection', features});
test('as cinco classificações geram SVGs com as cores Nicky', () => {
  const expected=['#2E8B57','#E1C542','#FF9900','#E85D04','#C94C4C'];
  RISKS.forEach((risk,index)=>{
    const result=prepare(collection([feature(risk.name)]));
    assert.equal(result.groups[0].risk.color,expected[index]);
    assert.ok(pinSvg(result.groups[0].risk.color).includes(`fill="${expected[index]}"`));
  });
});
test('agrupa painéis coincidentes sem ocultar o risco maior', () => {
  const result = prepare(collection([feature('Normal'),feature('Crítico','B')]));
  assert.equal(result.count,2); assert.equal(result.groups.length,1);
  assert.equal(result.groups[0].risk.color,'#C94C4C'); assert.equal(result.groups[0].items.length,2);
});
test('não converte dado desconhecido em Normal e normaliza acentos', () => {
  assert.equal(classify('  atencao ').name,'Atenção');
  assert.equal(classify('indefinido').color,'#6B7280');
});
test('rejeita arquivo incompleto e separa simulação dos dados operacionais', () => {
  assert.throws(()=>prepare(collection([feature('Normal','A',[NaN,0])])));
  const f=feature('Normal'); f.properties.risco_simulado='Crítico'; f.properties.teste=true;
  assert.throws(()=>prepare(collection([f])));
  assert.equal(prepare(collection([f]),true).groups[0].risk.name,'Crítico');
});
test('escapa texto recebido no popup e impede injeção de cor no SVG', () => {
  const result=prepare(collection([feature('Normal','<img src=x onerror=alert(1)>')]));
  assert.ok(!popupHtml(result.groups[0],false).includes('<img'));
  assert.throws(()=>pinSvg('red" onload="alert(1)'));
});
