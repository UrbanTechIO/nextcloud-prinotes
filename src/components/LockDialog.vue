<template>
  <PModal :title="note.isLocked ? 'Manage Note Lock' : 'Lock Note'" @close="$emit('close')">
    <div class="lock-dialog">
      <div v-if="note.isLocked" class="lock-status">
        <Lock :size="32" class="lock-icon" />
        <p>This note is currently locked with a PIN.</p>
        <div v-if="!showRemoveConfirm" style="display:flex;gap:8px;margin-top:8px">
          <button class="btn btn-error" @click="showRemoveConfirm = true">Remove Lock</button>
          <button class="btn" @click="showChangePIN = true">Change PIN</button>
        </div>
        <div v-else class="remove-confirm">
          <p style="font-size:0.88rem;margin-bottom:8px">Enter your current PIN to remove the lock:</p>
          <input type="password" v-model="removePIN" inputmode="numeric" maxlength="8"
            placeholder="Current PIN" class="pin-input" @keydown.enter="removeLock" />
          <p v-if="removeError" class="error-msg">{{ removeError }}</p>
          <div style="display:flex;gap:8px;margin-top:8px">
            <button class="btn" @click="showRemoveConfirm = false; removePIN = ''; removeError = ''">Cancel</button>
            <button class="btn btn-error" @click="removeLock">Confirm Remove</button>
          </div>
        </div>
      </div>

      <div v-if="!note.isLocked || showChangePIN" class="set-lock">
        <h4>{{ note.isLocked ? 'Change PIN' : 'Set a PIN for this note' }}</h4>
        <p class="hint">The PIN protects this note within the app.</p>

        <div class="pin-input-row">
          <label>PIN (4–8 digits)</label>
          <input type="password" v-model="pin" inputmode="numeric" pattern="[0-9]*"
            maxlength="8" minlength="4" placeholder="····" class="pin-input" />
        </div>
        <div class="pin-input-row">
          <label>Confirm PIN</label>
          <input type="password" v-model="pinConfirm" inputmode="numeric" pattern="[0-9]*"
            maxlength="8" placeholder="····" class="pin-input" />
        </div>
        <p v-if="pinError" class="error-msg">{{ pinError }}</p>

        <button class="btn btn-primary" @click="saveLock" :disabled="!canSave">
          {{ note.isLocked ? 'Update PIN' : 'Lock Note' }}
        </button>
      </div>
    </div>
  </PModal>
</template>

<script setup>
import { ref, computed } from 'vue'
import PModal from './ui/PModal.vue'
import Lock from 'vue-material-design-icons/Lock.vue'
import { useNotesStore } from '../stores/notes.js'

const props = defineProps({ note: { type: Object, required: true } })
const emit = defineEmits(['saved', 'close'])

const store = useNotesStore()
const pin = ref('')
const pinConfirm = ref('')
const showChangePIN = ref(false)
const showRemoveConfirm = ref(false)
const removePIN = ref('')
const removeError = ref('')

const pinError = computed(() => {
  if (pin.value && pin.value.length < 4) return 'PIN must be at least 4 digits'
  if (pin.value && !/^\d+$/.test(pin.value)) return 'PIN must contain only digits'
  if (pinConfirm.value && pin.value !== pinConfirm.value) return 'PINs do not match'
  return null
})

const canSave = computed(() => pin.value.length >= 4 && pin.value === pinConfirm.value && !pinError.value)

async function saveLock() {
  const hash = await hashPin(pin.value)
  await store.updateNote(props.note.id, { isLocked: true, lockPinHash: hash })
  emit('saved')
}

async function removeLock() {
  if (!removePIN.value || removePIN.value.length < 4) {
    removeError.value = 'Enter your current PIN'
    return
  }
  const hash = await hashPin(removePIN.value)
  if (hash !== props.note.lockPinHash) {
    removeError.value = 'Incorrect PIN'
    removePIN.value = ''
    return
  }
  await store.updateNote(props.note.id, { isLocked: false, lockPinHash: null })
  emit('saved')
}

async function hashPin(p) {
  const data = new TextEncoder().encode(p + ':prinotes-salt')
  const buf = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('')
}
</script>

<style lang="scss" scoped>
.lock-dialog { min-width: 300px; }

.lock-status {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 8px;
  text-align: center;
  .lock-icon { color: var(--color-warning); }
}

.set-lock {
  h4 { font-size: 0.95rem; font-weight: 600; margin: 0 0 8px; }
  .hint { font-size: 0.82rem; color: var(--color-text-lighter); margin-bottom: 16px; }
}

.pin-input-row {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 12px;
  label { min-width: 100px; font-size: 0.88rem; }
}

.pin-input {
  flex: 1;
  padding: 10px 12px;
  border: 1px solid var(--color-border);
  border-radius: var(--border-radius, 6px);
  font-size: 1.2rem;
  letter-spacing: 0.3em;
  text-align: center;
  background: var(--color-main-background);
  color: var(--color-main-text);
}

.error-msg { color: var(--color-error); font-size: 0.82rem; margin-bottom: 12px; }
</style>
