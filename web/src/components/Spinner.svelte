<script lang="ts">
  import { t } from '../lib/i18n.svelte';
  let { large = false }: { large?: boolean } = $props();
</script>

<span class="spinner" class:large role="status" aria-label={t('common.loading')}></span>

<style>
  .spinner {
    display: inline-block;
    width: 14px;
    height: 14px;
    border: 2px solid currentColor;
    border-right-color: transparent;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
    flex-shrink: 0;
  }
  .large {
    width: 28px;
    height: 28px;
    border-width: 3px;
    color: var(--primary);
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
