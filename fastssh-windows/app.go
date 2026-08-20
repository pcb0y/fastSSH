package main

import (
	"context"
	"fmt"
	"strings"
	"sync"

	"fastssh-windows/backend"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// App struct
type App struct {
	ctx      context.Context
	sessions map[string]*backend.SSHSession
	sftps    map[string]*backend.SFTPService
	config   *backend.ConfigService
	appCfg   *backend.AppConfig
	mu       sync.Mutex
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{
		sessions: make(map[string]*backend.SSHSession),
		sftps:    make(map[string]*backend.SFTPService),
		config:   backend.NewConfigService(),
	}
}

// startup is called when the app starts
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	cfg, _ := a.config.Load()
	a.appCfg = cfg
}

// ============ Connection Management ============

func (a *App) GetConnections() []backend.ConnectionConfig {
	if a.appCfg == nil {
		return []backend.ConnectionConfig{}
	}
	return a.appCfg.Connections
}

func (a *App) SaveConnection(conn backend.ConnectionConfig) {
	a.mu.Lock()
	defer a.mu.Unlock()

	// Update existing or add new
	found := false
	for i, c := range a.appCfg.Connections {
		if c.ID == conn.ID {
			a.appCfg.Connections[i] = conn
			found = true
			break
		}
	}
	if !found {
		a.appCfg.Connections = append(a.appCfg.Connections, conn)
	}
	a.config.Save(a.appCfg)
}

func (a *App) DeleteConnection(id string) {
	a.mu.Lock()
	defer a.mu.Unlock()

	for i, c := range a.appCfg.Connections {
		if c.ID == id {
			a.appCfg.Connections = append(a.appCfg.Connections[:i], a.appCfg.Connections[i+1:]...)
			break
		}
	}
	a.config.Save(a.appCfg)
}

// ============ SSH Session ============

func (a *App) Connect(connID string) error {
	a.mu.Lock()
	var conn *backend.ConnectionConfig
	for _, c := range a.appCfg.Connections {
		if c.ID == connID {
			cc := c
			conn = &cc
			break
		}
	}
	a.mu.Unlock()

	if conn == nil {
		return fmt.Errorf("connection not found")
	}

	session := backend.NewSSHSession(*conn, func(output string) {
		// Emit terminal output to frontend
		runtime.EventsEmit(a.ctx, "terminal-output-"+connID, output)
	})

	if err := session.Connect(); err != nil {
		return err
	}

	a.mu.Lock()
	a.sessions[connID] = session
	a.mu.Unlock()

	return nil
}

func (a *App) Disconnect(connID string) {
	a.mu.Lock()
	session := a.sessions[connID]
	sftp := a.sftps[connID]
	delete(a.sessions, connID)
	delete(a.sftps, connID)
	a.mu.Unlock()

	if sftp != nil {
		sftp.Close()
	}
	if session != nil {
		session.Disconnect()
	}
}

func (a *App) SendTerminalInput(connID string, data string) error {
	a.mu.Lock()
	session := a.sessions[connID]
	a.mu.Unlock()

	if session == nil {
		return fmt.Errorf("not connected")
	}
	return session.Send(data)
}

func (a *App) ResizeTerminal(connID string, cols, rows int) error {
	a.mu.Lock()
	session := a.sessions[connID]
	a.mu.Unlock()

	if session == nil {
		return nil
	}
	return session.Resize(cols, rows)
}

func (a *App) IsConnected(connID string) bool {
	a.mu.Lock()
	session := a.sessions[connID]
	a.mu.Unlock()

	if session == nil {
		return false
	}
	return session.IsConnected()
}

// ============ SFTP ============

func (a *App) ListRemoteDir(connID string, path string) ([]backend.FileItem, error) {
	sftp, err := a.getSFTP(connID)
	if err != nil {
		return nil, err
	}
	return sftp.ListDir(path)
}

func (a *App) UploadFile(connID string, localPath, remotePath string) error {
	sftp, err := a.getSFTP(connID)
	if err != nil {
		return err
	}
	return sftp.Upload(localPath, remotePath)
}

func (a *App) DownloadFile(connID string, remotePath, localPath string) error {
	sftp, err := a.getSFTP(connID)
	if err != nil {
		return err
	}
	return sftp.Download(remotePath, localPath)
}

func (a *App) MkdirRemote(connID string, path string) error {
	sftp, err := a.getSFTP(connID)
	if err != nil {
		return err
	}
	return sftp.MkdirAll(path)
}

