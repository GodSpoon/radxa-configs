#!/bin/bash
# DietPi VNC Server X11 Authorization Fix
# Repository: https://github.com/GodSpoon/radxa-configs
# Usage: curl -sSL https://raw.githubusercontent.com/GodSpoon/radxa-configs/refs/heads/main/dietpi/vnc.sh | sudo bash

set -e

echo "========================================"
echo "DietPi VNC Server Configuration Script"
echo "========================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check if this is a DietPi system
if [ ! -f /boot/dietpi.txt ]; then
    echo "Warning: /boot/dietpi.txt not found. This may not be a DietPi system."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Step 1: Installing VNC server if not present..."
if ! command -v tigervncserver >/dev/null 2>&1; then
    echo "Installing TigerVNC server..."
    if command -v dietpi-software >/dev/null 2>&1; then
        dietpi-software install 120
    else
        apt-get update
        apt-get install -y tigervnc-standalone-server tigervnc-scraping-server
    fi
else
    echo "TigerVNC already installed."
fi

echo "Step 2: Configuring systemd service for X11 authorization..."
cat > /etc/systemd/system/vncserver.service << 'EOF'
[Unit]
Description=VNC Server (DietPi)
Before=xrdp.service xrdp-sesman.service
Wants=network-online.target
After=network-online.target

[Service]
RemainAfterExit=yes
PAMName=login
User=root
Environment=HOME=/root
Environment=XAUTHORITY=/var/run/lightdm/root/:0
ExecStart=/usr/local/bin/vncserver start
ExecStop=/usr/local/bin/vncserver stop

[Install]
WantedBy=multi-user.target
EOF

echo "Step 3: Configuring TigerVNC for screen sharing..."
mkdir -p /etc/tigervnc

cat > /etc/tigervnc/vncserver.users << 'EOF'
# TigerVNC User assignment for screen sharing
# This assigns root to share display :0
:0=root
EOF

cat > /etc/tigervnc/vncserver-config-mandatory << 'EOF'
# TigerVNC mandatory configuration for screen sharing
# Force scraping mode for display :0
$localhost = "no";
$geometry = "2048x1536";
$scrapingGeometry = undef;  # Share full screen
$SecurityTypes = "VncAuth";
$AlwaysShared = "yes";
EOF

echo "Step 4: Updating DietPi VNC configuration..."
if [ -f /boot/dietpi.txt ]; then
    # Update or add VNC configuration in dietpi.txt
    cp /boot/dietpi.txt /boot/dietpi.txt.bak
    
    # Remove existing VNC config lines
    sed -i '/^SOFTWARE_VNCSERVER_/d' /boot/dietpi.txt
    
    # Add new VNC configuration
    cat >> /boot/dietpi.txt << 'EOF'

# VNC Server Configuration (Auto-configured)
SOFTWARE_VNCSERVER_WIDTH=2048
SOFTWARE_VNCSERVER_HEIGHT=1536
SOFTWARE_VNCSERVER_DEPTH=24
SOFTWARE_VNCSERVER_DISPLAY_INDEX=0
SOFTWARE_VNCSERVER_SHARE_DESKTOP=1
EOF
    echo "Updated /boot/dietpi.txt with VNC configuration."
fi

echo "Step 5: Setting up VNC password..."
mkdir -p /root/.vnc
if [ ! -f /root/.vnc/passwd ]; then
    echo "VNC password file not found. You'll need to set one manually:"
    echo "Run: sudo vncpasswd"
    echo "Or create one automatically with a default password (not recommended for production):"
    read -p "Set default password 'dietpi123'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "dietpi123" | vncpasswd -f > /root/.vnc/passwd
        chmod 600 /root/.vnc/passwd
        echo "Default VNC password set to 'dietpi123'"
        echo "WARNING: Change this password immediately for security!"
    fi
else
    echo "VNC password file already exists."
fi

echo "Step 6: Enabling and starting VNC service..."
systemctl daemon-reload
systemctl enable vncserver.service
systemctl restart vncserver.service

echo "Step 7: Checking service status..."
sleep 2
if systemctl is-active --quiet vncserver.service; then
    echo "✅ VNC service is running successfully!"
    
    # Get IP address
    IP=$(hostname -I | cut -d' ' -f1)
    echo ""
    echo "========================================"
    echo "VNC Server Setup Complete!"
    echo "========================================"
    echo "Connect to: $IP:5900"
    echo "Resolution: 2048x1536 (shared desktop)"
    echo "Security: VNC Authentication required"
    echo ""
    echo "To check status: sudo systemctl status vncserver.service"
    echo "To view logs: sudo journalctl -u vncserver.service -f"
    echo "========================================"
else
    echo "❌ VNC service failed to start. Checking logs..."
    systemctl status vncserver.service --no-pager
    echo ""
    echo "Check logs with: sudo journalctl -u vncserver.service -f"
    exit 1
fi

echo "Script completed successfully!"
