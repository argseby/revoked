<script lang="ts">
  import { t } from '../lib/i18n.svelte';
  import qrcode from 'qrcode-generator';

  let { text, size = 220 }: { text: string; size?: number } = $props();

  const cells = $derived.by(() => {
    const qr = qrcode(0, 'M');
    qr.addData(text);
    qr.make();
    const n = qr.getModuleCount();
    let d = '';
    for (let y = 0; y < n; y++) {
      for (let x = 0; x < n; x++) {
        if (qr.isDark(y, x)) d += `M${x + 4} ${y + 4}h1v1h-1z`;
      }
    }
    return { n: n + 8, d };
  });
</script>

<svg
  width={size}
  height={size}
  viewBox="0 0 {cells.n} {cells.n}"
  shape-rendering="crispEdges"
  role="img"
  aria-label={t('share.qr', { url: text })}
>
  <rect width={cells.n} height={cells.n} fill="#ffffff" />
  <path d={cells.d} fill="#000000" />
</svg>
