<template>
  <PModal title="Reminder" @close="$emit('close')">
    <div class="reminder-dialog">
      <div v-if="noteReminders.length" class="active-reminders">
        <h4>Active Reminders</h4>
        <div v-for="r in noteReminders" :key="r.id" class="reminder-item">
          <span>{{ formatDate(r.remindAt) }}</span>
          <span v-if="r.isRecurring" class="recurrence-badge">{{ r.recurrenceRule }}</span>
          <button class="btn" style="padding:4px 10px;font-size:0.8rem" @click="removeReminder(r.id)">Remove</button>
        </div>
      </div>

      <h4>Add Reminder</h4>
      <div class="form-row">
        <label>Date &amp; Time</label>
        <input type="datetime-local" v-model="remindAt" class="p-input" :min="minDate" />
      </div>
      <div class="form-row">
        <label>Recurring</label>
        <label class="p-switch">
          <input type="checkbox" v-model="isRecurring" />
        </label>
      </div>
      <div v-if="isRecurring" class="form-row">
        <label>Repeat</label>
        <select v-model="recurrenceRule" class="p-select">
          <option value="daily">Daily</option>
          <option value="weekly">Weekly</option>
          <option value="monthly">Monthly</option>
        </select>
      </div>

      <button class="btn btn-primary" style="margin-top:12px" @click="addReminder" :disabled="!remindAt">
        Set Reminder
      </button>
    </div>
  </PModal>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import PModal from './ui/PModal.vue'
import { useNotesStore } from '../stores/notes.js'

const props = defineProps({ note: { type: Object, required: true } })
const emit = defineEmits(['close'])

const store = useNotesStore()
const noteReminders = ref([])
const remindAt = ref('')
const isRecurring = ref(false)
const recurrenceRule = ref('daily')

const minDate = computed(() => new Date().toISOString().slice(0, 16))

onMounted(async () => {
  await store.fetchReminders()
  noteReminders.value = store.reminders.filter(r => r.noteId === props.note.id)
})

async function addReminder() {
  const ts = Math.floor(new Date(remindAt.value).getTime() / 1000)
  const r = await store.createReminder({
    noteId: props.note.id,
    remindAt: ts,
    isRecurring: isRecurring.value,
    recurrenceRule: isRecurring.value ? recurrenceRule.value : null,
  })
  noteReminders.value.push(r)
  remindAt.value = ''
  isRecurring.value = false
}

async function removeReminder(id) {
  await store.deleteReminder(id)
  noteReminders.value = noteReminders.value.filter(r => r.id !== id)
}

function formatDate(ts) { return new Date(ts * 1000).toLocaleString() }
</script>

<style lang="scss" scoped>
.reminder-dialog { min-width: 320px; }

h4 {
  font-size: 0.88rem;
  font-weight: 600;
  color: var(--color-text-lighter);
  text-transform: uppercase;
  margin: 16px 0 8px;
  &:first-child { margin-top: 0; }
}

.active-reminders { margin-bottom: 16px; }

.reminder-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px;
  border: 1px solid var(--color-border);
  border-radius: var(--border-radius, 6px);
  margin-bottom: 6px;
  font-size: 0.88rem;
}

.recurrence-badge {
  background: var(--color-primary-light);
  color: var(--color-primary-element);
  font-size: 0.75rem;
  padding: 2px 8px;
  border-radius: 999px;
}

.form-row {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 12px;
  label { min-width: 80px; font-size: 0.88rem; }
}
</style>
