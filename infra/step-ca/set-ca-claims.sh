#!/bin/sh

set -eu

CONFIGPATH="${CONFIGPATH:-/home/step/config/ca.json}"
PWDPATH="${PWDPATH:-/home/step/secrets/password}"
MIN_TLS_DURATION="${STEP_CA_MIN_TLS_CERT_DURATION:-1h}"
MAX_TLS_DURATION="${STEP_CA_MAX_TLS_CERT_DURATION:-2160h}"
DEFAULT_TLS_DURATION="${STEP_CA_DEFAULT_TLS_CERT_DURATION:-2160h}"

if [ ! -f "$CONFIGPATH" ]; then
  echo "Step CA config not found at $CONFIGPATH" >&2
  exit 1
fi

TMP_CONFIG="$(mktemp)"

jq \
  --arg min "$MIN_TLS_DURATION" \
  --arg max "$MAX_TLS_DURATION" \
  --arg def "$DEFAULT_TLS_DURATION" \
  '.authority = ((.authority // {}) + {claims: ((.authority.claims // {}) + {minTLSCertDuration: $min, maxTLSCertDuration: $max, defaultTLSCertDuration: $def})})' \
  "$CONFIGPATH" > "$TMP_CONFIG"

mv "$TMP_CONFIG" "$CONFIGPATH"

exec /usr/local/bin/step-ca --password-file "$PWDPATH" "$CONFIGPATH"