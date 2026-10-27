import type { ExternalPluginConfig } from '@windy/interfaces';
const config: ExternalPluginConfig = {
  name: 'windy-plugin-nicky',
  version: '0.1.0',
  title: 'Nicky OOH — Risco dos painéis',
  icon: '📍',
  description: 'Painéis Nicky com pins por risco operacional e atualização a cada cinco minutos.',
  author: 'Nicky OOH',
  private: true,
  desktopUI: 'embedded',
  mobileUI: 'small',
  routerPath: '/nicky-ooh',
};
export default config;
