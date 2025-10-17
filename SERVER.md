# Proto Server - Installation Guide

## 🚀 Quick Installation

### Automatic Installation (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/DTunnel0/DTProto-Server-Releases/main/install-server.sh | sudo bash
```

This will install:
- ✅ `proto-server` - Main server binary
- ✅ `proto` - Interactive management tool

---

## 🎮 Management Tool

After installation, use the `proto` command to manage your server:

```bash
sudo proto
```

### Features

The interactive menu allows you to:

1. **Start Server** - Start the server on a specific port
2. **Stop Server** - Stop the running server
3. **Restart Server** - Restart the server
4. **Server Status** - View server status and configuration
5. **View Logs** - Follow server logs in real-time
6. **Change Port** - Change the listening port
7. **Change Token** - Update authentication token

### First Run

On first run, you'll be asked to enter your authentication token. The token will be:
- ✅ Validated against the API
- ✅ Saved securely for future use
- ✅ No need to enter it again

### Starting the Server

When you start the server, you'll be prompted for:
- **Port**: The port to listen on (e.g., 5000)
- **Virtual Subnet**: CIDR for the virtual network (default: 10.10.0.0/16)
- **TUN Interface**: Name of the TUN interface (default: tun0)

---

## 📦 Manual Installation

### 1. Download Binary

Download the binary for your architecture:

| Architecture | Binary Name |
|-------------|-------------|
| 64-bit x86 | `proto-server-linux-amd64` |
| 64-bit ARM | `proto-server-linux-arm64` |
| 32-bit ARM | `proto-server-linux-arm` |
| 32-bit x86 | `proto-server-linux-386` |

```bash
# Example for amd64
wget https://github.com/DTunnel0/DTProto-Server-Releases/releases/latest/download/proto-server-linux-amd64
chmod +x proto-server-linux-amd64
sudo mv proto-server-linux-amd64 /usr/local/bin/proto-server
```

### 2. Download Management Script

```bash
wget https://raw.githubusercontent.com/DTunnel0/DTProto-Server-Releases/main/proto-server.sh
chmod +x proto-server.sh
sudo mv proto-server.sh /usr/local/bin/proto
```

### 3. Run the Manager

```bash
sudo proto
```

---

## ⚙️ Direct Usage (Without Manager)

You can also run the server directly:

```bash
sudo proto-server --token YOUR_TOKEN
```

### Command Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `--token` | *required* | Authentication token |
| `--listen-addr` | `:5000` | Server listen address |
| `--virtual-subnet-cidr` | `10.10.0.0/16` | Virtual subnet for clients |
| `--tun` | `tun0` | TUN interface name |
| `--auth-file` | `credentials.json` | Authentication file path |
| `--stats-file` | `stats.json` | Statistics file path |
| `--tls-cert-file` | `cert.pem` | TLS certificate file |
| `--tls-key-file` | `""` | TLS key file (optional) |
| `--validate` | `false` | Validate token and exit |

### Example

```bash
sudo proto-server \
  --token YOUR_TOKEN \
  --listen-addr :5000 \
  --virtual-subnet-cidr 10.10.0.0/16 \
  --tun tun0 \
  --auth-file /var/lib/proto-server/credentials.json \
  --stats-file /var/lib/proto-server/stats.json
```

---

## 🔧 Systemd Service Management

When using `proto`, a systemd service is created:

```bash
# Check status
sudo systemctl status proto-server

# View logs
sudo journalctl -u proto-server -f

