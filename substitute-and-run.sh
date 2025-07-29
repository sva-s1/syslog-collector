#!/bin/sh

# Cleanup function to remove sensitive files
cleanup() {
    if [ -f "$SECURE_INPUT" ]; then
        rm -f "$SECURE_INPUT"
    fi
    if [ -p "$FIFO_PATH" ]; then
        rm -f "$FIFO_PATH"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Create a secure temporary file with restricted permissions
SECURE_INPUT=$(mktemp -t syslog-config.XXXXXX)
chmod 600 "$SECURE_INPUT"

# Generate syslog.yaml from template using environment variables
# Use a safer approach that handles special characters properly
cp /etc/syslog-collector/syslog.yaml "$SECURE_INPUT"

# Function to safely replace variables using printf for proper escaping
safe_replace() {
    local var_name="$1"
    local var_value="$2"
    local temp_file="$SECURE_INPUT.tmp"
    
    # Use a different delimiter that's unlikely to appear in values
    sed "s|\${${var_name}}|${var_value}|g" "$SECURE_INPUT" > "$temp_file"
    mv "$temp_file" "$SECURE_INPUT"
}

# Replace all variables safely
safe_replace "AISIEM_LOGACCESS_WRITE_TOKEN" "$(printenv AISIEM_LOGACCESS_WRITE_TOKEN)"
safe_replace "AISIEM_SERVER" "$(printenv AISIEM_SERVER)"
safe_replace "SYSLOG_HOST" "$(printenv SYSLOG_HOST)"
safe_replace "PORT1_PROTOCOL" "$(printenv PORT1_PROTOCOL)"
safe_replace "PORT1_NUMBER" "$(printenv PORT1_NUMBER)"
safe_replace "PORT1_TYPE" "$(printenv PORT1_TYPE)"
safe_replace "PORT2_PROTOCOL" "$(printenv PORT2_PROTOCOL)"
safe_replace "PORT2_NUMBER" "$(printenv PORT2_NUMBER)"
safe_replace "PORT2_TYPE" "$(printenv PORT2_TYPE)"
safe_replace "SOURCE1_NAME" "$(printenv SOURCE1_NAME)"
safe_replace "SOURCE1_PARSER" "$(printenv SOURCE1_PARSER)"
safe_replace "SOURCE1_ATTRIBUTE" "$(printenv SOURCE1_ATTRIBUTE)"
safe_replace "SOURCE1_MATCHER" "$(printenv SOURCE1_MATCHER)"
safe_replace "SOURCE2_NAME" "$(printenv SOURCE2_NAME)"
safe_replace "SOURCE2_PARSER" "$(printenv SOURCE2_PARSER)"
safe_replace "SOURCE2_ATTRIBUTE" "$(printenv SOURCE2_ATTRIBUTE)"
safe_replace "SOURCE2_MATCHER" "$(printenv SOURCE2_MATCHER)"
safe_replace "SOURCE1_DATASOURCE_NAME" "$(printenv SOURCE1_DATASOURCE_NAME)"
safe_replace "SOURCE1_DATASOURCE_VENDOR" "$(printenv SOURCE1_DATASOURCE_VENDOR)"
safe_replace "SOURCE1_DATASOURCE_CATEGORY" "$(printenv SOURCE1_DATASOURCE_CATEGORY)"
safe_replace "SOURCE2_DATASOURCE_NAME" "$(printenv SOURCE2_DATASOURCE_NAME)"
safe_replace "SOURCE2_DATASOURCE_VENDOR" "$(printenv SOURCE2_DATASOURCE_VENDOR)"
safe_replace "SOURCE2_DATASOURCE_CATEGORY" "$(printenv SOURCE2_DATASOURCE_CATEGORY)"

# Debug: Check what dataSource environment variables contain
echo "DEBUG: SOURCE1_DATASOURCE_NAME='$(printenv SOURCE1_DATASOURCE_NAME)'"
echo "DEBUG: SOURCE1_DATASOURCE_VENDOR='$(printenv SOURCE1_DATASOURCE_VENDOR)'"
echo "DEBUG: SOURCE1_DATASOURCE_CATEGORY='$(printenv SOURCE1_DATASOURCE_CATEGORY)'"
echo "DEBUG: SOURCE2_DATASOURCE_NAME='$(printenv SOURCE2_DATASOURCE_NAME)'"
echo "DEBUG: SOURCE2_DATASOURCE_VENDOR='$(printenv SOURCE2_DATASOURCE_VENDOR)'"
echo "DEBUG: SOURCE2_DATASOURCE_CATEGORY='$(printenv SOURCE2_DATASOURCE_CATEGORY)'"

# Handle conditional dataSource attributes
# TEMPORARILY DISABLED: Remove empty dataSource lines first (only lines with no value after colon)
# sed '/dataSource\.name:[[:space:]]*$/d' "$SECURE_INPUT" > "$SECURE_INPUT.tmp1" && mv "$SECURE_INPUT.tmp1" "$SECURE_INPUT"
# sed '/dataSource\.vendor:[[:space:]]*$/d' "$SECURE_INPUT" > "$SECURE_INPUT.tmp2" && mv "$SECURE_INPUT.tmp2" "$SECURE_INPUT"
# sed '/dataSource\.category:[[:space:]]*$/d' "$SECURE_INPUT" > "$SECURE_INPUT.tmp3" && mv "$SECURE_INPUT.tmp3" "$SECURE_INPUT"

# Now check if we need to remove entire attributes sections
for source_num in 1 2; do
    name_var="SOURCE${source_num}_DATASOURCE_NAME"
    vendor_var="SOURCE${source_num}_DATASOURCE_VENDOR"
    category_var="SOURCE${source_num}_DATASOURCE_CATEGORY"
    name_val=$(printenv "$name_var")
    vendor_val=$(printenv "$vendor_var")
    category_val=$(printenv "$category_var")
    
    # If all dataSource attributes are empty, remove the entire attributes section for this source
    if [ -z "$name_val" ] && [ -z "$vendor_val" ] && [ -z "$category_val" ]; then
        # Use a simpler approach: create a temp file without the attributes section
        awk -v source="SOURCE${source_num}_NAME" '
        BEGIN { in_source = 0; in_attributes = 0; skip_until_matchers = 0 }
        /^[[:space:]]*-[[:space:]]*\$\{/ {
            if ($0 ~ "\\$\\{" source "\\}:") {
                in_source = 1
                print $0
                next
            } else {
                in_source = 0
            }
        }
        in_source && /^[[:space:]]*attributes:[[:space:]]*$/ {
            in_attributes = 1
            skip_until_matchers = 1
            next
        }
        in_source && skip_until_matchers && /^[[:space:]]*matchers:[[:space:]]*$/ {
            skip_until_matchers = 0
            in_attributes = 0
            print $0
            next
        }
        skip_until_matchers { next }
        { print $0 }
        ' "$SECURE_INPUT" > "$SECURE_INPUT.tmp" && mv "$SECURE_INPUT.tmp" "$SECURE_INPUT"
    fi
done

# Set INPUT to point to the secure substituted file
export INPUT="$SECURE_INPUT"

# Check for required files
abort=0
for f in /etc/syslog-collector/syslog.yaml /etc/syslog-collector/syslog.crt /etc/syslog-collector/syslog.key; do
  test -e "$f" || { echo "$(basename "$f") not found"; abort=1; }
done
if [ $abort -eq 1 ]; then
    cleanup
    exit 1
fi

# Create cert directory and copy certificates
mkdir -p /out/etc/syslog-ng/cert.d
(cd /etc/syslog-collector && cp -f syslog.crt syslog.key /out/etc/syslog-ng/cert.d)

# Run the config-generator with all required parameters in background
config-generator \
  -i "$INPUT" \
  -o "$AGENT_OUTPUT" \
  -s "$SYSLOG_OUTPUT" \
  -lc "$LOGROTATE_CONFIG_OUTPUT" \
  -ls "$LOGROTATE_SCRIPT_OUTPUT" \
  -l "$LOGPATH" \
  -d "$SYSLOG_IMAGE" \
  -e "$VERSION" &

CONFIG_GENERATOR_PID=$!
echo "DEBUG: Config-generator started with PID $CONFIG_GENERATOR_PID"

# Wait for the initial config files to be created
echo "DEBUG: Waiting for agent.json to be created..."
for i in $(seq 1 30); do
    if [ -f "$AGENT_OUTPUT" ]; then
        echo "DEBUG: agent.json found after ${i} seconds"
        break
    fi
    sleep 1
done

# Set up continuous post-processing monitoring
if [ -f "/etc/syslog-collector/post-process-agent.sh" ]; then
    echo "DEBUG: Setting up continuous post-processing monitoring..."
    cp "/etc/syslog-collector/post-process-agent.sh" "/tmp/post-process-agent.sh"
    chmod +x "/tmp/post-process-agent.sh"
    
    # Start monitoring loop in background
    (
        LAST_MODIFIED=""
        while true; do
            if [ -f "$AGENT_OUTPUT" ]; then
                CURRENT_MODIFIED=$(stat -c %Y "$AGENT_OUTPUT" 2>/dev/null || stat -f %m "$AGENT_OUTPUT" 2>/dev/null)
                if [ "$CURRENT_MODIFIED" != "$LAST_MODIFIED" ]; then
                    echo "DEBUG: agent.json modified, re-applying dataSource attributes..."
                    /tmp/post-process-agent.sh "$AGENT_OUTPUT"
                    LAST_MODIFIED="$CURRENT_MODIFIED"
                fi
            fi
            sleep 5
        done
    ) &
    MONITOR_PID=$!
    echo "DEBUG: Post-processing monitor started with PID $MONITOR_PID"
else
    echo "WARNING: post-process-agent.sh not found, dataSource attributes will be missing"
fi

# Wait for the config-generator to continue running
echo "DEBUG: Waiting for config-generator to continue..."
wait $CONFIG_GENERATOR_PID
CONFIG_EXIT_CODE=$?

# Clean up monitoring process
if [ ! -z "$MONITOR_PID" ]; then
    echo "DEBUG: Stopping post-processing monitor..."
    kill $MONITOR_PID 2>/dev/null
fi

# Call cleanup and exit with the same code as the config generator
cleanup
exit $CONFIG_EXIT_CODE
