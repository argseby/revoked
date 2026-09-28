<script lang="ts">
  let {
    label,
    value = $bindable(),
    type = 'text',
    placeholder,
    hint,
    error,
    maxlength,
    autocomplete,
    required = false,
    disabled = false,
    onblur,
  }: {
    label: string;
    value?: string | number | null;
    type?: 'text' | 'email' | 'password' | 'url' | 'number' | 'date';
    placeholder?: string;
    hint?: string;
    error?: string | null;
    maxlength?: number;
    autocomplete?: AutoFill;
    required?: boolean;
    disabled?: boolean;
    onblur?: () => void;
  } = $props();

  const id = `f-${Math.random().toString(36).slice(2, 9)}`;
</script>

<div class="field">
  <label for={id}>{label}</label>
  <input
    {id}
    {type}
    bind:value
    {placeholder}
    {maxlength}
    {autocomplete}
    {required}
    {disabled}
    {onblur}
    aria-invalid={error ? 'true' : undefined}
    aria-describedby={hint || error ? `${id}-note` : undefined}
  />
  {#if error}
    <p id="{id}-note" class="small note bad">{error}</p>
  {:else if hint}
    <p id="{id}-note" class="small note muted">{hint}</p>
  {/if}
</div>

<style>
  .field {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }
  label {
    font-size: 12px;
    font-weight: 600;
    color: var(--fg-muted);
  }
  input {
    min-height: 40px;
    padding: 0 var(--space-3);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background: var(--surface);
    width: 100%;
  }
  input:focus {
    border-color: var(--primary);
    outline: 1px solid var(--primary);
  }
  input[aria-invalid='true'] {
    border-color: var(--bad);
  }
  .bad {
    color: var(--bad);
  }
</style>