# Start/Stop/Restart manually
sudo systemctl start proto-server
sudo systemctl stop proto-server
sudo systemctl restart proto-server
```

---

## 📁 File Locations

### Configuration Files

| Path | Description |
|------|-------------|
| `/etc/proto-server/token` | Saved authentication token |
| `/etc/proto-server/config.conf` | Server configuration (port, subnet, tun) |
| `/etc/proto-server/cert.pem` | TLS certificate |
| `/etc/proto-server/key.pem` | TLS private key |

### Data Files

| Path | Description |
|------|-------------|
| `/var/lib/proto-server/credentials.json` | User credentials |
| `/var/lib/proto-server/stats.json` | Server statistics |

### System Files

| Path | Description |
|------|-------------|
| `/usr/local/bin/proto-server` | Server binary |
| `/usr/local/bin/proto` | Management script |
| `/etc/systemd/system/proto-server.service` | Systemd service |

---

## 🔐 Authentication

### Validate Token

Before using, validate your token:

```bash
proto-server --token YOUR_TOKEN --validate
```

### Credentials File Format

The credentials file (`credentials.json`) format:

```json
{
  "credentials": [
    {
      "username": "user1",
      "password": "password1"
    },
    {
      "username": "user2",
      "password": "password2"
    }
  ]
}
```

Edit this file at: `/var/lib/proto-server/credentials.json`

---

## 🔒 TLS Certificates

TLS certificates are automatically generated when you first start the server.

Certificates are stored at:
- `/etc/proto-server/cert.pem`
- `/etc/proto-server/key.pem`

To use custom certificates, replace these files and restart the service.

---

## 🔄 Update Server

Re-run the installation script to update:

```bash
curl -fsSL https://raw.githubusercontent.com/DTunnel0/DTProto-Server-Releases/main/install-server.sh | sudo bash
```

This will:
- Update the binary
- Update the management script
- Keep all your configurations and data

---

## 🗑️ Uninstall

### Complete Removal

```bash
# Stop the service
sudo systemctl stop proto-server
sudo systemctl disable proto-server

# Remove service file
sudo rm /etc/systemd/system/proto-server.service
sudo systemctl daemon-reload

# Remove configuration and data
sudo rm -rf /etc/proto-server
sudo rm -rf /var/lib/proto-server

# Remove binaries
sudo rm /usr/local/bin/proto-server
sudo rm /usr/local/bin/proto
```

---

## 💡 Usage Examples

### Example 1: Start Server

```bash
$ sudo proto

╔════════════════════════════════════════╗
║      Proto Server Manager v2.0         ║
║      by @DuTra01                       ║
╚════════════════════════════════════════╝

● Server is stopped

Main Menu:

  1. Start Server
  2. Stop Server
  3. Restart Server
  4. Server Status
  5. View Logs
  6. Change Port
  7. Change Token
  8. Exit

Select option: 1

Enter the port to start the server:
Port: 5000
Virtual subnet CIDR [current: 10.10.0.0/16]: 
TUN interface name [current: tun0]: 

[INFO] Creating service...
[INFO] Starting server on port 5000...
[✓] Server started successfully!

Port: 5000
TUN Interface: tun0
Virtual Subnet: 10.10.0.0/16
```

### Example 2: Change Port

```bash
Select option: 6

Current port: 5000

[!] Server is running! It will be restarted with the new port.

Enter new port: 5001
[✓] Port updated to 5001
[INFO] Recreating service...
[INFO] Restarting server...
[✓] Server restarted on new port!
```

### Example 3: View Status

```bash
Select option: 4

[✓] Server is running

Configuration:
  Port: 5000
  TUN Interface: tun0
  Virtual Subnet: 10.10.0.0/16

[INFO] Systemd Status:
● proto-server.service - Proto Server
   Loaded: loaded (/etc/systemd/system/proto-server.service; enabled)
   Active: active (running) since...
```

---

## 🐛 Troubleshooting

### Service Won't Start

Check the logs:

```bash
sudo journalctl -u proto-server -n 50
```

Or use the menu option "View Logs"

### Token Invalid

Use the menu to change token:

```bash
sudo proto
# Select: 7 (Change Token)
# Enter new token
```

### Port Already in Use

Check what's using the port:

```bash
sudo netstat -tlnp | grep :PORT
# or
sudo ss -tlnp | grep :PORT
```

Stop the conflicting service or choose a different port.

### TUN Interface Error

Load TUN module:

```bash
sudo modprobe tun
lsmod | grep tun
```

### Permission Denied

Make sure you're running with sudo:

```bash
sudo proto
```

---

## 📞 Support

- **Author**: Glemison C. DuTra (@DuTra01)
- **GitHub**: https://github.com/DTunnel0/DTProto

---

**Built with ❤️ by the DTunnel team**
