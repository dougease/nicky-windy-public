# Nicky OOH — pins por risco dentro do Windy

Esta é uma integração pelo sistema oficial de plugins do Windy, não um arquivo para o carregador de GeoJSON/KML.

## O que está implementado

- Pins SVG desenhados diretamente na instância de mapa do Windy.
- Normal #2E8B57; Atenção #E1C542; Preparação #FF9900; Alerta #E85D04; Crítico #C94C4C.
- Leitura da fonte atual: https://raw.githubusercontent.com/dougease/nicky-windy-public/main/paineis_nicky.geojson
- Atualização de cinco em cinco minutos enquanto o plugin está aberto em modo operacional.
- Risco desconhecido em cinza, nunca convertido automaticamente para Normal.
- Painéis no mesmo par de coordenadas agrupados, com quantidade no pin e maior risco conhecido. Popup lista todos os painéis.
- Erros de rede ou arquivo inválido preservam os pins anteriores e exibem falha de atualização.
- Data de geração e horário da leitura visíveis; os dados podem estar antigos mesmo quando o download funciona.
- Botão de teste com cinco coordenadas reais e riscos simulados, identificado como TESTE. Para retomar a atualização, usar Dados atuais.
- Abrir o plugin não força zoom, modelo nem camada do Windy. O botão Localizar painéis move a visualização para a região, zoom 10.

A classificação vem do gerador Nicky; não é calculada a partir do vento sob o cursor. Mover a linha do tempo do Windy não altera a classificação recebida. A manutenção da fonte e sua publicação seguem no fluxo já existente.

## Como testar no Windy

Com Node.js instalado, abrir um terminal nesta pasta:

```text
npm install
npm test
npm run build
npm start
```

Se usar pnpm, a versão 11 pode pedir autorização de scripts de dependências; siga a política da sua instalação. Não é necessário atualizar os pacotes para usar este projeto.

O servidor de desenvolvimento usa HTTPS local, apenas em localhost:9999. A documentação oficial descreve a etapa manual de certificado local; qualquer decisão no aviso do navegador fica com o usuário/desenvolvedor:
https://docs.windy-plugins.com/getting-started/debugging.html

Abrir https://www.windy.com/developer-mode e carregar https://localhost:9999/plugin.js.

1. Fechar a importação GeoJSON antiga para evitar pins duplicados.
2. Selecionar Vento no Windy e manter um zoom regional, como 8 ou 9.
3. Abrir o plugin. Verificar geração da fonte e pins operacionais.
4. Clicar em Testar 5 cores e verificar todos os pins. Mover o mapa/zoom se necessário.
5. Clicar em Dados atuais para sair da simulação.
6. Testar um local com painéis coincidentes e conferir o popup.
7. Conferir mudança de camada, arraste e zoom; o plugin não deve selecionar Outdoor nem modificar o fundo.
8. Verificar falha de conexão e preservação da leitura anterior.

O próprio Windy pode passar para um fundo detalhado ao aproximar o mapa. Sua documentação descreve a transição em zoom alto; isso não é configurado pelo GeoJSON nem pelo plugin.

## Publicação para uso cotidiano

No repositório dougease/nicky-windy-public, o projeto fica em plugins/nicky.
Os workflows da pasta github-workflows deste pacote devem ficar na raiz do
repositório, em .github/workflows. A validação é executada nas alterações do
plugin; atualizações apenas do GeoJSON não acionam esse processo.

Em Settings → Secrets and variables → Actions, cadastrar WINDY_API_KEY como
Repository secret, com a chave Windy Plugins API. O segredo é usado apenas na
etapa final do workflow manual “Publicar plugin Nicky no Windy”. Depois de
salvar o segredo, executar esse workflow pela aba Actions, branch main. A URL
retornada pelo Windy fica no resumo da execução. Não reenviar a mesma versão;
para corrigir uma versão já publicada, aumentar version em src/pluginConfig.ts
e package.json e publicar de novo.

A compilação gera dist/plugin.js, dist/plugin.min.js e dist/plugin.json. O modo de desenvolvimento serve para homologação; não é a instalação permanente.

Para distribuir como plugin privado é necessária uma chave **Windy Plugins API**, da conta responsável, e publicação no serviço oficial. A assinatura Windy Premium não substitui essa etapa. Nenhuma chave foi criada e nenhuma publicação foi feita por este pacote.

O campo private:true retira o plugin da galeria pública, mas não é um controle de acesso aos dados. A fonte atual já é pública.

Guia oficial para publicação: https://docs.windy-plugins.com/getting-started/publishing-plugin.html
Caso o endereço tenha sido alterado, acessar Publishing your plugin no menu de https://docs.windy-plugins.com/.

Não inserir chaves no código nem enviar por chat. Publicar por fluxo oficial com segredo protegido ou ambiente local do desenvolvedor. Um plugin privado não requer solicitar inclusão na galeria pública.

## Limites da entrega

Os testes locais verificam cores, agrupamento, validação dos dados e separação de simulação. A execução real sobre a instância do mapa Windy depende da homologação acima; compilação não confirma integração visual em produção. O plugin só atualiza enquanto está aberto; fechar o navegador não interrompe o gerador Nicky, mas interrompe esta visualização.

## Referências técnicas

- Template oficial consultado: https://github.com/windycom/windy-plugin-template (v5.0.1 na consulta)
- Guia: https://docs.windy-plugins.com/getting-started/
- Exemplo de ícone SVG: examples/03-boat-tracker/boatIcon.ts do template oficial.
- Código de compilação rollup.config.js, tsconfig.json e svelte.config.js derivados do template oficial Windyty (ISC).

Estado de validação específico desta entrega: ver VALIDACAO.txt.
