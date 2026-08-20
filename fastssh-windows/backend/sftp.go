package backend

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
)

// FileItem represents a file or directory
type FileItem struct {
	Name    string `json:"name"`
	Path    string `json:"path"`
	IsDir   bool   `json:"isDir"`
	Size    int64  `json:"size"`
	ModTime string `json:"modTime"`
}

// SFTPService handles SFTP operations
type SFTPService struct {
	client *sftp.Client
}

// NewSFTPService creates a new SFTP service from an SSH client
func NewSFTPService(sshClient *ssh.Client) (*SFTPService, error) {
	client, err := sftp.NewClient(sshClient)
	if err != nil {
		return nil, fmt.Errorf("sftp client failed: %w", err)
	}
	return &SFTPService{client: client}, nil
}

// ListDir lists files in a remote directory
func (s *SFTPService) ListDir(path string) ([]FileItem, error) {
	entries, err := s.client.ReadDir(path)
	if err != nil {
		return nil, err
	}

	var items []FileItem
	for _, entry := range entries {
		items = append(items, FileItem{
			Name:    entry.Name(),
			Path:    filepath.Join(path, entry.Name()),
			IsDir:   entry.IsDir(),
			Size:    entry.Size(),
			ModTime: entry.ModTime().Format(time.RFC3339),
		})
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].IsDir != items[j].IsDir {
			return items[i].IsDir
		}
		return items[i].Name < items[j].Name
	})

	return items, nil
}

// Download downloads a remote file to local path
func (s *SFTPService) Download(remotePath, localPath string) error {
	remoteFile, err := s.client.Open(remotePath)
	if err != nil {
		return err
	}
	defer remoteFile.Close()

	localFile, err := os.Create(localPath)
	if err != nil {
		return err
	}
	defer localFile.Close()

	_, err = io.Copy(localFile, remoteFile)
	return err
}

// Upload uploads a local file to remote path
func (s *SFTPService) Upload(localPath, remotePath string) error {
	localFile, err := os.Open(localPath)
	if err != nil {
		return err
	}
	defer localFile.Close()

	remoteFile, err := s.client.Create(remotePath)
	if err != nil {
		return err
	}
	defer remoteFile.Close()

	_, err = io.Copy(remoteFile, localFile)
	return err
}

// MkdirAll creates a remote directory
func (s *SFTPService) MkdirAll(path string) error {
	return s.client.MkdirAll(path)
}

// Remove removes a remote file or directory
func (s *SFTPService) Remove(path string) error {
	return s.client.Remove(path)
}

// Close closes the SFTP client
func (s *SFTPService) Close() {
	if s.client != nil {
		s.client.Close()
	}
}
