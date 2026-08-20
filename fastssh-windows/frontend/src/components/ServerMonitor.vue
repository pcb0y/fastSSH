<script setup>
import { ref, onMounted, onUnmounted } from 'vue'

const props = defineProps(['sessionId'])
const stats = ref(null)
const error = ref('')
const loading = ref(false)
let timer = null

async function fetchStats() {
  loading.value = true
  try {
    const result = await window.go.main.App.GetServerStats(props.sessionId)
    stats.value = result
    error.value = ''
  } catch (e) {
    error.value = e.toString()
  }
  loading.value = false
}

onMounted(() => {
  fetchStats()
  timer = setInterval(fetchStats, 5000)
})

onUnmounted(() => {
  if (timer) clearInterval(timer)
})
</script>

<template>
  <div class="monitor">
    <div class="monitor-header">
      <span>Server Monitor</span>
      <button @click="fetchStats" :disabled="loading">{{ loading ? '...' : '🔄 Refresh' }}</button>
    </div>

    <div v-if="error" class="error">{{ error }}</div>

    <div v-if="stats" class="stats-content scrollbar">
      <pre class="stats-raw">{{ stats.raw }}</pre>
    </div>

    <div v-else-if="!error" class="loading-msg">Loading server stats...</div>
  </div>
</template>

<style scoped>
.monitor {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.monitor-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 14px;
  border-bottom: 1px solid var(--border);
  font-weight: 600;
}

.monitor-header button {
  background: var(--bg-tertiary);
  color: var(--text-primary);
  font-size: 11px;
}

.stats-content {
  flex: 1;
  overflow-y: auto;
  padding: 14px;
}

.stats-raw {
  font-family: 'JetBrains Mono', 'Consolas', monospace;
  font-size: 12px;
  line-height: 1.6;
  white-space: pre-wrap;
  color: var(--text-primary);
  background: var(--bg-tertiary);
  padding: 12px;
  border-radius: 8px;
}

.error {
  padding: 14px;
  color: var(--red);
  font-size: 12px;
}

.loading-msg {
  padding: 14px;
  color: var(--text-secondary);
  text-align: center;
}
</style>
