const TAG_DISPLAY_MAP: Record<string, string> = {
  cbd: 'CBD',
  full6k: 'Full 6k',
  full10k: 'Full 10k',
  gummy: 'Gummy',
  pomada: 'Pomada',
  lubrificante: 'Lub',
};

/**
 * Returns a human-friendly display name for a product.
 * Uses the tag field to look up the display name, falling back to
 * the tag itself or nome_oficial.
 */
export function getProductDisplayName(product: { tag?: string; nome_oficial?: string } | null | undefined): string {
  if (!product) return '—';
  const tag = product.tag?.toLowerCase() || '';
  return TAG_DISPLAY_MAP[tag] || product.tag || product.nome_oficial || '—';
}

/**
 * Given a raw tag string, return the display name.
 */
export function getTagDisplayName(tag: string): string {
  return TAG_DISPLAY_MAP[tag?.toLowerCase()] || tag || '—';
}
