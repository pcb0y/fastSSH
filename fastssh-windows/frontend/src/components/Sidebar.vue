<script setup>
const props = defineProps(['connections', 'sessions', 'activeSessionId'])
const emit = defineEmits(['connect', 'disconnect', 'new-connection', 'edit-connection', 'delete-connection', 'select-session'])
</script>

<template>
  <aside class="sidebar">
    <div class="sidebar-section">
      <div class="section-header">
        <span>Sessions</span>
      </div>
      <div v-for="s in sessions" :key="s.id"
           class="session-item"
           :class="{ active: s.id === activeSessionId }"
           @click="emit('select-session', s.id)">
        <span class="dot green"></span>
        <span class="name">{{ s.name }}</span>
        <button class="close-btn" @click.stop="emit('disconnect', s.id)">&times;</button>
      </div>
    </div>

    <div class="sidebar-section">
      <div class="section-header">
        <span>Connections</span>
        <button class="add-btn" @click="emit('new-connection')">+</button>
      </div>
      <div v-for="c in connections" :key="c.id" class="conn-item" @dblclick="emit('connect', c)">
        <span class="name">{{ c.name || c.host }}</span>
        <span class="host">{{ c.username }}@{{ c.host }}</span>
        <div class="conn-actions">
          <button @click="emit('connect', c)" title="Connect">▶</button>
          <button @click="emit('edit-connection', c)" title="Edit">✎</button>
          <button @click="emit('delete-connection', c.id)" title="Delete">✕</button>
        </div>
      </div>
      <div v-if="connections.length === 0" class="empty">No connections saved</div>
    </div>
  </aside>
</template>

<style scoped>
.sidebar {
  width: 200px;
  min-width: 200px;
  background: var(--bg-secondary);
  border-right: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  overflow-y: auto;
}

.sidebar-section {
  padding: 8px;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-secondary);
  padding: 4px 8px;
  margin-bottom: 4px;
}

.add-btn {
  background: transparent;
  color: var(--text-secondary);
  font-size: 16px;
  padding: 2px 6px;
}

.session-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 8px;
  border-radius: 6px;
  cursor: pointer;
}

.session-item:hover, .session-item.active {
  background: var(--bg-tertiary);
}

.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.dot.green { background: var(--green); }

.close-btn {
  margin-left: auto;
  background: transparent;
  color: var(--text-secondary);
  font-size: 14px;
  padding: 2px 4px;
}

.conn-item {
  padding: 6px 8px;
  border-radius: 6px;
  cursor: pointer;
  position: relative;
}

.conn-item:hover {
  background: var(--bg-tertiary);
}

.conn-item .name {
  display: block;
  font-weight: 500;
}

.conn-item .host {
  font-size: 11px;
  color: var(--text-secondary);
}

.conn-actions {
  display: none;
  position: absolute;
  right: 4px;
  top: 50%;
  transform: translateY(-50%);
  gap: 2px;
}

.conn-item:hover .conn-actions {
  display: flex;
}

.conn-actions button {
  background: transparent;
  color: var(--text-secondary);
  font-size: 11px;
  padding: 2px 4px;
}

.empty {
  color: var(--text-secondary);
  font-size: 11px;
  padding: 8px;
  text-align: center;
}
</style>
