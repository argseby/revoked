<script lang="ts" generics="T extends string | number">
  let {
    options,
    value = $bindable(),
    label,
  }: { options: { value: T; label: string }[]; value: T; label: string } = $props();
</script>

<div class="seg" role="radiogroup" aria-label={label}>
  {#each options as o (o.value)}
    <button
      type="button"
      role="radio"
      aria-checked={value === o.value}
      class:on={value === o.value}
      onclick={() => (value = o.value)}>{o.label}</button
    >
  {/each}
</div>

<style>
  .seg {
    display: inline-flex;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    overflow: hidden;
  }
  button {
    border: 0;
    background: var(--surface);
    padding: var(--space-2) var(--space-4);
    cursor: pointer;
    font-weight: 550;
  }
  button + button {
    border-left: 1px solid var(--border);
  }
  button.on {
    background: var(--primary-subtle);
    color: var(--primary);
  }
</style>
