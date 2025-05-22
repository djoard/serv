#!/data/data/com.termux/files/usr/bin/bash

# Termux Complete Server Setup Script
# Compatible with Termux environment
# Run with: bash termux_server_setup.sh

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓ $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] ✗ $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] ⚠ $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] ℹ $1${NC}"
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local task=$3
    local percent=$((current * 100 / total))
    printf "\r${PURPLE}[%d/%d] (%d%%) %s...${NC}" $current $total $percent "$task"
    if [ $current -eq $total ]; then
        echo ""
    fi
}

# Check if running in Termux
check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        error "This script must be run in Termux!"
        echo "Please install Termux from F-Droid and run this script inside Termux."
        exit 1
    fi
    log "Termux environment detected"
}

# Install packages with error handling
install_packages() {
    log "Starting package installation"
    
    show_progress 1 8 "Updating package database"
    if ! pkg update -y >/dev/null 2>&1; then
        warning "Package update had some issues, continuing..."
    fi
    
    show_progress 2 8 "Upgrading existing packages"
    if ! pkg upgrade -y >/dev/null 2>&1; then
        warning "Package upgrade had some issues, continuing..."
    fi
    
    show_progress 3 8 "Installing core packages"
    pkg install -y python nginx openssh curl wget git nano >/dev/null 2>&1 || {
        error "Failed to install core packages"
        exit 1
    }
    
    show_progress 4 8 "Installing network utilities"
    pkg install -y net-tools >/dev/null 2>&1 || warning "Some network tools failed to install"
    
    show_progress 5 8 "Installing development tools"
    pkg install -y make clang openssl >/dev/null 2>&1 || warning "Some dev tools failed to install"
    
    show_progress 6 8 "Setting up Python environment"
    python -m pip install --upgrade pip >/dev/null 2>&1
    pip install flask requests >/dev/null 2>&1 || {
        error "Failed to install Python packages"
        exit 1
    }
    
    show_progress 7 8 "Installing additional utilities"
    pkg install -y tree zip unzip >/dev/null 2>&1 || warning "Some utilities failed to install"
    
    show_progress 8 8 "Package installation completed"
    log "All essential packages installed successfully"
}

# Create directory structure
create_directories() {
    log "Creating directory structure"
    
    mkdir -p $HOME/www/html
    mkdir -p $HOME/www/python
    mkdir -p $HOME/www/logs
    mkdir -p $HOME/www/ssl
    mkdir -p $HOME/.ssh
    mkdir -p $HOME/scripts
    
    log "Directory structure created"
}

# Configure Nginx
setup_nginx() {
    log "Configuring Nginx web server"
    
    # Backup original config if it exists
    if [ -f $PREFIX/etc/nginx/nginx.conf ]; then
        cp $PREFIX/etc/nginx/nginx.conf $PREFIX/etc/nginx/nginx.conf.backup
    fi
    
    # Create custom nginx configuration
    cat > $PREFIX/etc/nginx/nginx.conf << 'EOF'
worker_processes 1;
error_log /data/data/com.termux/files/home/www/logs/nginx_error.log;
pid /data/data/com.termux/files/usr/var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    
    access_log /data/data/com.termux/files/home/www/logs/nginx_access.log;
    
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    
    server {
        listen 8080;
        server_name localhost;
        root /data/data/com.termux/files/home/www/html;
        index index.html index.htm;
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location / {
            try_files $uri $uri/ =404;
        }
        
        # Proxy to Flask app
        location /api/ {
            proxy_pass http://127.0.0.1:5000/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        
        # Deny access to sensitive files
        location ~ /\. {
            deny all;
        }
    }
    
    server {
        listen 8443 ssl;
        server_name localhost;
        root /data/data/com.termux/files/home/www/html;
        index index.html;
        
        ssl_certificate /data/data/com.termux/files/home/www/ssl/server.crt;
        ssl_certificate_key /data/data/com.termux/files/home/www/ssl/server.key;
        
        location / {
            try_files $uri $uri/ =404;
        }
    }
}
EOF
    
    log "Nginx configuration completed"
}

