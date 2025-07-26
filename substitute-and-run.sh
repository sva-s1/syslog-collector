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

# Substitute environment variables in syslog.yaml
# Use printenv to get clean API token value and sed with proper escaping
TOKEN=$(printenv API_TOKEN)
sed "s/\${API_TOKEN}/$TOKEN/g" /etc/syslog-collector/syslog.yaml > "$SECURE_INPUT"

# Set INPUT to point to the secure substituted file
export INPUT="$SECURE_INPUT"

# Check for required files
abort=0
for f in "$INPUT" /etc/syslog-collector/syslog.crt /etc/syslog-collector/syslog.key; do
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
