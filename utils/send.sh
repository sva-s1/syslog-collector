#!/bin/bash

# Syslog Collector Test Script
# Sends sample messages to test firewall, router, and Palo Alto pattern matching

echo "🧪 Testing Syslog Collector with sample messages..."
echo "📡 Target: UDP port 514 on localhost"
echo ""

# Directory containing sample log files
SAMPLES_DIR="$(dirname "$0")/../samples"

# Function to send a log message
send_log() {
    local log_file="$1"
    local description="$2"
    local pattern="$3"
    
    if [ ! -f "$SAMPLES_DIR/$log_file" ]; then
        echo "❌ Sample file $log_file not found in $SAMPLES_DIR"
        return 1
    fi
    
    echo "📤 Sending $description (should match $pattern pattern)..."
    
    # Read the log content and send it
    LOG_CONTENT=$(cat "$SAMPLES_DIR/$log_file")
    
    echo "$LOG_CONTENT" | \
        docker run -i --rm --network host ghcr.io/sva-s1/alpine-nc:latest /bin/ash -c "nc -u -w 1 127.0.0.1 514 && echo '$description sent successfully'" || \
        echo "❌ Failed to send $description"
    
    echo ""
}

# Test Message 1: Cisco Firewall (matches SOURCE2_MATCHER=firewall*)
send_log "cisco-firewall.log" "🔥 CISCO FIREWALL message" "firewall*"

# Test Message 2: Cisco Router (matches SOURCE1_MATCHER=router*)
send_log "cisco-router.log" "🌐 CISCO ROUTER message" "router*"

# Test Message 3: Palo Alto Firewall (matches SOURCE3_MATCHER=PA-*)
send_log "palo-alto.log" "🛡️ PALO ALTO FIREWALL message" "PA-*"

echo "✅ Test complete! All messages sent"
echo ""
echo "📋 Messages sent:"
echo "   1. Cisco Firewall (hostname: firewall4) → ciscoFirewall1 parser"
echo "   2. Cisco Router (hostname: router01) → ciscoRouter1 parser"
echo "   3. Palo Alto Firewall (appname: PA-220) → paloAltoFirewall parser"
echo ""
echo "🔍 Check your SentinelOne SIEM or container logs to verify message processing:"
echo "   docker compose logs scalyr-agent"
echo "   docker compose logs syslog-ng"
echo "   docker compose logs config-generator"
echo ""
echo "🎯 Expected DataSource attributes in SDL:"
echo "   • Cisco Firewall: Category=security, Name='Cisco Firepower Threat Defense', Vendor='Cisco'"
echo "   • Cisco Router: Category=security, Name='Cisco Router', Vendor='Cisco'"
echo "   • Palo Alto: Category=security, Name='Palo Alto Firewall', Vendor='Palo Alto Networks'"
