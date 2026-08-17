# Placing one payment from your own system

**Live.** This is the flow that answers today. The shape to keep in mind: your
system prepares, a person signs in BankID, the bank executes. Your API call is
never the last step.

## 0. Hold a key

Created in the Settla portal under **Profil**, shown once. Everything below is

```sh
AUTH="Authorization: Bearer $SETTLA_KEY"   # settla_sk_…
BASE=https://test.settla.se                # test host; do not hard-code
```

## 1. Find the source account

```sh
curl -s -H "$AUTH" "$BASE/v1/accounts?refresh=false"
```

Pick the paying account's `number` from whichever connected bank should pay.
If nothing is connected yet, `POST /v1/bank-connections` first — same signing
flow as step 3.

## 2. Place the payment

```sh
curl -s -X POST -H "$AUTH" \
  -H "Idempotency-Key: invoice-4471-attempt-1" \
  -H "Content-Type: application/json" \
  -d '{
    "from_account": "SE72 8000 0810 3400 0978 3242",
    "to_account": "5099-2429",
    "to_account_type": "BGNR",
    "creditor_name": "Elbolaget AB",
    "amount": "7031.00",
    "reference": "1234567897"
  }' "$BASE/v1/payments"
```

The answer is a **signing order**, not a payment outcome:

```json
{ "order": { "id": "ord_9f2c66d1a03b71e4c8d20a55", "kind": "payment",
             "bank": "nordea", "status": "pending",
             "qr_data": "bankid.67df3917-…", "qr_image": null,
             "autostart_token": "…", "poll": "/v1/orders/ord_9f2c…" } }
```

## 3. Put it in front of the person

- **Another device**: render `qr_data` as a QR (or show `qr_image` where the
  bank sends a finished PNG — carry both). **The code rotates about once a
  second**: re-render from every poll, never from the start response.
- **Same device as the BankID app**: place the payment with
  `"same_device": true` and open
  `bankid:///?autostarttoken=<token>&redirect=null`. Some banks fix the mode
  when the order is raised — deciding late gives a code that cannot be
  scanned.

## 4. Poll until it ends

```sh
curl -s -H "$AUTH" "$BASE/v1/orders/ord_9f2c66d1a03b71e4c8d20a55"
```

`pending` → keep showing the freshest QR. Then one of:

```json
{ "order": { "status": "completed",
             "payment": { "id": "…", "bank_status": "ACSC",
                          "label": "Signerad", "detail": "…", "signed": true } } }
```

or `failed` / `expired` with a `reason`. The person may decline: do not treat
your own API call as the outcome.

A payment the person abandoned can be withdrawn so nothing lingers at the
bank:

```sh
curl -s -X POST -H "$AUTH" "$BASE/v1/payments/ord_9f2c66d1a03b71e4c8d20a55/cancel"
```

## 5. Reconcile on the bank's words, later

```sh
curl -s -H "$AUTH" "$BASE/v1/payments"
```

Each payment carries the bank's own `status` and a `label`/`detail` that never
say "settled" or "paid". A signed payment can still fail or be reversed before
clearing — reconcile against the account statement, not against the
signature.
