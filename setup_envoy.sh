#!/usr/bin/env bash

# Download Envoy Proxy
curl -L https://github.com/envoyproxy/envoy/releases/download/v1.24.1/envoy-contrib-1.24.1-linux-x86_64 -O /usr/local/bin/envoy
chmod +x /usr/local/bin/envoy-contrib-1.24.1-linux-x86_64

# Request user input for the address (Ask for user to enter the IP address / FQDN of the desired datasource to proxy) 
read -p "Enter the address (e.g., clusterabc.us-west-2.rds.amazonaws.com): " address

# Create envoy-postgres.yaml
cat << EOF > /usr/local/bin/envoy-postgres.yaml
static_resources:
  listeners:
  - name: postgres_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 5433
    filter_chains:
    - filters:
      - name: envoy.filters.network.tcp_proxy
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy
          stat_prefix: postgres_tcp
          cluster: postgres_cluster

  clusters:
  - name: postgres_cluster
    connect_timeout: 1s
    type: strict_dns
    load_assignment:
      cluster_name: postgres_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: $address
                port_value: 5432 #Update to desired target port as per the datasource, example RDS default connects on 5432
EOF

# Configure systemd service
cat << EOF > /etc/systemd/system/envoy-proxy.service
[Unit]
Description=Envoy Proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/envoy-contrib-1.24.1-linux-x86_64 --config-path /usr/local/bin/envoy-postgres.yaml
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon
sudo systemctl daemon-reload

# Enable automatic start on boot
#sudo systemctl enable envoy-proxy

# Start the Envoy Proxy service
#sudo systemctl start envoy-proxy

# Stop the Envoy Proxy service
# systemctl stop envoy-proxy
# Command to stop the envoy proxy service.
echo "To stop the Envoy Proxy service, run: sudo systemctl stop envoy-proxy"
