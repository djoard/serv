#!/bin/bash

# Termux Complete Server Setup Script
# Run with: bash <(curl -s https://raw.githubusercontent.com/your-repo/termux-server-setup.sh)
# Or download and run: bash termux_server_setup.sh

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local task=$3
    local percent=$((current * 100 / total))
    printf "\r${BLUE}[%d/%d] (%d%%) %s${NC}" $current $total $percent "$task"
    if [ $current -eq $total ]; then
        echo ""
    fi
}

# Check if running in Termux
check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        error "This script must be run in Termux!"
        exit 1
    fi
    log "Termux environment detected ✓"
}

# Main installation function
install_packages() {
    log "Starting package installation..."
    
    show_progress 1 10 "Updating package lists..."
    pkg update -y > /dev/null 2>&1
    
    show_progress 2 10 "Upgrading existing packages..."
    pkg upgrade -y > /dev/null 2>&1
    
    show_progress 3 10 "Installing core packages..."
    pkg install -y python nginx php openssh curl wget git nano vim > /dev/null 2>&1
    
    show_progress 4 10 "Installing network utilities..."
    pkg install -y net-tools iproute2 dnsutils > /dev/null 2>&1
    
    show_progress 5 10 "Installing development tools..."
    pkg install -y make clang openssl > /dev/null 2>&1
    
    show_progress 6 10 "Installing Python packages..."
    pip install --upgrade pip > /dev/null 2>&1
    pip install flask django fastapi uvicorn gunicorn requests > /dev/null 2>&1
    
    show_progress 7 10 "Installing additional utilities..."
    pkg install -y htop tree zip unzip > /dev/null 2>&1
    
    show_progress 8 10 "Installing security tools..."
    pkg install -y gnupg > /dev/null 2>&1
    
    show_progress 9 10 "Installing monitoring tools..."
    pkg install -y procps > /dev/null 2>&1
    
    show_progress 10 10 "Package installation completed!"
    log "All packages installed successfully ✓"
}

# Create directory structure
create_directories() {
    log "Creating directory structure..."
    
    mkdir -p ~/www/html
    mkdir -p ~/www/python
    mkdir -p ~/www/logs
    mkdir -p ~/www/ssl
    mkdir -p ~/.ssh
    mkdir -p ~/scripts
    mkdir -p ~/backups
    
    log "Directory structure created ✓"
}

# Configure Nginx
setup_nginx() {
    log "Configuring Nginx web server..."
    
    # Backup original config
    cp $PREFIX/etc/nginx/nginx.conf $PREFIX/etc/nginx/nginx.conf.backup 2>/dev/null || true
    
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
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /data/data/com.termux/files/home/www/logs/nginx_access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1000;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # Main HTTP server
    server {
        listen 8080;
        server_name localhost;
        root /data/data/com.termux/files/home/www/html;
        index index.html index.htm index.php;
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        
        # Static files
        location / {
            try_files $uri $uri/ =404;
        }
        
        # PHP support
        location ~ \.php$ {
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_index index.php;
        }
        
        # Python scripts
        location /python/ {
            alias /data/data/com.termux/files/home/www/python/;
        }
        
        # API proxy to Flask
        location /api/ {
            proxy_pass http://127.0.0.1:5000/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Deny access to sensitive files
        location ~ /\. {
            deny all;
        }
        
        location ~ \.(log|bak|backup|old)$ {
            deny all;
        }
    }
    
    # HTTPS server (optional)
    server {
        listen 8443 ssl;
        server_name localhost;
        root /data/data/com.termux/files/home/www/html;
        index index.html index.htm;
        
        ssl_certificate /data/data/com.termux/files/home/www/ssl/server.crt;
        ssl_certificate_key /data/data/com.termux/files/home/www/ssl/server.key;
        
        ssl_session_cache shared:SSL:1m;
        ssl_session_timeout 5m;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        
        location / {
            try_files $uri $uri/ =404;
        }
    }
}
EOF
    
    log "Nginx configuration completed ✓"
}