func (a *App) RemoveRemote(connID string, path string) error {
	sftp, err := a.getSFTP(connID)
	if err != nil {
		return err
	}
	return sftp.Remove(path)
}

func (a *App) getSFTP(connID string) (*backend.SFTPService, error) {
	a.mu.Lock()
	defer a.mu.Unlock()

	if sftp, ok := a.sftps[connID]; ok {
		return sftp, nil
	}

	session := a.sessions[connID]
	if session == nil {
		return nil, fmt.Errorf("not connected")
	}

	sshClient := session.Client()
	if sshClient == nil {
		return nil, fmt.Errorf("SSH client not available")
	}

	sftp, err := backend.NewSFTPService(sshClient)
	if err != nil {
		return nil, err
	}
	a.sftps[connID] = sftp
	return sftp, nil
}

// ============ AI Agent ============

func (a *App) GetAIConfig() backend.AIConfig {
	if a.appCfg == nil {
		return backend.AIConfig{}
	}
	return a.appCfg.AI
}

func (a *App) SaveAIConfig(config backend.AIConfig) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.appCfg.AI = config
	a.config.Save(a.appCfg)
}

func (a *App) FetchModels(config backend.AIConfig) ([]string, error) {
	service := &backend.AIService{Config: config}
	return service.FetchModels()
}

func (a *App) AIChat(config backend.AIConfig, messages []map[string]string) (*backend.AIResponse, error) {
	service := &backend.AIService{Config: config}
	return service.Chat(messages)
}

func (a *App) ExecuteCommand(connID string, cmd string) (string, error) {
	a.mu.Lock()
	session := a.sessions[connID]
	a.mu.Unlock()

	if session == nil {
		return "", fmt.Errorf("not connected")
	}
	return session.ExecuteCommand(cmd)
}

// ============ Server Monitor ============

func (a *App) GetServerStats(connID string) (map[string]string, error) {
	a.mu.Lock()
	session := a.sessions[connID]
	a.mu.Unlock()

	if session == nil {
		return nil, fmt.Errorf("not connected")
	}

	script := `echo "===HOSTNAME==="; hostname; echo "===CPU==="; top -bn1 | head -3; echo "===MEMORY==="; free -h 2>/dev/null || vm_stat; echo "===DISK==="; df -h / 2>/dev/null`
	output, err := session.ExecuteCommand(script)
	if err != nil {
		return nil, err
	}

	stats := make(map[string]string)
	sections := strings.Split(output, "===")
	for i := 0; i < len(sections)-1; i += 2 {
		key := strings.TrimSpace(sections[i])
		if i+1 < len(sections) {
			val := strings.TrimSpace(sections[i+1])
			// Remove the key prefix from value
			val = strings.TrimPrefix(val, key+"===\n")
			stats[strings.ToLower(key)] = val
		}
	}

	// Simpler parsing
	stats["raw"] = output
	return stats, nil
}

// ============ Config Import/Export ============

func (a *App) ExportAllConfig() error {
	path, err := runtime.SaveFileDialog(a.ctx, runtime.SaveDialogOptions{
		Title:           "Export Configuration",
		DefaultFilename: "FastSSH_Config.json",
		Filters: []runtime.FileFilter{
			{DisplayName: "JSON Files", Pattern: "*.json"},
		},
	})
	if err != nil || path == "" {
		return err
	}
	return a.config.ExportConfig(a.appCfg, path)
}

func (a *App) ImportAllConfig() (string, error) {
	path, err := runtime.OpenFileDialog(a.ctx, runtime.OpenDialogOptions{
		Title: "Import Configuration",
		Filters: []runtime.FileFilter{
			{DisplayName: "JSON Files", Pattern: "*.json"},
		},
	})
	if err != nil || path == "" {
		return "", err
	}

	imported, err := a.config.ImportConfig(path)
	if err != nil {
		return "", err
	}

	// Merge connections
	added := 0
	for _, conn := range imported.Connections {
		exists := false
		for _, existing := range a.appCfg.Connections {
			if existing.Host == conn.Host && existing.Username == conn.Username && existing.Port == conn.Port {
				exists = true
				break
			}
		}
		if !exists {
			a.appCfg.Connections = append(a.appCfg.Connections, conn)
			added++
		}
	}

	// Import AI config
	if imported.AI.Provider != "" {
		a.appCfg.AI = imported.AI
	}

	a.config.Save(a.appCfg)
	return fmt.Sprintf("Imported %d of %d connections", added, len(imported.Connections)), nil
}
