<script lang="ts">
  import { t } from '../lib/i18n.svelte';
  import { confirm } from '../lib/confirm.svelte';
  import Button from './Button.svelte';
  import Dialog from './Dialog.svelte';
</script>

<Dialog open={!!confirm.request} title={confirm.request?.title ?? ''} onclose={() => confirm.answer(false)}>
  <p>{confirm.request?.message}</p>
  {#snippet footer()}
    <Button onclick={() => confirm.answer(false)}>{confirm.request?.cancel ?? t('common.cancel')}</Button>
    <Button variant={confirm.request?.destructive ? 'destructive' : 'primary'} onclick={() => confirm.answer(true)}>
      {confirm.request?.action}
    </Button>
  {/snippet}
</Dialog>
