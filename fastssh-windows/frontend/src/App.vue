<script setup>
import { ref, computed } from 'vue'
import Sidebar from './components/Sidebar.vue'
import SessionView from './components/SessionView.vue'
import ConnectionDialog from './components/ConnectionDialog.vue'

const connections = ref([])
const sessions = ref([])
const activeSessionId = ref(null)
const showConnDialog = ref(false)
const editingConn = ref(null)

const activeSession = computed(() => sessions.value.find(s => s.id === activeSessionId.value))

async function loadConnections() {
  connections.value = await window.go.main.App.GetConnections()
}

async function connect(conn) {
  try {
    await window.go.main.App.Connect(conn.id)
    sessions.value.push({ id: conn.id, name: conn.name, host: conn.host })
    activeSessionId.value = conn.id
  } catch (e) {
    alert('Connection failed: ' + e)
  }
}

function disconnect(sessionId) {
  window.go.main.App.Disconnect(sessionId)
  sessions.value = sessions.value.filter(s => s.id !== sessionId)
  if (activeSessionId.value === sessionId) {
    activeSessionId.value = sessions.value.length > 0 ? sessions.value[sessions.value.length - 1].id : null
  }
}

function openNewConn() {
  editingConn.value = null
  showConnDialog.value = true
}

function editConn(conn) {
  editingConn.value = conn
  showConnDialog.value = true
}

async function saveConn(conn) {
  await window.go.main.App.SaveConnection(conn)
  showConnDialog.value = false
  await loadConnections()
}

async function deleteConn(id) {
  await window.go.main.App.DeleteConnection(id)
  await loadConnections()
}

loadConnections()
</script>

<template>
  <div class="app-layout">
    <Sidebar
      :connections="connections"
      :sessions="sessions"
      :activeSessionId="activeSessionId"
      @connect="connect"
      @disconnect="disconnect"
      @new-connection="openNewConn"
      @edit-connection="editConn"
      @delete-connection="deleteConn"
      @select-session="id => activeSessionId = id"
    />
    <main class="main-content">
      <SessionView v-if="activeSession" :session="activeSession" :key="activeSession.id" />
      <div v-else class="welcome">
        <h1>FastSSH</h1>
        <p>Connect to a server to get started</p>
        <button class="btn-primary" @click="openNewConn">+ New Connection</button>
      </div>
    </main>
    <ConnectionDialog
      v-if="showConnDialog"
      :connection="editingConn"
      @save="saveConn"
      @close="showConnDialog = false"
    />
  </div>
</template>

<style scoped>
.app-layout {
  display: flex;
  height: 100%;
  width: 100%;
}

.main-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.welcome {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  gap: 12px;
}

.welcome h1 {
  font-size: 28px;
  color: var(--accent);
}

.welcome p {
  color: var(--text-secondary);
}

.btn-primary {
  background: var(--accent);
  color: var(--bg-primary);
  font-weight: 600;
  padding: 8px 16px;
}
</style>
