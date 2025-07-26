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
# This replaces ALL variables in the template, not just API_TOKEN
sed -e "s/\${AISIEM_LOGACCESS_WRITE_TOKEN}/$(printenv AISIEM_LOGACCESS_WRITE_TOKEN)/g" \
    -e "s/\${AISIEM_SERVER}/$(printenv AISIEM_SERVER)/g" \
    -e "s/\${SYSLOG_HOST}/$(printenv SYSLOG_HOST)/g" \
    -e "s/\${PORT1_PROTOCOL}/$(printenv PORT1_PROTOCOL)/g" \
    -e "s/\${PORT1_NUMBER}/$(printenv PORT1_NUMBER)/g" \
    -e "s/\${PORT1_TYPE}/$(printenv PORT1_TYPE)/g" \
    -e "s/\${PORT2_PROTOCOL}/$(printenv PORT2_PROTOCOL)/g" \
    -e "s/\${PORT2_NUMBER}/$(printenv PORT2_NUMBER)/g" \
    -e "s/\${PORT2_TYPE}/$(printenv PORT2_TYPE)/g" \
    -e "s/\${SOURCE1_NAME}/$(printenv SOURCE1_NAME)/g" \
    -e "s/\${SOURCE1_PARSER}/$(printenv SOURCE1_PARSER)/g" \
    -e "s/\${SOURCE1_ATTRIBUTE}/$(printenv SOURCE1_ATTRIBUTE)/g" \
    -e "s/\${SOURCE1_MATCHER}/$(printenv SOURCE1_MATCHER)/g" \
    -e "s/\${SOURCE2_NAME}/$(printenv SOURCE2_NAME)/g" \
    -e "s/\${SOURCE2_PARSER}/$(printenv SOURCE2_PARSER)/g" \
    -e "s/\${SOURCE2_ATTRIBUTE}/$(printenv SOURCE2_ATTRIBUTE)/g" \
    -e "s/\${SOURCE2_MATCHER}/$(printenv SOURCE2_MATCHER)/g" \
    /etc/syslog-collector/syslog.yaml > "$SECURE_INPUT"

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

# Run the config-generator with all required parameters
# Note: cleanup will be called automatically via trap when config-generator exits
exec config-generator \
  -i "$INPUT" \
  -o "$AGENT_OUTPUT" \
  -s "$SYSLOG_OUTPUT" \
  -lc "$LOGROTATE_CONFIG_OUTPUT" \
  -ls "$LOGROTATE_SCRIPT_OUTPUT" \
  -l "$LOGPATH" \
  -d "$SYSLOG_IMAGE" \
  -e "$VERSION"
