# Nicky OOH — risco de rajadas no Windy (72 h)

Plugin privado do Windy. Os pins usam a janela de 24 horas que contém o horário selecionado na barra de tempo: 0–24, 24–48 ou 48–72 h da rodada UTC. A troca ocorre nas fronteiras de 24 horas, não a cada hora.

## Fonte operacional

O plugin consulta `docs/windy/risco_72h.json` deste repositório público a cada cinco minutos. O arquivo é gerado por `scripts/gerar_windy_72h.R` **no computador que contém as previsões locais**. O script exige:

- `previsao_rajadas_ecmwf_janelas.csv` e `previsao_rajadas_gefs_janelas.csv` completos, da mesma rodada UTC;
- `paineis_analytics_atual.xlsx` (ou `paineis_analytics.xlsx`) com códigos e coordenadas;
- três janelas completas por painel e rodada com no máximo 36 horas.

O gerador grava o JSON em `docs/windy`. A tarefa do Windows deve executá-lo depois que **ambos** os modelos terminarem. Defina `NICKY_WINDY_GIT_PUBLISH=1` no ambiente dessa tarefa para fazer commit e push automático. A conta que roda a tarefa precisa ter autenticação Git para escrever neste repositório. Sem isso, o JSON fica somente no computador e o plugin não recebe novas previsões.

## Classificação

| Cor | Regra de triagem |
| --- | --- |
| Verde — Acompanhar | Nenhuma das duas condições abaixo |
| Laranja — Verificar ≥54 km/h | P(≥54 km/h) ≥30% em pelo menos um modelo |
| Vermelho — Verificar ≥90 km/h | P(≥90 km/h) ≥10% em pelo menos um modelo |

O maior nível entre ECMWF e GEFS prevalece. O popup mostra os dois percentuais por modelo e limiar. Não há interpolação horária, e a camada animada de vento do Windy pode usar outro modelo ou rodada. A triagem não dispensa alertas oficiais e o protocolo de segurança dos painéis.

O plugin rejeita JSON incompatível, coordenadas e probabilidades inválidas e rodadas vencidas. Fora de 0–72 h ou após 36 h sem nova rodada, remove os pins classificados em vez de mostrar risco antigo como atual. Uma falha temporária de rede preserva a última leitura válida até o vencimento.

## Teste e publicação

```sh
cd plugins/nicky
pnpm install --frozen-lockfile
pnpm test
pnpm run build
```

A validação pode ser disparada na branch pelo workflow **Validar plugin Nicky**. A versão 0.2.0 deve ser publicada somente após existir um JSON atual e válido no repositório. Na branch `main`, o workflow **Publicar plugin Nicky no Windy** usa o segredo `WINDY_API_KEY` do GitHub Actions, do produto **Windy Plugins API**. O link de instalação é entregue no resumo da execução. A versão 0.1.0 publicada continua ativa até essa publicação; não republicar uma versão com o mesmo número.

Documentação oficial: https://docs.windy-plugins.com/getting-started/publishing-plugin.html
