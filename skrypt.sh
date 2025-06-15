#!/bin/bash

# Variables setup
VM1LAN=eth0
VM2LAN=eth0
VM2WAN=enp0s3

VM1ADDR=10.1.2.101
VM2ADDR=10.1.2.102

DNSZONE=wit2025.pl

# Setup dns resolution
sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF

# apt update
sudo apt-get update

# Enable routing
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Install iptables
sudo apt-get install -y iptables

# Setup masquerade
sudo iptables -t nat -A POSTROUTING -o $VM2WAN -j MASQUERADE

# --- DNS SETUP ---
# Install dns utils
apt-get install -y bind9 bind9utils bind9-doc dnsutils

# Create new dns zone
echo "zone \"$DNSZONE\" {type master; file \"/etc/bind/db.$DNSZONE\";};" | sudo tee -a /etc/bind/named.local.conf

# Create dns zone config
sudo tee /etc/bind/db.$DNSZONE > dev/null <<EOF
;
; BIND data file for local loopback interface
;
$TTL    604800
@       IN      SOA     $DNSZONE. root.$DNSZONE. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1
ns1     IN      A       $VM2ADDR
vm2     IN      A       $VM2ADDR
vm1     IN      A       $VM1ADDR
EOF

# Override server config
sudo tee /etc/bind/named.conf.options > dev/null <<EOF
options {
        directory "/var/cache/bind";

        directory "/var/cache/bind";

        // If there is a firewall between you and nameservers you want
        // to talk to, you may need to fix the firewall to allow multiple
        // ports to talk.  See http://www.kb.cert.org/vuls/id/800113

        // If your ISP provided one or more IP addresses for stable
        // nameservers, you probably want to use them as forwarders.
        // Uncomment the following block, and insert the addresses replacing
        // the all-0's placeholder.

        forwarders {
              8.8.8.8;
              9.9.9.9;
        };

        //========================================================================
        // If BIND logs error messages about the root key being expired,
        // you will need to update your keys.  See https://www.isc.org/bind-keys
        //========================================================================

        dnssec-validation auto;

        recursion yes;
        allow-recursion { any; };
        listen-on {$VM2ADDR};
        listen-on-v6 { any; };
        allow-transfer { none; };
};
EOF