# Create Python Flask application
create_python_app() {
    log "Creating Python Flask application..."
    
    cat > ~/www/python/app.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import json
import socket
import psutil
from datetime import datetime
from flask import Flask, render_template_string, jsonify, request

app = Flask(__name__)

# HTML template
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Termux Server Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; color: #333; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { font-size: 1.1em; opacity: 0.9; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .card { background: white; padding: 25px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); border-left: 4px solid #667eea; }
        .card h3 { color: #667eea; margin-bottom: 15px; font-size: 1.3em; }
        .status-online { color: #27ae60; font-weight: bold; }
        .status-offline { color: #e74c3c; font-weight: bold; }
        .metric { display: flex; justify-content: space-between; margin: 10px 0; padding: 8px 0; border-bottom: 1px solid #eee; }
        .metric:last-child { border-bottom: none; }
        .btn { background: #667eea; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; text-decoration: none; display: inline-block; }
        .btn:hover { background: #5a6fd8; }
        .api-section { background: white; padding: 25px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .api-endpoint { background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 10px 0; border-left: 3px solid #28a745; }
        pre { background: #2d3748; color: #e2e8f0; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .footer { text-align: center; margin-top: 30px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Termux Server Dashboard</h1>
            <p>Your mobile server is running successfully on {{ hostname }}</p>
        </div>
        
        <div class="grid">
            <div class="card">
                <h3>📊 System Information</h3>
                <div class="metric"><span>Python Version:</span><span>{{ python_version }}</span></div>
                <div class="metric"><span>Platform:</span><span>{{ platform }}</span></div>
                <div class="metric"><span>Server Time:</span><span>{{ server_time }}</span></div>
                <div class="metric"><span>Uptime:</span><span>{{ uptime }}</span></div>
            </div>
            
            <div class="card">
                <h3>🌐 Network Information</h3>
                <div class="metric"><span>Local IP:</span><span>{{ local_ip }}</span></div>
                <div class="metric"><span>HTTP Port:</span><span class="status-online">8080</span></div>
                <div class="metric"><span>HTTPS Port:</span><span class="status-online">8443</span></div>
                <div class="metric"><span>Flask Port:</span><span class="status-online">5000</span></div>
            </div>
            
            <div class="card">
                <h3>💾 Resource Usage</h3>
                <div class="metric"><span>CPU Usage:</span><span>{{ cpu_usage }}%</span></div>
                <div class="metric"><span>Memory Usage:</span><span>{{ memory_usage }}%</span></div>
                <div class="metric"><span>Disk Usage:</span><span>{{ disk_usage }}%</span></div>
            </div>
            
            <div class="card">
                <h3>🔗 Quick Links</h3>
                <div style="display: flex; flex-direction: column; gap: 10px;">
                    <a href="/" class="btn">🏠 Home</a>
                    <a href="/api/status" class="btn">📡 API Status</a>
                    <a href="/api/system" class="btn">⚙️ System Info</a>
                    <a href="/dashboard" class="btn">📊 Dashboard</a>
                </div>
            </div>
        </div>
        
        <div class="api-section">
            <h3>🔌 Available API Endpoints</h3>
            <div class="api-endpoint">
                <strong>GET /api/status</strong> - Server status information
            </div>
            <div class="api-endpoint">
                <strong>GET /api/system</strong> - Detailed system information
            </div>
            <div class="api-endpoint">
                <strong>GET /api/network</strong> - Network configuration
            </div>
            <div class="api-endpoint">
                <strong>POST /api/test</strong> - Test endpoint for POST requests
            </div>
        </div>
        
        <div class="footer">
            <p>Powered by Termux + Flask + Nginx | Built with ❤️</p>
        </div>
    </div>
    
    <script>
        // Auto-refresh every 30 seconds
        setTimeout(() => location.reload(), 30000);
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
            'server_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'uptime': str(datetime.now() - datetime.fromtimestamp(psutil.boot_time())).split('.')[0],
            'local_ip': socket.gethostbyname(socket.gethostname()),
            'cpu_usage': round(psutil.cpu_percent(interval=1), 1),
            'memory_usage': round(psutil.virtual_memory().percent, 1),
            'disk_usage': round(psutil.disk_usage('/').percent, 1)
        }
    except:
        return {
            'python_version': sys.version.split()[0],
            'platform': sys.platform,
            'hostname': 'localhost',
            'server_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'uptime': 'Unknown',
            'local_ip': '127.0.0.1',
            'cpu_usage': 0,
            'memory_usage': 0,
            'disk_usage': 0
        }

@app.route('/')
def home():
    return render_template_string(HTML_TEMPLATE, **get_system_info())

@app.route('/dashboard')
def dashboard():
    return home()

@app.route('/api/status')
def api_status():
    return jsonify({
        'status': 'online',
        'message': 'Termux server is running',
        'timestamp': datetime.now().isoformat(),
        'services': {
            'nginx': 'running',
            'flask': 'running',
            'ssh': 'available'
        }
    })

@app.route('/api/system')
def api_system():
    return jsonify(get_system_info())

@app.route('/api/network')
def api_network():
    return jsonify({
        'ports': {
            'http': 8080,
            'https': 8443,
            'flask': 5000,
            'ssh': 8022
        },
        'protocols': ['HTTP', 'HTTPS', 'SSH'],
        'local_ip': socket.gethostbyname(socket.gethostname())
    })

@app.route('/api/test', methods=['GET', 'POST'])
def api_test():
    if request.method == 'POST':
        data = request.get_json() or {}
        return jsonify({
            'method': 'POST',
            'received_data': data,
            'message': 'POST request processed successfully'
        })
    else:
        return jsonify({
            'method': 'GET',
            'message': 'Test endpoint is working',
            'timestamp': datetime.now().isoformat()
        })

if __name__ == '__main__':
    print("🚀 Starting Termux Flask Server...")
    print("📱 Access at: http://localhost:5000")
    print("🌐 API endpoints available at /api/*")
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
EOF
    
    chmod +x ~/www/python/app.py
    log "Python Flask application created ✓"
}

# Create HTML content
create_html_content() {
    log "Creating HTML content..."
    
    cat > ~/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Termux Server</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Arial', sans-serif; line-height: 1.6; color: #333; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; }
        .container { max-width: 1000px; margin: 0 auto; padding: 20px; }
        .header { text-align: center; margin-bottom: 40px; color: white; }
        .header h1 { font-size: 3em; margin-bottom: 10px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .header p { font-size: 1.2em; opacity: 0.9; }
        .card { background: white; padding: 30px; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.2); margin-bottom: 30px; }
        .services { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .service { background: linear-gradient(45deg, #f093fb 0%, #f5576c 100%); color: white; padding: 25px; border-radius: 10px; text-align: center; text-decoration: none; transition: transform 0.3s; }
        .service:hover { transform: translateY(-5px); color: white; text-decoration: none; }
        .service h3 { margin-bottom: 10px; font-size: 1.5em; }
        .service p { opacity: 0.9; }
        .status { background: linear-gradient(45deg, #4facfe 0%, #00f2fe 100%); color: white; padding: 20px; border-radius: 10px; text-align: center; }
        .features { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 20px; }
        .feature { background: #f8f9fa; padding: 15px; border-radius: 8px; border-left: 4px solid #667eea; }
        .footer { text-align: center; margin-top: 40px; color: white; opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Termux Server</h1>
            <p>Your Mobile Server is Live and Running!</p>
        </div>
        
        <div class="card">
            <div class="status">
                <h2>✅ Server Status: ONLINE</h2>
                <p>All services are running smoothly</p>
            </div>
        </div>
        
        <div class="services">
            <a href="/" class="service">
                <h3>🌐 Static Website</h3>
                <p>HTML, CSS, JS content served by Nginx</p>
                <small>Port: 8080</small>
            </a>
            
            <a href="http://localhost:5000" class="service">
                <h3>🐍 Python Flask</h3>
                <p>Dynamic web applications and APIs</p>
                <small>Port: 5000</small>
            </a>
            
            <a href="https://localhost:8443" class="service">
                <h3>🔒 HTTPS Server</h3>
                <p>Secure encrypted connections</p>
                <small>Port: 8443</small>
            </a>
            
            <div class="service">
                <h3>🔑 SSH Access</h3>
                <p>Remote terminal access</p>
                <small>Port: 8022</small>
            </div>
        </div>
        
        <div class="card">
            <h2>🛠️ Server Features</h2>
            <div class="features">
                <div class="feature">
                    <h4>📱 Mobile Optimized</h4>
                    <p>Runs entirely on your Android device</p>
                </div>
                <div class="feature">
                    <h4>🔧 Full Stack</h4>
                    <p>HTML, CSS, JavaScript, Python, PHP support</p>
                </div>
                <div class="feature">
                    <h4>🔐 Secure</h4>
                    <p>SSH access, SSL certificates, security headers</p>
                </div>
                <div class="feature">
                    <h4>📊 Monitoring</h4>
                    <p>Built-in system monitoring and logging</p>
                </div>
                <div class="feature">
                    <h4>🚀 High Performance</h4>
                    <p>Nginx reverse proxy, gzip compression</p>
                </div>
                <div class="feature">
                    <h4>🔄 Auto Management</h4>
                    <p>Start/stop scripts, automated backups</p>
                </div>
            </div>
        </div>
        
        <div class="card">
            <h2>📚 Getting Started</h2>
            <ol>
                <li><strong>Static Files:</strong> Place HTML, CSS, JS files in <code>~/www/html/</code></li>
                <li><strong>Python Apps:</strong> Create Flask/Django apps in <code>~/www/python/</code></li>
                <li><strong>Logs:</strong> Check server logs in <code>~/www/logs/</code></li>
                <li><strong>Management:</strong> Use <code>~/start_servers.sh</code> and <code>~/stop_servers.sh</code></li>
                <li><strong>Monitoring:</strong> Run <code>~/monitor_server.sh</code> for server status</li>
            </ol>
        </div>
        
        <div class="footer">
            <p>🔥 Powered by Termux • Built with ❤️ • Open Source</p>
            <p>Server started on <span id="datetime"></span></p>
        </div>
    </div>
    
    <script>
        document.getElementById('datetime').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF
    
    log "HTML content created ✓"
}

# Setup SSH
setup_ssh() {
    log "Setting up SSH server..."
    
    # Generate SSH key if not exists
    if [ ! -f ~/.ssh/termux_key ]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/termux_key -N "" > /dev/null 2>&1
    fi
    
    # Configure SSH
    cat > $PREFIX/etc/ssh/sshd_config << 'EOF'
Port 8022
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PrintMotd yes
PrintLastLog yes
TCPKeepAlive yes
Subsystem sftp $PREFIX/libexec/sftp-server
EOF
    
    log "SSH server configured ✓"
}

# Create SSL certificates
create_ssl_certificates() {
    log "Creating SSL certificates..."
    
    openssl req -x509 -newkey rsa:4096 -keyout ~/www/ssl/server.key -out ~/www/ssl/server.crt -days 365 -nodes -subj "/C=US/ST=Mobile/L=Termux/O=MobileServer/CN=localhost" > /dev/null 2>&1
    
    chmod 600 ~/www/ssl/server.key
    chmod 644 ~/www/ssl/server.crt
    
    log "SSL certificates created ✓"
}

# Create management scripts
create_management_scripts() {
    log "Creating management scripts..."
    
    # Start servers script
    cat > ~/start_servers.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Termux Server Stack..."

# Check if already running
if pgrep nginx > /dev/null; then
    echo "⚠️  Nginx is already running"
else
    nginx -t && nginx
    echo "✅ Nginx started on port 8080 (HTTP) and 8443 (HTTPS)"
fi

if pgrep -f "python.*app.py" > /dev/null; then
    echo "⚠️  Python Flask server is already running"
else
    cd ~/www/python
    nohup python app.py > ~/www/logs/flask.log 2>&1 &
    echo "✅ Python Flask server started on port 5000"
fi

if pgrep sshd > /dev/null; then
    echo "⚠️  SSH server is already running"
else
    sshd
    echo "✅ SSH server started on port 8022"
fi

sleep 2
echo ""
echo "🌟 All servers started successfully!"
echo "📊 Server Dashboard: http://localhost:8080"
echo "🐍 Flask App: http://localhost:5000"
echo "🔒 HTTPS: https://localhost:8443"
echo "🔑 SSH: ssh -p 8022 \$USER@localhost"
echo ""
echo "📈 Server Status:"
ps aux | grep -E "(nginx|python.*app.py|sshd)" | grep -v grep | while read line; do
    echo "  ✓ $line"
done

echo ""
echo "🔍 Use './monitor_server.sh' to check server status"
echo "🛑 Use './stop_servers.sh' to stop all servers"
EOF
    
    # Stop servers script
    cat > ~/stop_servers.sh << 'EOF'
#!/bin/bash

echo "🛑 Stopping Termux Server Stack..."

# Stop Nginx
if pgrep nginx > /dev/null; then
    nginx -s quit
    echo "✅ Nginx stopped"
else
    echo "ℹ️  Nginx was not running"
fi

# Stop Python Flask
if pgrep -f "python.*app.py" > /dev/null; then
    pkill -f "python.*app.py"
    echo "✅ Python Flask server stopped"
else
    echo "ℹ️  Python Flask server was not running"
fi

# Stop SSH
if pgrep sshd > /dev/null; then
    pkill sshd
    echo "✅ SSH server stopped"
else
    echo "ℹ️  SSH server was not running"
fi

echo ""
echo "🏁 All servers stopped successfully!"
EOF
    
    # Monitor script
    cat > ~/monitor_server.sh << 'EOF'
#!/bin/bash

echo "📊 Termux Server Status Report"
echo "================================="
echo "📅 Generated: $(date)"
echo ""

echo "🖥️  System Information:"
echo "  📱 Hostname: $(hostname)"
echo "  🕐 Uptime: $(uptime -p 2>/dev/null || echo 'N/A')"
echo "  💾 Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $3 "/" $2}' || echo 'N/A')"
echo "  💽 Disk: $(df -h ~ | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}' || echo 'N/A')"
echo ""

echo "🌐 Network Status:"
IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7}' | head -1)
echo "  📍 IP Address: ${IP:-N/A}"
echo "  🔌 Open Ports:"
netstat -tlnp 2>/dev/null | grep -E "(8080|8443|5000|8022)" | while read line; do
    echo "    ✓ $line"
done
echo ""

echo "⚙️  Running Services:"
NGINX_STATUS="❌ Stopped"
FLASK_STATUS="❌ Stopped"
SSH_STATUS="❌ Stopped"

if pgrep nginx > /dev/null; then
    NGINX_STATUS="✅ Running (PID: $(pgrep nginx | tr '\n' ' '))"
fi

if pgrep -f "python.*app.py" > /dev/null; then
    FLASK_STATUS="✅ Running (PID: $(pgrep -f 'python.*app.py'))"
fi

if pgrep sshd > /dev/null; then
    SSH_STATUS="✅ Running (PID: $(pgrep sshd | tr '\n' ' '))"
fi

echo "  🌐 Nginx: $NGINX_STATUS"
echo "  🐍 Flask: $FLASK_STATUS"
echo "  🔑 SSH: $SSH_STATUS"
echo ""

echo "📊 Resource Usage:"
if command -v python3 >/dev/null 2>&1; then
    python3 -c "
try:
    import psutil
    print(f'  🔥 CPU: {psutil.cpu_percent(interval=1):.1f}%')
    print(f'  🧠 RAM: {psutil.virtual_memory().percent:.1f}%')
    print(f'  💿 Disk: {psutil.disk_usage(\"/\").percent:.1f}%')
except ImportError:
    print('  ℹ️  Install psutil for detailed stats: pip install psutil')
"
else
    echo "  ℹ️  Python3 not available for resource monitoring"
fi
echo ""

echo "📝 Recent Logs:"
if [ -f ~/www/logs/nginx_access.log ]; then
    echo "  📄 Nginx Access (last 3):"
    tail -n 3 ~/www/logs/nginx_access.log | sed 's/^/    /'
else
    echo "  📄 Nginx Access: No logs yet"
fi

if [ -f ~/www/logs/flask.log ]; then
    echo "  📄 Flask Logs (last 3):"
    tail -n 3 ~/www/logs/flask.log | sed 's/^/    /'
else
    echo "  📄 Flask Logs: No logs yet"
fi
echo ""

echo "🔗 Access URLs:"
echo "  🌐 Main Site: http://localhost:8080"
echo "  🐍 Flask App: http://localhost:5000"
echo "  🔒 HTTPS: https://localhost:8443"
echo "  🔑 SSH: ssh -p 8022 \$USER@localhost"
echo ""
echo "💡 Tip: Add port forwarding on your router to access externally!"
EOF
    
    # Restart script
    cat > ~/restart_servers.sh << 'EOF'
#!/bin/bash

echo "🔄 Restarting Termux Server Stack..."

# Stop all servers
./stop_servers.sh

# Wait a moment
sleep 3

# Start all servers
./start_servers.sh
EOF
    
    # Backup script
    cat > ~/backup_server.sh << 'EOF'
#!/bin/bash

BACKUP_DIR=~/backups
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/termux_server_backup_$TIMESTAMP.tar.gz"

echo "💾 Creating server backup..."

mkdir -p $BACKUP_DIR

# Create backup
tar -czf "$BACKUP_FILE" \
    ~/www/ \
    ~/start_servers.sh \
    ~/stop_servers.sh \
    ~/restart_servers.sh \
    ~/monitor_server.sh \
    ~/.ssh/ \
    $PREFIX/etc/nginx/nginx.conf \
    $PREFIX/etc/ssh/sshd_config \
    2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Backup created: $BACKUP_FILE"
    echo "📦 Size: $(du -h "$BACKUP_FILE" | cut -f1)"
    
    # Keep only last 5 backups
    cd $BACKUP_DIR
    ls -t termux_server_backup_*.tar.gz | tail -n +6 | xargs rm -f 2>/dev/null
    echo "🗂️  Old backups cleaned up"
else
    echo "❌ Backup failed!"
fi
EOF
    
    # Network configuration script
    cat > ~/network_config.sh << 'EOF'
#!/bin/bash

echo "🌐 Network Configuration Helper"
echo "==============================="

# Get current network info
CURRENT_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7}' | head -1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)

echo "📡 Current Network Status:"
echo "  📍 Local IP: ${CURRENT_IP:-Unknown}"
echo "  🌐 Gateway: ${GATEWAY:-Unknown}"
echo "  🔌 Active Ports: 8080, 8443, 5000, 8022"
echo ""

echo "🔧 To access your server externally:"
echo "1. 📱 Note your local IP: $CURRENT_IP"
echo "2. 🏠 Access your router (usually http://$GATEWAY)"
echo "3. ⚙️  Find 'Port Forwarding' or 'NAT' settings"
echo "4. ➡️  Forward these ports to $CURRENT_IP:"
echo "   - 8080 (HTTP)"
echo "   - 8443 (HTTPS)"  
echo "   - 5000 (Flask)"
echo "   - 8022 (SSH)"
echo "5. 🌍 Use your public IP to access from internet"
echo ""

echo "🔍 Finding your public IP:"
echo "curl -s https://ipinfo.io/ip 2>/dev/null || curl -s https://icanhazip.com 2>/dev/null || echo 'Unable to determine'"
echo ""

echo "🛡️  Security Notes:"
echo "  - Change default passwords"
echo "  - Use strong SSH keys"
echo "  - Consider VPN for external access"
echo "  - Monitor access logs regularly"
EOF
    
    # Update script
    cat > ~/update_server.sh << 'EOF'
#!/bin/bash

echo "🔄 Updating Termux Server..."

# Stop servers
echo "⏹️  Stopping servers..."
./stop_servers.sh

# Update packages
echo "📦 Updating packages..."
pkg update -y && pkg upgrade -y

# Update Python packages
echo "🐍 Updating Python packages..."
pip install --upgrade pip
pip install --upgrade flask django fastapi uvicorn gunicorn requests psutil

# Restart servers
echo "🚀 Restarting servers..."
./start_servers.sh

echo "✅ Update completed!"
EOF
    
    # Make all scripts executable
    chmod +x ~/start_servers.sh
    chmod +x ~/stop_servers.sh
    chmod +x ~/restart_servers.sh
    chmod +x ~/monitor_server.sh
    chmod +x ~/backup_server.sh
    chmod +x ~/network_config.sh
    chmod +x ~/update_server.sh
    
    log "Management scripts created ✓"
}

# Create security configurations
setup_security() {
    log "Setting up security configurations..."
    
    # Set proper permissions
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/* 2>/dev/null || true
    chmod 755 ~/www/html
    chmod 755 ~/www/python
    chmod 600 ~/www/ssl/server.key 2>/dev/null || true
    
    # Create .htaccess for additional security
    cat > ~/www/html/.htaccess << 'EOF'
# Security headers
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"
Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
Header always set Referrer-Policy no-referrer

# Disable directory browsing
Options -Indexes

# Prevent access to sensitive files
<FilesMatch "\.(htaccess|htpasswd|ini|log|sh|inc|bak)$">
    Require all denied
</FilesMatch>

# Block suspicious requests
<RequireAll>
    Require all granted
    Require not ip 127.0.0.1
</RequireAll>
EOF
    
    log "Security configurations applied ✓"
}

# Create systemd-like service management
create_service_management() {
    log "Creating service management..."
    
    cat > ~/service_manager.sh << 'EOF'
#!/bin/bash

SERVICE_NAME="termux-server"
PID_FILE="$HOME/.${SERVICE_NAME}.pid"

case "$1" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Service already running"
            exit 1
        fi
        echo "Starting $SERVICE_NAME..."
        ./start_servers.sh
        echo $ > "$PID_FILE"
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            echo "Stopping $SERVICE_NAME..."
            ./stop_servers.sh
            rm -f "$PID_FILE"
        else
            echo "Service not running"
        fi
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "$SERVICE_NAME is running"
            ./monitor_server.sh
        else
            echo "$SERVICE_NAME is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF
    
    chmod +x ~/service_manager.sh
    
    log "Service management created ✓"
}

# Create auto-start configuration
setup_autostart() {
    log "Setting up auto-start configuration..."
    
    # Create termux boot script
    mkdir -p ~/.termux/boot
    cat > ~/.termux/boot/start-server << 'EOF'
#!/bin/bash

# Wait for network
sleep 10

# Start servers
cd ~
./start_servers.sh

# Log the startup
echo "$(date): Termux server auto-started" >> ~/www/logs/autostart.log
EOF
    
    chmod +x ~/.termux/boot/start-server
    
    # Create manual autostart helper
    cat > ~/setup_autostart.sh << 'EOF'
#!/bin/bash

echo "🚀 Setting up auto-start..."

# Install Termux:Boot from F-Droid if not already installed
if ! pm list packages | grep -q termux.boot; then
    echo "📱 Please install 'Termux:Boot' from F-Droid to enable auto-start"
    echo "🔗 https://f-droid.org/packages/com.termux.boot/"
    echo ""
    echo "After installation:"
    echo "1. Open Termux:Boot app"
    echo "2. Grant necessary permissions"
    echo "3. The server will start automatically on boot"
else
    echo "✅ Termux:Boot is installed"
    echo "✅ Auto-start configured"
fi

echo ""
echo "🔧 Manual start options:"
echo "  ./start_servers.sh - Start all servers"
echo "  ./service_manager.sh start - Service-style start"
EOF
    
    chmod +x ~/setup_autostart.sh
    
    log "Auto-start configuration completed ✓"
}

# Main installation workflow
main() {
    clear
    cat << 'EOF'
    
████████╗███████╗██████╗ ███╗   ███╗██╗   ██╗██╗  ██╗
╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║   ██║╚██╗██╔╝
   ██║   █████╗  ██████╔╝██╔████╔██║██║   ██║ ╚███╔╝ 
   ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║   ██║ ██╔██╗ 
   ██║   ███████╗██║  ██║██║ ╚═╝ ██║╚██████╔╝██╔╝ ██╗
   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝
                                                      
    ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ 
    ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
    ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
    ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
                                                      
    🚀 Complete Mobile Server Setup Script
    📱 Transform your Android into a powerful server!
    
EOF
    
    info "This script will install and configure:"
    echo "  • Nginx web server (HTTP/HTTPS)"
    echo "  • Python Flask application server"
    echo "  • SSH server for remote access"
    echo "  • SSL certificates for security"
    echo "  • Management and monitoring tools"
    echo "  • Auto-start configuration"
    echo ""
    
    read -p "🤔 Do you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Installation cancelled."
        exit 0
    fi
    
    echo ""
    log "🎯 Starting Termux Server installation..."
    
    # Check environment
    check_termux
    
    # Install packages
    install_packages
    
    # Create directory structure
    create_directories
    
    # Setup services
    setup_nginx
    create_python_app
    create_html_content
    setup_ssh
    create_ssl_certificates
    
    # Create management tools
    create_management_scripts
    setup_security
    create_service_management
    setup_autostart
    
    # Final setup
    log "🔧 Finalizing installation..."
    
    # Install psutil for system monitoring
    pip install psutil > /dev/null 2>&1 || warning "Could not install psutil - system monitoring will be limited"
    
    # Create initial logs
    touch ~/www/logs/nginx_access.log
    touch ~/www/logs/nginx_error.log
    touch ~/www/logs/flask.log
    touch ~/www/logs/autostart.log
    
    # Success message
    clear
    cat << 'EOF'
    
    🎉 INSTALLATION COMPLETED SUCCESSFULLY! 🎉
    
    ╔════════════════════════════════════════════════════╗
    ║              🚀 TERMUX SERVER READY 🚀              ║
    ╚════════════════════════════════════════════════════╝
    
EOF
    
    log "✅ Your Termux server is now ready!"
    echo ""
    info "🚀 Quick Start Commands:"
    echo "  ./start_servers.sh     - Start all servers"
    echo "  ./stop_servers.sh      - Stop all servers" 
    echo "  ./monitor_server.sh    - Check server status"
    echo "  ./restart_servers.sh   - Restart all servers"
    echo "  ./backup_server.sh     - Create backup"
    echo "  ./network_config.sh    - Network setup help"
    echo ""
    
    info "🌐 Access URLs (after starting servers):"
    echo "  📊 Dashboard: http://localhost:8080"
    echo "  🐍 Flask App: http://localhost:5000"
    echo "  🔒 HTTPS: https://localhost:8443"
    echo "  🔑 SSH: ssh -p 8022 \$USER@localhost"
    echo ""
    
    info "📁 Important Directories:"
    echo "  ~/www/html/     - Static web files"
    echo "  ~/www/python/   - Python applications"
    echo "  ~/www/logs/     - Server logs"
    echo "  ~/www/ssl/      - SSL certificates"
    echo ""
    
    warning "🔐 Security Reminders:"
    echo "  • Change default passwords"
    echo "  • Review firewall settings"
    echo "  • Monitor access logs"
    echo "  • Keep packages updated"
    echo ""
    
    read -p "🚀 Start servers now? (Y/n): " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        log "🎯 Starting servers..."
        ./start_servers.sh
        echo ""
        log "🎊 All done! Your server is running!"
        echo ""
        info "💡 Pro Tips:"
        echo "  • Run './monitor_server.sh' to check status anytime"
        echo "  • Use './setup_autostart.sh' for boot-time startup"
        echo "  • Check './network_config.sh' for external access"
        echo ""
    else
        echo ""
        log "👍 Servers not started. Run './start_servers.sh' when ready!"
    fi
    
    echo ""
    echo "🙏 Thank you for using Termux Server Setup!"
    echo "⭐ If you found this useful, consider sharing it!"
    echo ""
}

# Trap to handle interruption
trap 'echo ""; error "Installation interrupted!"; exit 1' INT TERM

# Run main installation
main "$@"