# Create Python Flask application
create_python_app() {
    log "Creating Python Flask application"
    
    cat > $HOME/www/python/app.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import json
import socket
from datetime import datetime
from flask import Flask, render_template_string, jsonify, request

app = Flask(__name__)

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Termux Server Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Arial', sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: #333; 
            min-height: 100vh;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { 
            background: rgba(255,255,255,0.1); 
            color: white; 
            padding: 30px; 
            border-radius: 15px; 
            margin-bottom: 30px; 
            text-align: center;
            backdrop-filter: blur(10px);
        }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); 
            gap: 20px; 
            margin-bottom: 30px; 
        }
        .card { 
            background: rgba(255,255,255,0.95); 
            padding: 25px; 
            border-radius: 15px; 
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        .card h3 { color: #667eea; margin-bottom: 15px; }
        .status-online { color: #27ae60; font-weight: bold; }
        .metric { 
            display: flex; 
            justify-content: space-between; 
            margin: 10px 0; 
            padding: 8px 0; 
            border-bottom: 1px solid #eee; 
        }
        .metric:last-child { border-bottom: none; }
        .btn { 
            background: #667eea; 
            color: white; 
            padding: 12px 24px; 
            border: none; 
            border-radius: 8px; 
            cursor: pointer; 
            text-decoration: none; 
            display: inline-block; 
            margin: 5px;
            transition: all 0.3s;
        }
        .btn:hover { 
            background: #5a6fd8; 
            transform: translateY(-2px);
        }
        .footer { 
            text-align: center; 
            margin-top: 30px; 
            color: white; 
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Termux Server</h1>
            <p>Mobile Server Dashboard - {{ hostname }}</p>
        </div>
        
        <div class="grid">
            <div class="card">
                <h3>📊 System Status</h3>
                <div class="metric"><span>Python:</span><span class="status-online">{{ python_version }}</span></div>
                <div class="metric"><span>Platform:</span><span>{{ platform }}</span></div>
                <div class="metric"><span>Time:</span><span>{{ server_time }}</span></div>
                <div class="metric"><span>Status:</span><span class="status-online">Online</span></div>
            </div>
            
            <div class="card">
                <h3>🌐 Network</h3>
                <div class="metric"><span>HTTP:</span><span class="status-online">Port 8080</span></div>
                <div class="metric"><span>HTTPS:</span><span class="status-online">Port 8443</span></div>
                <div class="metric"><span>Flask:</span><span class="status-online">Port 5000</span></div>
                <div class="metric"><span>SSH:</span><span class="status-online">Port 8022</span></div>
            </div>
            
            <div class="card">
                <h3>🔗 Quick Access</h3>
                <a href="/" class="btn">🏠 Home</a>
                <a href="/api/status" class="btn">📡 Status</a>
                <a href="/api/info" class="btn">ℹ️ Info</a>
                <a href="http://localhost:8080" class="btn">🌐 Main Site</a>
            </div>
        </div>
        
        <div class="footer">
            <p>🔥 Powered by Termux • Flask • Nginx</p>
        </div>
    </div>
    
    <script>
        // Auto refresh every 60 seconds
        setTimeout(() => location.reload(), 60000);
    </script>
</body>
</html>
'''

def get_system_info():
    try:
        return {
            'python_version': sys.version.split()[0],
            'platform': sys.platform,
            'hostname': socket.gethostname(),
            'server_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }
    except:
        return {
            'python_version': 'Unknown',
            'platform': 'Android/Termux',
            'hostname': 'localhost',
            'server_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }

@app.route('/')
def home():
    return render_template_string(HTML_TEMPLATE, **get_system_info())

@app.route('/api/status')
def api_status():
    return jsonify({
        'status': 'online',
        'message': 'Termux server running',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/info')
def api_info():
    return jsonify(get_system_info())

@app.route('/api/test', methods=['GET', 'POST'])
def api_test():
    if request.method == 'POST':
        return jsonify({'method': 'POST', 'status': 'success'})
    return jsonify({'method': 'GET', 'status': 'success'})

if __name__ == '__main__':
    print("🚀 Starting Flask server on port 5000...")
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF
    
    chmod +x $HOME/www/python/app.py
    log "Python Flask application created"
}

# Create HTML content
create_html_content() {
    log "Creating HTML content"
    
    cat > $HOME/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Termux Server</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Arial', sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white; 
            min-height: 100vh; 
            display: flex; 
            align-items: center; 
            justify-content: center;
        }
        .container { max-width: 800px; padding: 40px; text-align: center; }
        .header h1 { font-size: 3.5em; margin-bottom: 20px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .header p { font-size: 1.3em; margin-bottom: 40px; opacity: 0.9; }
        .services { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin: 40px 0; 
        }
        .service { 
            background: rgba(255,255,255,0.1); 
            padding: 30px 20px; 
            border-radius: 15px; 
            text-decoration: none; 
            color: white; 
            transition: all 0.3s;
            backdrop-filter: blur(10px);
        }
        .service:hover { 
            transform: translateY(-10px); 
            background: rgba(255,255,255,0.2);
        }
        .service h3 { font-size: 1.5em; margin-bottom: 10px; }
        .status { 
            background: rgba(46, 204, 113, 0.2); 
            padding: 20px; 
            border-radius: 10px; 
            margin: 30px 0;
            border: 2px solid rgba(46, 204, 113, 0.5);
        }
        .footer { margin-top: 40px; opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Termux Server</h1>
            <p>Your Mobile Server is Online!</p>
        </div>
        
        <div class="status">
            <h2>✅ Server Status: RUNNING</h2>
            <p>All services are operational</p>
        </div>
        
        <div class="services">
            <a href="/" class="service">
                <h3>🌐 Web Server</h3>
                <p>Nginx on Port 8080</p>
            </a>
            
            <a href="http://localhost:5000" class="service">
                <h3>🐍 Flask App</h3>
                <p>Python on Port 5000</p>
            </a>
            
            <a href="https://localhost:8443" class="service">
                <h3>🔒 HTTPS</h3>
                <p>Secure Port 8443</p>
            </a>
            
            <div class="service">
                <h3>🔑 SSH</h3>
                <p>Remote Port 8022</p>
            </div>
        </div>
        
        <div class="footer">
            <p>🔥 Powered by Termux • Built with ❤️</p>
            <p>Server started: <span id="time"></span></p>
        </div>
    </div>
    
    <script>
        document.getElementById('time').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF
    
    log "HTML content created"
}

# Setup SSH
setup_ssh() {
    log "Setting up SSH server"
    
    # Generate SSH key if not exists
    if [ ! -f $HOME/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 2048 -f $HOME/.ssh/id_rsa -N "" >/dev/null 2>&1
    fi
    
    # Create SSH config
    cat > $PREFIX/etc/ssh/sshd_config << 'EOF'
Port 8022
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PrintMotd yes
Subsystem sftp $PREFIX/libexec/sftp-server
EOF
    
    log "SSH server configured"
}

# Create SSL certificates
create_ssl_certificates() {
    log "Creating SSL certificates"
    
    openssl req -x509 -newkey rsa:2048 -keyout $HOME/www/ssl/server.key -out $HOME/www/ssl/server.crt -days 365 -nodes -subj "/C=US/ST=Mobile/L=Termux/O=Server/CN=localhost" >/dev/null 2>&1
    
    chmod 600 $HOME/www/ssl/server.key
    chmod 644 $HOME/www/ssl/server.crt
    
    log "SSL certificates created"
}

# Create management scripts
create_management_scripts() {
    log "Creating management scripts"
    
    # Start servers script
    cat > $HOME/start_servers.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

echo "🚀 Starting Termux Server Stack..."

# Check and start Nginx
if pgrep nginx >/dev/null 2>&1; then
    echo "⚠️  Nginx already running"
else
    if nginx -t >/dev/null 2>&1; then
        nginx
        echo "✅ Nginx started (HTTP: 8080, HTTPS: 8443)"
    else
        echo "❌ Nginx configuration error"
        nginx -t
    fi
fi

# Check and start Python Flask
if pgrep -f "python.*app.py" >/dev/null 2>&1; then
    echo "⚠️  Flask server already running"
else
    cd ~/www/python
    nohup python app.py > ~/www/logs/flask.log 2>&1 &
    echo "✅ Flask server started (Port: 5000)"
fi

# Check and start SSH
if pgrep sshd >/dev/null 2>&1; then
    echo "⚠️  SSH server already running"
else
    sshd
    echo "✅ SSH server started (Port: 8022)"
fi

sleep 2
echo ""
echo "🌟 Server Status:"
echo "📊 Dashboard: http://localhost:8080"
echo "🐍 Flask App: http://localhost:5000"
echo "🔒 HTTPS: https://localhost:8443"
echo "🔑 SSH: ssh -p 8022 \$USER@localhost"
echo ""
echo "✨ All servers are running!"
EOF
    
    # Stop servers script
    cat > $HOME/stop_servers.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

echo "🛑 Stopping Termux Server Stack..."

# Stop Nginx
if pgrep nginx >/dev/null 2>&1; then
    nginx -s quit >/dev/null 2>&1
    echo "✅ Nginx stopped"
else
    echo "ℹ️  Nginx not running"
fi

# Stop Flask
if pgrep -f "python.*app.py" >/dev/null 2>&1; then
    pkill -f "python.*app.py"
    echo "✅ Flask server stopped"
else
    echo "ℹ️  Flask server not running"
fi

# Stop SSH
if pgrep sshd >/dev/null 2>&1; then
    pkill sshd
    echo "✅ SSH server stopped"
else
    echo "ℹ️  SSH server not running"
fi

echo ""
echo "🏁 All servers stopped"
EOF
    
    # Monitor script
    cat > $HOME/monitor_server.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

echo "📊 Termux Server Status"
echo "======================="
echo "Time: $(date)"
echo ""

echo "🌐 Network Info:"
echo "  Local IP: $(ip route get 8.8.8.8 2>/dev/null | awk '{print $7}' | head -1 || echo 'Unknown')"
echo ""

echo "⚙️  Service Status:"
if pgrep nginx >/dev/null 2>&1; then
    echo "  🌐 Nginx: ✅ Running"
else
    echo "  🌐 Nginx: ❌ Stopped"
fi

if pgrep -f "python.*app.py" >/dev/null 2>&1; then
    echo "  🐍 Flask: ✅ Running"
else
    echo "  🐍 Flask: ❌ Stopped"
fi

if pgrep sshd >/dev/null 2>&1; then
    echo "  🔑 SSH: ✅ Running"
else
    echo "  🔑 SSH: ❌ Stopped"
fi

echo ""
echo "🔌 Active Ports:"
netstat -tlnp 2>/dev/null | grep -E "(8080|8443|5000|8022)" || echo "  No active ports found"

echo ""
echo "🔗 Access URLs:"
echo "  📊 Main: http://localhost:8080"
echo "  🐍 Flask: http://localhost:5000"
echo "  🔒 HTTPS: https://localhost:8443"
EOF
    
    # Make scripts executable
    chmod +x $HOME/start_servers.sh
    chmod +x $HOME/stop_servers.sh
    chmod +x $HOME/monitor_server.sh
    
    log "Management scripts created"
}

# Main installation
main() {
    clear
    echo -e "${PURPLE}"
    cat << 'EOF'
 _____ _____ ____  __  __ _   ___  __
|_   _| ____|  _ \|  \/  | | | \ \/ /
  | | |  _| | |_) | |\/| | | | |\  / 
  | | | |___|  _ <| |  | | |_| |/  \ 
  |_| |_____|_| \_\_|  |_|\___//_/\_\
                                    
   ____  _____ ______     _______ ____  
  / ___|| ____|  _ \ \   / / ____|  _ \ 
  \___ \|  _| | |_) \ \ / /|  _| | |_) |
   ___) | |___|  _ < \ V / | |___|  _ < 
  |____/|_____|_| \_\ \_/  |_____|_| \_\
                                       
EOF
    echo -e "${NC}"
    
    info "🚀 Termux Complete Server Setup"
    info "This will install: Nginx + Python Flask + SSH + SSL"
    echo ""
    
    read -p "Continue with installation? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    echo ""
    log "Starting installation..."
    
    # Run installation steps
    check_termux
    install_packages
    create_directories
    setup_nginx
    create_python_app
    create_html_content
    setup_ssh
    create_ssl_certificates
    create_management_scripts
    
    # Create log files
    touch $HOME/www/logs/nginx_access.log
    touch $HOME/www/logs/nginx_error.log
    touch $HOME/www/logs/flask.log
    
    # Final message
    clear
    echo -e "${GREEN}"
    cat << 'EOF'
🎉 INSTALLATION COMPLETE! 🎉

Your Termux server is ready!
EOF
    echo -e "${NC}"
    echo ""
    
    log "Installation completed successfully!"
    echo ""
    info "📋 Available Commands:"
    echo "  ./start_servers.sh   - Start all servers"
    echo "  ./stop_servers.sh    - Stop all servers"
    echo "  ./monitor_server.sh  - Check status"
    echo ""
    
    info "🌐 Access URLs (after starting):"
    echo "  Main Site: http://localhost:8080"
    echo "  Flask App: http://localhost:5000"
    echo "  HTTPS: https://localhost:8443"
    echo ""
    
    read -p "Start servers now? (Y/n): " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        bash $HOME/start_servers.sh
    else
        echo ""
        info "Run './start_servers.sh' when ready!"
    fi
    
    echo ""
    log "🎊 Setup complete! Enjoy your Termux server!"
}

# Run installation
main "$@"
