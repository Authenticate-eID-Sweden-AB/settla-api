#!/usr/bin/env bash
# Verify a signed PDF against Settla, and pull the evidence behind the answer.
#
# This example works today. It needs no API key and no account — you hold the
# file, and its hash is the entitlement.
#
#   ./verify.sh signed-document.pdf
set -euo pipefail

# A test host. It will change; do not hard-code it in an integration.
BASE="${SETTLA_BASE:-https://test.settla.se}"
FILE="${1:?usage: verify.sh <file.pdf>}"

echo "Asking $BASE about $(basename "$FILE")"
RESULT=$(curl -fsS -X POST "$BASE/api/verify" \
  -H 'Content-Type: application/pdf' \
  --data-binary "@$FILE")

KNOWN=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["known"])')

if [ "$KNOWN" != "True" ]; then
  # Not a 404: the question was answered. The smallest change to a file — one
  # space, a re-export from a PDF reader — gives a different hash and no match.
  printf '%s' "$RESULT" | python3 -m json.tool
  echo "No signature matches this file."
  exit 1
fi

printf '%s' "$RESULT" | python3 - <<'PY'
import json, sys
r = json.load(sys.stdin)
d = r["document"]
print(f'{d["filename"]}  [{d["status"]}]')
print(f'you sent the {r["matched"]} file')
for s in d["signatures"]:
    v = s.get("verification", {})
    print(f'\n  {s["name"]} ({s["role"]})  {s["personal_number"]}  {s["at"]}')
    print(f'    xmldsig valid ............ {v.get("xmldsig_valid")}')
    print(f'    covers this document ..... {v.get("signed_payload_matches_manifest")}')
    chain = v.get("chain") or {}
    if chain:
        # Two separate facts, and the second is always false. A chain that hangs
        # together internally is not a chain anchored in a BankID root.
        print(f'    chain internally linked .. {chain.get("links_verified")}')
        print(f'    anchored in a BankID root  False  <- never checked here')
    for note in v.get("notes", []):
        print(f'    note: {note}')
print(f'\nevidence: {r["evidence_url"]}')
PY

# The bundle is the point: it can be checked with your own tools, or with
# github.com/Authenticate-eID-Sweden-AB/settla-signature-verifier.
SHA=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha256"])')
curl -fsS "$BASE/api/verify/evidence/$SHA" -o evidence.json
echo "wrote evidence.json"
