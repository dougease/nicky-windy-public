# Nicky OOH — mapa Windy sincronizado (72 h)

Esta página mostra os painéis da Nicky OOH no Windy. A barra de tempo escolhe uma das janelas de previsão de 24 horas: 0–24, 24–48 ou 48–72 h a partir da rodada UTC dos arquivos. A classificação muda na fronteira das janelas, não a cada hora. A página não calcula a previsão diretamente; consome o JSON produzido pelo script R.

## Arquivos

- `docs/windy/index.html`: página do mapa.
- `scripts/gerar_windy_72h.R`: valida ECMWF, GEFS e os painéis e escreve `docs/windy/risco_72h.json`.
- `docs/index.html`: redireciona para a página Windy.

## Dados e execução no computador Windows

Clone este repositório em `C:\Users\Douglas\Documents\NICKY OOH\Climatologia\Nicky_Windy_Public`. Deixe na pasta `Climatologia` os arquivos gerados pelos atualizadores:

- `previsao_rajadas_ecmwf_janelas.csv`
- `previsao_rajadas_gefs_janelas.csv`
- `paineis_analytics_atual.xlsx` ou `paineis_analytics.xlsx`

Instale os pacotes R `readxl` e `jsonlite`. Depois de **ambos** os atualizadores terminarem com êxito, execute o script R:

```powershell
Rscript.exe "C:\Users\Douglas\Documents\NICKY OOH\Climatologia\Nicky_Windy_Public\scripts\gerar_windy_72h.R"
```

O gerador exige a mesma rodada UTC, três janelas completas, coordenadas válidas e dados recentes. Ao falhar, não publica nova previsão. Por padrão, grava o JSON somente no clone local. Para enviar automaticamente ao GitHub, a tarefa que executa o script deve definir `NICKY_WINDY_GIT_PUBLISH=1` e ter autenticação Git de push já configurada. A tarefa deve rodar **após** as tarefas ECMWF e GEFS, não em paralelo com elas.

Ative GitHub Pages em **Settings → Pages → Deploy from a branch → main → /docs**. Uma chave Windy **Map Forecast API** autorizada para o domínio publicado é necessária para abrir o mapa; informe-a no campo da página. Não grave a chave neste repositório.

## Leitura operacional

A cor considera o maior percentual entre os dois modelos para cada limiar: ≥90 km/h com pelo menos 10% mostra "Verificar ≥90 km/h"; ≥54 km/h com pelo menos 30% mostra "Verificar ≥54 km/h"; os demais aparecem como "Acompanhar". Esta triagem não substitui alertas oficiais, inspeção local e o protocolo de baixar lonas.

A página oculta dados com mais de 36 horas e horários fora de 0–72 h. O vento animado do Windy pode usar outro modelo/rodada; a cor é da classificação calculada pelos CSVs locais.
