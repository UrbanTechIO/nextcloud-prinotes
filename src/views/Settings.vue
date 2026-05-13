<template>
  <div class="app-content">
    <div class="settings-page">
      <h2>PriNotes Settings</h2>

      <section class="settings-section">
        <h3>Version History</h3>
        <div class="setting-row">
          <label>Enable version history</label>
          <label class="p-switch">
            <input type="checkbox" v-model="settings.version_history_enabled" @change="save" />
          </label>
        </div>
        <div v-if="settings.version_history_enabled" class="setting-row">
          <label>Keep versions for (days)</label>
          <input type="number" v-model="settings.version_history_days" min="1" max="365"
            class="setting-input" @change="save" />
        </div>
      </section>

      <section class="settings-section">
        <h3>Trash</h3>
        <div class="setting-row">
          <label>Auto-delete trashed notes after (days)</label>
          <input type="number" v-model="settings.trash_auto_delete_days" min="0" max="365"
            class="setting-input" @change="save" />
          <span class="hint">0 = never</span>
        </div>
      </section>

      <section class="settings-section">
        <h3>Editor</h3>
        <div class="setting-row">
          <label>Auto-save interval (seconds)</label>
          <input type="number" v-model="settings.auto_save_interval" min="1" max="60"
            class="setting-input" @change="save" />
        </div>
        <div class="setting-row">
          <label>Default font size</label>
          <input type="number" v-model="settings.editor_font_size" min="12" max="24"
            class="setting-input" @change="save" />
        </div>
      </section>

      <section class="settings-section">
        <h3>Display</h3>
        <div class="setting-row">
          <label>Default sort</label>
          <select v-model="settings.default_sort" class="p-select" @change="save">
            <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
          </select>
        </div>
      </section>

      <section class="settings-section">
        <h3>Mobile App</h3>
        <p class="section-info">Connect the <strong>PriNotes</strong> Android app to this server:</p>
        <div class="connection-info">
          <div class="info-row">
            <span class="info-label">Server URL:</span>
            <code>{{ serverUrl }}</code>
            <button class="btn" style="padding:4px 10px;font-size:0.8rem" @click="copy(serverUrl)">Copy</button>
          </div>
          <div class="info-row">
            <span class="info-label">Your username:</span>
            <code>{{ currentUser }}</code>
          </div>
        </div>
        <p class="hint">Use an <strong>app password</strong> (Settings → Security → App passwords) in the mobile app.</p>
      </section>

      <p v-if="saved" class="save-msg">Settings saved!</p>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useNotesStore } from '../stores/notes.js'

const store = useNotesStore()

const settings = ref({
  version_history_enabled: true,
  version_history_days: '30',
  trash_auto_delete_days: '30',
  auto_save_interval: '5',
  editor_font_size: '16',
  default_sort: 'updated_desc',
})

const saved = ref(false)

const sortOptions = [
  { label: 'Last modified (newest first)', value: 'updated_desc' },
  { label: 'Last modified (oldest first)', value: 'updated_asc' },
  { label: 'Created (newest first)', value: 'created_desc' },
  { label: 'Title (A-Z)', value: 'title_asc' },
]

const serverUrl = window.location.origin
const currentUser = document.getElementById('prinotes-app')?.dataset.user ?? ''

onMounted(async () => {
  await store.fetchSettings()
  Object.assign(settings.value, store.settings)
})

async function save() {
  const payload = { ...settings.value }
  payload.version_history_enabled = settings.value.version_history_enabled ? 'true' : 'false'
  await store.saveSettings(payload)
  saved.value = true
  setTimeout(() => { saved.value = false }, 2000)
}

function copy(text) { navigator.clipboard.writeText(text) }
</script>

<style lang="scss" scoped>
.settings-page {
  padding: 24px;
  max-width: 700px;
  h2 { font-size: 1.3rem; margin-bottom: 24px; }
}

.settings-section {
  margin-bottom: 28px;
  padding-bottom: 24px;
  border-bottom: 1px solid var(--color-border);
  h3 { font-size: 1rem; font-weight: 600; margin: 0 0 14px; }
}

.setting-row {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-bottom: 14px;
  label { min-width: 220px; font-size: 0.9rem; }
  .hint { font-size: 0.78rem; color: var(--color-text-lighter); }
}

.setting-input {
  width: 80px;
  padding: 6px;
  border: 1px solid var(--color-border);
  border-radius: var(--border-radius, 6px);
  background: var(--color-main-background);
  color: var(--color-main-text);
}

.section-info { font-size: 0.88rem; margin-bottom: 12px; }

.connection-info {
  background: var(--color-background-dark);
  border-radius: var(--border-radius, 6px);
  padding: 12px 16px;
  margin-bottom: 12px;
}

.info-row {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 8px;
  font-size: 0.88rem;
  .info-label { min-width: 120px; color: var(--color-text-lighter); }
  code { flex: 1; }
}

.save-msg { color: var(--color-success); font-size: 0.88rem; margin-top: 16px; }
.hint { font-size: 0.82rem; color: var(--color-text-lighter); margin-bottom: 8px; }
</style>
