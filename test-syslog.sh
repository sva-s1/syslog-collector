#!/bin/bash

# Syslog Collector Test Script
# Sends sample messages to test firewall and router pattern matching

echo "🧪 Testing Syslog Collector with sample messages..."
echo "📡 Target: UDP port 514 on localhost"
echo ""

# Generate current timestamp in RFC3339 format
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Test Message 1: Firewall pattern (matches SOURCE2_MATCHER=firewall*)
echo "🔥 Sending FIREWALL message (should match firewall* pattern)..."
FIREWALL_MSG="<134>1 $TIMESTAMP docker-desktop firewall4 12345 INTF-ALERT [exampleSDID@32473 iut=\"3\" eventSource=\"cisco\"] %ASA-4-313001: Built inbound TCP connection for faddr 10.20.30.40/12345 gaddr 192.168.1.1/80 laddr 172.16.0.2/443"

echo "$FIREWALL_MSG" | \
  docker run -i --rm --network host ghcr.io/sva-s1/alpine-nc:latest /bin/ash -c "nc -u -w 1 127.0.0.1 514 && echo 'Firewall log sent successfully'"

echo ""

# Test Message 2: Router pattern (matches SOURCE1_MATCHER=router*)
echo "🌐 Sending ROUTER message (should match router* pattern)..."
ROUTER_MSG="<134>1 $TIMESTAMP router01 ospf 23456 LINK-STATE [exampleSDID@32473 iut=\"2\" eventSource=\"cisco\"] %OSPF-5-ADJCHG: Process 1, Nbr 192.168.1.100 on GigabitEthernet0/1 from LOADING to FULL, Loading Done"

echo "$ROUTER_MSG" | \
  docker run -i --rm --network host ghcr.io/sva-s1/alpine-nc:latest /bin/ash -c "nc -u -w 1 127.0.0.1 514 && echo 'Router log sent successfully'"

echo ""
echo "✅ Test complete! Both messages sent with timestamp: $TIMESTAMP"
echo "📋 Messages sent:"
echo "   1. Firewall message (hostname: firewall4) → should match ciscoFirewall parser"
echo "   2. Router message (hostname: router01) → should match ciscoRouter parser"
echo ""
echo "🔍 Check your SentinelOne SIEM or container logs to verify message processing:"
echo "   docker-compose logs scalyr-agent"
echo "   docker-compose logs syslog-ng"
