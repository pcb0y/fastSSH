<script setup>
import { ref } from 'vue'
import TerminalTab from './TerminalTab.vue'
import FileBrowser from './FileBrowser.vue'
import ServerMonitor from './ServerMonitor.vue'
import AIPanel from './AIPanel.vue'

const props = defineProps(['session'])
const activeTab = ref('terminal')
const showAI = ref(false)
</script>

<template>
  <div class="session-view">
    <!-- Tab Bar -->
    <div class="tab-bar">
      <button :class="{ active: activeTab === 'terminal' }" @click="activeTab = 'terminal'">
        Terminal
      </button>
      <button :class="{ active: activeTab === 'files' }" @click="activeTab = 'files'">
        Files
      </button>
      <button :class="{ active: activeTab === 'monitor' }" @click="activeTab = 'monitor'">
        Monitor
      </button>
      <div class="spacer"></div>
      <button class="ai-btn" :class="{ active: showAI }" @click="showAI = !showAI">
        ✨ AI Agent
      </button>
    </div>

    <!-- Content -->
    <div class="content-area">
      <div class="main-panel">
        <TerminalTab v-if="activeTab === 'terminal'" :sessionId="session.id" />
        <FileBrowser v-else-if="activeTab === 'files'" :sessionId="session.id" />
        <ServerMonitor v-else :sessionId="session.id" />
      </div>
      <AIPanel v-if="showAI" :sessionId="session.id" />
    </div>
  </div>
</template>

<style scoped>
.session-view {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.tab-bar {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 4px 8px;
  background: var(--bg-secondary);
  border-bottom: 1px solid var(--border);
}

.tab-bar button {
  background: transparent;
  color: var(--text-secondary);
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 12px;
}

.tab-bar button.active {
  background: var(--bg-tertiary);
  color: var(--accent);
}

.spacer { flex: 1; }

.ai-btn {
  background: linear-gradient(135deg, rgba(203,166,247,0.15), rgba(137,180,250,0.15)) !important;
  color: var(--accent) !important;
  border: 1px solid rgba(203,166,247,0.4);
  font-weight: 600;
}

.ai-btn.active {
  background: linear-gradient(135deg, var(--accent), var(--blue)) !important;
  color: var(--bg-primary) !important;
  border-color: transparent;
}

.content-area {
  display: flex;
  flex: 1;
  overflow: hidden;
}

.main-panel {
  flex: 1;
  overflow: hidden;
}
</style>
