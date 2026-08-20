package backend

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// AppConfig holds all app configuration
type AppConfig struct {
	Connections []ConnectionConfig `json:"connections"`
	AI          AIConfig           `json:"aiConfig"`
}

// ConfigService manages configuration persistence
type ConfigService struct {
	configDir  string
	configFile string
}

// NewConfigService creates a config service
func NewConfigService() *ConfigService {
	configDir, _ := os.UserConfigDir()
	dir := filepath.Join(configDir, "FastSSH")
	os.MkdirAll(dir, 0755)

	return &ConfigService{
		configDir:  dir,
		configFile: filepath.Join(dir, "config.json"),
	}
}

// Load reads the config from disk
func (c *ConfigService) Load() (*AppConfig, error) {
	data, err := os.ReadFile(c.configFile)
	if err != nil {
		if os.IsNotExist(err) {
			return &AppConfig{}, nil
		}
		return nil, err
	}

	var config AppConfig
	if err := json.Unmarshal(data, &config); err != nil {
		return &AppConfig{}, nil
	}
	return &config, nil
}

// Save writes the config to disk
func (c *ConfigService) Save(config *AppConfig) error {
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(c.configFile, data, 0644)
}

// ExportConfig exports config to a specified path
func (c *ConfigService) ExportConfig(config *AppConfig, path string) error {
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

// ImportConfig imports config from a specified path
func (c *ConfigService) ImportConfig(path string) (*AppConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var config AppConfig
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, err
	}
	return &config, nil
}
