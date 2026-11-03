import type { ExternalPluginConfig } from '@windy/interfaces';
const config: ExternalPluginConfig = {
  name: 'windy-plugin-nicky',
  version: '0.2.0',
  title: 'Nicky OOH — Risco dos painéis',
  icon: '📍',
  description: 'Painéis Nicky com triagem por janela de 24 h sincronizada à barra de tempo do Windy.',
  author: 'Nicky OOH',
  private: true,
  desktopUI: 'embedded',
  mobileUI: 'small',
  routerPath: '/nicky-ooh',
};
export default config;
