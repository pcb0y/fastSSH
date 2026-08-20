package backend

import (
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

// SSHSession manages a single SSH connection
type SSHSession struct {
	ID       string
	Config   ConnectionConfig
	client   *ssh.Client
	shell    *ssh.Session
	stdin    io.WriteCloser
	stdout   io.Reader
	mu       sync.Mutex
	connected bool
	onOutput func(string)
}

// ConnectionConfig holds SSH connection parameters
type ConnectionConfig struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Host     string `json:"host"`
	Port     int    `json:"port"`
	Username string `json:"username"`
	AuthType string `json:"authType"` // "password" or "key"
	Password string `json:"password"`
	KeyPath  string `json:"keyPath"`
	Group    string `json:"group"`
}

// NewSSHSession creates a new SSH session
func NewSSHSession(config ConnectionConfig, onOutput func(string)) *SSHSession {
	return &SSHSession{
		ID:       config.ID,
		Config:   config,
		onOutput: onOutput,
	}
}

// Connect establishes the SSH connection and starts a shell
func (s *SSHSession) Connect() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	var authMethods []ssh.AuthMethod
	if s.Config.AuthType == "key" {
		// Key-based auth would read the key file
		// For now, fallback to password
		authMethods = append(authMethods, ssh.Password(s.Config.Password))
	} else {
		authMethods = append(authMethods, ssh.Password(s.Config.Password))
	}

	sshConfig := &ssh.ClientConfig{
		User:            s.Config.Username,
		Auth:            authMethods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}

	addr := fmt.Sprintf("%s:%d", s.Config.Host, s.Config.Port)
	conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
	if err != nil {
		return fmt.Errorf("dial failed: %w", err)
	}

	c, chans, reqs, err := ssh.NewClientConn(conn, addr, sshConfig)
	if err != nil {
		conn.Close()
		return fmt.Errorf("ssh handshake failed: %w", err)
	}

	s.client = ssh.NewClient(c, chans, reqs)

	// Open a session for the interactive shell
	session, err := s.client.NewSession()
	if err != nil {
		s.client.Close()
		return fmt.Errorf("session failed: %w", err)
	}

	// Request PTY
	modes := ssh.TerminalModes{
		ssh.ECHO:          1,
		ssh.TTY_OP_ISPEED: 14400,
		ssh.TTY_OP_OSPEED: 14400,
	}
	if err := session.RequestPty("xterm-256color", 40, 120, modes); err != nil {
		session.Close()
		s.client.Close()
		return fmt.Errorf("pty request failed: %w", err)
	}

	stdin, err := session.StdinPipe()
	if err != nil {
		session.Close()
		s.client.Close()
		return fmt.Errorf("stdin pipe failed: %w", err)
	}

	stdout, err := session.StdoutPipe()
	if err != nil {
		session.Close()
		s.client.Close()
		return fmt.Errorf("stdout pipe failed: %w", err)
	}

	if err := session.Shell(); err != nil {
		session.Close()
		s.client.Close()
		return fmt.Errorf("shell failed: %w", err)
	}

	s.shell = session
	s.stdin = stdin
	s.stdout = stdout
	s.connected = true

	// Start reading output
	go s.readOutput()

	return nil
}

// Send writes data to the shell
func (s *SSHSession) Send(data string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.connected || s.stdin == nil {
		return fmt.Errorf("not connected")
	}
	_, err := s.stdin.Write([]byte(data))
	return err
}

// Resize changes the terminal size
func (s *SSHSession) Resize(cols, rows int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.connected || s.shell == nil {
		return nil
	}
	return s.shell.WindowChange(rows, cols)
}

// ExecuteCommand runs a command on a separate channel and returns output
func (s *SSHSession) ExecuteCommand(cmd string) (string, error) {
	s.mu.Lock()
	client := s.client
	s.mu.Unlock()

	if client == nil {
		return "", fmt.Errorf("not connected")
	}

	session, err := client.NewSession()
	if err != nil {
		return "", err
	}
	defer session.Close()

	output, err := session.CombinedOutput(cmd)
	return string(output), err
}

// Disconnect closes the SSH connection
func (s *SSHSession) Disconnect() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.connected = false
	if s.shell != nil {
		s.shell.Close()
	}
	if s.client != nil {
		s.client.Close()
	}
}

// IsConnected returns connection status
func (s *SSHSession) IsConnected() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.connected
}

// Client returns the underlying SSH client for SFTP
func (s *SSHSession) Client() *ssh.Client {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.client
}

func (s *SSHSession) readOutput() {
	buf := make([]byte, 4096)
	for {
		n, err := s.stdout.Read(buf)
		if n > 0 && s.onOutput != nil {
			s.onOutput(string(buf[:n]))
		}
		if err != nil {
			s.mu.Lock()
			s.connected = false
			s.mu.Unlock()
			return
		}
	}
}
