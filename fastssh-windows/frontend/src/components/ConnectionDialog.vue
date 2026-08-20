<script setup>
import { ref } from 'vue'

const props = defineProps(['connection'])
const emit = defineEmits(['save', 'close'])

const form = ref({
  id: props.connection?.id || crypto.randomUUID(),
  name: props.connection?.name || '',
  host: props.connection?.host || '',
  port: props.connection?.port || 22,
  username: props.connection?.username || 'root',
  authType: props.connection?.authType || 'password',
  password: props.connection?.password || '',
  keyPath: props.connection?.keyPath || '',
  group: props.connection?.group || '',
})

function save() {
  if (!form.value.host || !form.value.username) return
  emit('save', { ...form.value })
}
</script>

<template>
  <div class="overlay" @click.self="emit('close')">
    <div class="dialog">
      <h3>{{ connection ? 'Edit Connection' : 'New Connection' }}</h3>
      <div class="form">
        <label>Name<input v-model="form.name" placeholder="My Server" /></label>
        <label>Host<input v-model="form.host" placeholder="192.168.1.1" required /></label>
        <label>Port<input v-model.number="form.port" type="number" /></label>
        <label>Username<input v-model="form.username" /></label>
        <label>Auth Method
          <select v-model="form.authType">
            <option value="password">Password</option>
            <option value="key">SSH Key</option>
          </select>
        </label>
        <label v-if="form.authType === 'password'">Password<input v-model="form.password" type="password" /></label>
        <label v-else>Key Path<input v-model="form.keyPath" placeholder="~/.ssh/id_rsa" /></label>
        <label>Group<input v-model="form.group" placeholder="Optional" /></label>
      </div>
      <div class="actions">
        <button class="btn-cancel" @click="emit('close')">Cancel</button>
        <button class="btn-save" @click="save">Save</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
}

.dialog {
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 24px;
  width: 380px;
}

.dialog h3 {
  margin-bottom: 16px;
}

.form {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.form label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 12px;
  color: var(--text-secondary);
}

.form input, .form select {
  width: 100%;
}

.actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 20px;
}

.btn-cancel {
  background: var(--bg-tertiary);
  color: var(--text-primary);
}

.btn-save {
  background: var(--accent);
  color: var(--bg-primary);
  font-weight: 600;
}
</style>
