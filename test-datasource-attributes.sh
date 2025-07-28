#!/bin/bash

# Test script to verify dataSource attributes functionality
# This simulates what happens inside the config-generator container

set -e

# Load test environment
set -a  # automatically export all variables
source .env.test
set +a  # turn off automatic export

# Create a temporary file for testing
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

echo "Testing dataSource attributes functionality..."
echo "============================================="

# Perform the same substitution as the container script
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
    -e "s/\${SOURCE1_DATASOURCE_NAME}/$(printenv SOURCE1_DATASOURCE_NAME)/g" \
    -e "s/\${SOURCE1_DATASOURCE_VENDOR}/$(printenv SOURCE1_DATASOURCE_VENDOR)/g" \
    -e "s/\${SOURCE2_DATASOURCE_NAME}/$(printenv SOURCE2_DATASOURCE_NAME)/g" \
    -e "s/\${SOURCE2_DATASOURCE_VENDOR}/$(printenv SOURCE2_DATASOURCE_VENDOR)/g" \
    syslog.yaml > "$TEMP_FILE"

echo "After initial substitution:"
echo "=========================="
cat "$TEMP_FILE"
echo ""

# Handle conditional dataSource attributes
# Remove empty dataSource lines first
echo "Removing empty dataSource lines..."
sed '/dataSource\.name:[[:space:]]*$/d' "$TEMP_FILE" > "$TEMP_FILE.tmp1" && mv "$TEMP_FILE.tmp1" "$TEMP_FILE"
sed '/dataSource\.vendor:[[:space:]]*$/d' "$TEMP_FILE" > "$TEMP_FILE.tmp2" && mv "$TEMP_FILE.tmp2" "$TEMP_FILE"

echo "After removing empty lines:"
echo "========================"
cat "$TEMP_FILE"
echo ""

# Now check if we need to remove entire attributes sections
for source_num in 1 2; do
    name_var="SOURCE${source_num}_DATASOURCE_NAME"
    vendor_var="SOURCE${source_num}_DATASOURCE_VENDOR"
    name_val=$(printenv "$name_var")
    vendor_val=$(printenv "$vendor_var")
    
    echo "Source $source_num: name='$name_val', vendor='$vendor_val'"
    
    # If both name and vendor are empty, remove the entire attributes section for this source
    if [[ -z "$name_val" && -z "$vendor_val" ]]; then
        echo "  -> Removing entire attributes section for source $source_num"
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
        ' "$TEMP_FILE" > "$TEMP_FILE.tmp" && mv "$TEMP_FILE.tmp" "$TEMP_FILE"
    else
        echo "  -> Keeping attributes section (has non-empty values)"
    fi
done

echo ""
echo "Final result after conditional processing:"
echo "========================================="
cat "$TEMP_FILE"
