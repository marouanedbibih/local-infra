#!/bin/bash

# Current date
echo "Setting up SonarQube domain access on $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "User: $USER"

# Create directories for Nginx configuration
mkdir -p nginx/conf.d nginx/certs

# Create a self-signed SSL certificate
echo "Creating SSL certificate for sonarqube.local..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/certs/sonarqube.key \
  -out nginx/certs/sonarqube.crt \
  -subj "/CN=sonarqube.local/O=DevOps/C=US" \
  -addext "subjectAltName = DNS:sonarqube.local,DNS:localhost,IP:127.0.0.1"

# Create Nginx configuration for SonarQube
echo "Creating Nginx configuration for sonarqube.local..."
cat > nginx/conf.d/sonarqube.conf << 'EOF'
# HTTP redirect to HTTPS
server {
    listen 80;
    server_name sonarqube.local;
    
    # Redirect all HTTP requests to HTTPS
    return 301 https://$host$request_uri;
}

# HTTPS server for SonarQube
server {
    listen 443 ssl;
    server_name sonarqube.local;
    
    ssl_certificate /etc/nginx/certs/sonarqube.crt;
    ssl_certificate_key /etc/nginx/certs/sonarqube.key;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Proxy to SonarQube
    location / {
        proxy_pass http://sonarqube:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 30s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF

# Add entry to /etc/hosts
echo "Adding sonarqube.local to /etc/hosts..."
if ! grep -q "sonarqube.local" /etc/hosts; then
    echo "127.0.0.1 sonarqube.local" | sudo tee -a /etc/hosts
    echo "Added sonarqube.local to /etc/hosts"
else
    echo "sonarqube.local already in /etc/hosts"
fi

# Set up sysctl requirements for SonarQube
echo "Setting up system requirements for SonarQube..."
cat > sysctl-sonarqube.conf << EOF
vm.max_map_count=262144
fs.file-max=65536
EOF

echo "Adding system requirements to sysctl..."
sudo cp sysctl-sonarqube.conf /etc/sysctl.d/99-sonarqube.conf
sudo sysctl --system

echo "Updating security limits for SonarQube..."
if ! grep -q "sonarqube - nofile" /etc/security/limits.conf; then
    echo "sonarqube - nofile 65536" | sudo tee -a /etc/security/limits.conf
    echo "sonarqube - nproc 4096" | sudo tee -a /etc/security/limits.conf
fi

echo "Setup complete! Start the containers with 'docker-compose up -d'"
echo "You should be able to access SonarQube at https://sonarqube.local"