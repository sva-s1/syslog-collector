#!/bin/sh

# Post-processing script to add dataSource attributes to agent.json
# This script is called after the config-generator creates the initial agent.json

AGENT_JSON="$1"

if [ -z "$AGENT_JSON" ] || [ ! -f "$AGENT_JSON" ]; then
    echo "Usage: $0 <path-to-agent.json>"
    exit 1
fi

echo "Post-processing $AGENT_JSON to add dataSource attributes..."

# Create a temporary file for the updated agent.json
TEMP_AGENT_JSON=$(mktemp)
trap "rm -f $TEMP_AGENT_JSON" EXIT

# Get dataSource values from environment
SOURCE1_NAME="${SOURCE1_DATASOURCE_NAME:-}"
SOURCE1_VENDOR="${SOURCE1_DATASOURCE_VENDOR:-}"
SOURCE1_CATEGORY="${SOURCE1_DATASOURCE_CATEGORY:-}"
SOURCE2_NAME="${SOURCE2_DATASOURCE_NAME:-}"
SOURCE2_VENDOR="${SOURCE2_DATASOURCE_VENDOR:-}"
SOURCE2_CATEGORY="${SOURCE2_DATASOURCE_CATEGORY:-}"

# Use Python to process the JSON (more reliable than jq in containers)
python3 << EOF
import json
import sys
import os

# Read the original agent.json
try:
    with open('$AGENT_JSON', 'r') as f:
        agent_config = json.load(f)
except Exception as e:
    print(f"Error reading agent.json: {e}")
    sys.exit(1)

# Get environment variables
source1_name = os.environ.get('SOURCE1_DATASOURCE_NAME', '').strip()
source1_vendor = os.environ.get('SOURCE1_DATASOURCE_VENDOR', '').strip()
source1_category = os.environ.get('SOURCE1_DATASOURCE_CATEGORY', '').strip()
source2_name = os.environ.get('SOURCE2_DATASOURCE_NAME', '').strip()
source2_vendor = os.environ.get('SOURCE2_DATASOURCE_VENDOR', '').strip()
source2_category = os.environ.get('SOURCE2_DATASOURCE_CATEGORY', '').strip()

# Process each log entry
if 'logs' in agent_config:
    for log_entry in agent_config['logs']:
        if 'attributes' in log_entry:
            source_type = log_entry['attributes'].get('source_type', '')
            
            # Add dataSource attributes based on source type
            if source_type == 'cisco-router' and (source1_name or source1_vendor or source1_category):
                if source1_category:
                    log_entry['attributes']['dataSource.category'] = source1_category
                if source1_name:
                    log_entry['attributes']['dataSource.name'] = source1_name
                if source1_vendor:
                    log_entry['attributes']['dataSource.vendor'] = source1_vendor
                    
            elif source_type == 'cisco-firewall' and (source2_name or source2_vendor or source2_category):
                if source2_category:
                    log_entry['attributes']['dataSource.category'] = source2_category
                if source2_name:
                    log_entry['attributes']['dataSource.name'] = source2_name
                if source2_vendor:
                    log_entry['attributes']['dataSource.vendor'] = source2_vendor

# Write the updated configuration
try:
    with open('$TEMP_AGENT_JSON', 'w') as f:
        json.dump(agent_config, f, indent=2)
    print("Successfully processed agent.json")
except Exception as e:
    print(f"Error writing updated agent.json: {e}")
    sys.exit(1)
EOF

# Check if the Python script succeeded
if [ $? -eq 0 ] && [ -s "$TEMP_AGENT_JSON" ]; then
    mv "$TEMP_AGENT_JSON" "$AGENT_JSON"
    echo "Successfully added dataSource attributes to agent.json"
else
    echo "Warning: Failed to process agent.json, keeping original"
    exit 1
fi
