#!/bin/bash

# Variables setup
VM1LAN=eth0
VM2LAN=eth0
VM2WAN=enp0s3

VM1ADDR=10.1.2.101
VM2ADDR=10.1.2.102

DNSZONE=wit2025.pl

DHCPSUBNET=10.110.0.0
DHCPBEGIN=10.110.0.2
DHCPEND=10.110.0.100
DHCPMASK=255.255.255.0

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
sudo apt-get install -y bind9 bind9utils bind9-doc dnsutils

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

# --- DHCP setup ---
# Install DHCP utils
sudo apt-get install -y isc-dhcp-server

# Override default isc-dhcp-server config
sudo tee /etc/default/isc-dhcp-server > dev/null <<EOF
# Defaults for isc-dhcp-server (sourced by /etc/init.d/isc-dhcp-server)

# Path to dhcpd's config file (default: /etc/dhcp/dhcpd.conf).
#DHCPDv4_CONF=/etc/dhcp/dhcpd.conf
#DHCPDv6_CONF=/etc/dhcp/dhcpd6.conf

# Path to dhcpd's PID file (default: /var/run/dhcpd.pid).
#DHCPDv4_PID=/var/run/dhcpd.pid
#DHCPDv6_PID=/var/run/dhcpd6.pid

# Additional options to start dhcpd with.
#       Don't use options -cf or -pf here; use DHCPD_CONF/ DHCPD_PID instead
#OPTIONS=""

# On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
#       Separate multiple interfaces with spaces, e.g. "eth0 eth1".
INTERFACESv4="$VM2LAN"
INTERFACESv6=""
EOF

# Override dhcp.conf
sudo tee /etc/dhcp/dhcpd.conf > dev/null <<EOF
# dhcpd.conf
#
# Sample configuration file for ISC dhcpd
#

# option definitions common to all supported networks...
option domain-name "$DNSZONE";
option domain-name-servers $VM2ADDR;

default-lease-time 600;
max-lease-time 7200;

# The ddns-updates-style parameter controls whether or not the server will
# attempt to do a DNS update when a lease is confirmed. We default to the
# behavior of the version 2 packages ('none', since DHCP v2 didn't
# have support for DDNS.)
ddns-update-style none;

# If this DHCP server is the official DHCP server for the local
# network, the authoritative directive should be uncommented.
#authoritative;

# Use this to send dhcp log messages to a different log file (you also
# have to hack syslog.conf to complete the redirection).
#log-facility local7;

# No service will be given on this subnet, but declaring it helps the
# DHCP server to understand the network topology.

#subnet 10.152.187.0 netmask 255.255.255.0 {
#}

# This is a very basic subnet declaration.

subnet $DHCPSUBNET netmask $DHCPMASK {
  range $DHCPBEGIN $DHCPEND;
  option routers $VM2ADDR;
}

# This declaration allows BOOTP clients to get dynamic addresses,
# which we don't really recommend.

#subnet 10.254.239.32 netmask 255.255.255.224 {
#  range dynamic-bootp 10.254.239.40 10.254.239.60;
#  option broadcast-address 10.254.239.31;
#  option routers rtr-239-32-1.example.org;
#}

# A slightly different configuration for an internal subnet.
#subnet 10.5.5.0 netmask 255.255.255.224 {
#  range 10.5.5.26 10.5.5.30;
#  option domain-name-servers ns1.internal.example.org;
#  option domain-name "internal.example.org";
#  option routers 10.5.5.1;
#  option broadcast-address 10.5.5.31;
#  default-lease-time 600;
#  max-lease-time 7200;
#}

# Hosts which require special configuration options can be listed in
# host statements.   If no address is specified, the address will be
# allocated dynamically (if possible), but the host-specific information
# will still come from the host declaration.

#host passacaglia {
#  hardware ethernet 0:0:c0:5d:bd:95;
#  filename "vmunix.passacaglia";
#  server-name "toccata.example.com";
#}

# Fixed IP addresses can also be specified for hosts.   These addresses
# should not also be listed as being available for dynamic assignment.
# Hosts for which fixed IP addresses have been specified can boot using
# BOOTP or DHCP.   Hosts for which no fixed address is specified can only
# be booted with DHCP, unless there is an address range on the subnet
# to which a BOOTP client is connected which has the dynamic-bootp flag
# set.
#host fantasia {
#  hardware ethernet 08:00:07:26:c0:a5;
#  fixed-address fantasia.example.com;
#}

# You can declare a class of clients and then do address allocation
# based on that.   The example below shows a case where all clients
# in a certain class get addresses on the 10.17.224/24 subnet, and all
# other clients get addresses on the 10.0.29/24 subnet.

#class "foo" {
#  match if substring (option vendor-class-identifier, 0, 4) = "SUNW";
#}

#shared-network 224-29 {
#  subnet 10.17.224.0 netmask 255.255.255.0 {
#    option routers rtr-224.example.org;
#  }
#  subnet 10.0.29.0 netmask 255.255.255.0 {
#    option routers rtr-29.example.org;
#  }
#  pool {
#    allow members of "foo";
#    range 10.17.224.10 10.17.224.250;
#  }
#  pool {
#    deny members of "foo";
#    range 10.0.29.10 10.0.29.230;
#  }
#}
EOF

# Restart the dhcp server
sudo systemctl restart isc-dhcp-server
