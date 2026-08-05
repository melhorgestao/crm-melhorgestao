// Cores canônicas de canal — MESMAS em todo o CRM (Dashboard, Métricas, tags
// de Pedidos, etc). Paleta validada CVD-safe (slots da dataviz).
//   ADS  = azul   · BASE = laranja · REP/C-REP = verde-água
export const CANAL_HEX: Record<string, string> = {
  ADS: '#2a78d6',
  BASE: '#eb6834',
  REP: '#1baf7a',
  'C-REP': '#1baf7a',
};

export function canalHex(canal?: string): string {
  return CANAL_HEX[String(canal || '').toUpperCase()] || '#64748b';
}
