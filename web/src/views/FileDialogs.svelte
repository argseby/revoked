<script lang="ts">
  import Dialog from '../components/Dialog.svelte';
  import { t } from '../lib/i18n.svelte';
  import { staging } from '../lib/staging.svelte';
  import PreviewDialog from './PreviewDialog.svelte';
  import RedactionEditor from './RedactionEditor.svelte';
  import StagingDialog from './StagingDialog.svelte';
</script>

<!-- The upload, view and redact dialogs, shared by Documents and About you. -->
<StagingDialog />
<PreviewDialog />
<Dialog open={staging.editorOpen} full title={t('redact.title')} onclose={() => staging.cancelEditor()}>
  <RedactionEditor oncancel={() => staging.cancelEditor()} ondone={(out) => staging.applyRedaction(out)} />
</Dialog>
