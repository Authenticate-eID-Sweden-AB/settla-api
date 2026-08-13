# Paying a batch of invoices from your own system

**Proposed. Nothing here answers a request today** — see the status block in the
[README](../README.md). This is what an invoice run is meant to look like, written
out so it can be argued with before it is built.

The shape to keep in mind: your system prepares, a person signs, the bank
settles. Your API call is never the last step.

## 1. Prepare the batch

One request, one signature for the lot. The `Idempotency-Key` is not optional
and not decoration — it is what makes it safe for a nightly job, or an agent,
to retry.

```sh
curl -X POST https://api.settla.se/v1/payments/batch \
  -H "Authorization: Bearer $SETTLA_KEY" \
  -H "Idempotency-Key: invoice-run-2026-08-13" \
  -H "Settla-Version: 2026-08-13" \
  -H "Content-Type: application/json" \
  -d '{
    "signer": {"name": "Scott Alexander Millar", "email": "scott@millar.se"},
    "payments": [
      {
        "recipient": {"kind": "bankgiro", "number": "5099-2429"},
        "amount": "7031.00", "currency": "SEK",
        "reference": {"ocr": "1234567897"},
        "due_date": "2026-08-28",
        "metadata": {"our_invoice_id": "INV-4471"}
      },
      {
        "recipient": {"kind": "iban", "number": "LT643250090327964206"},
        "amount": "1010.56", "currency": "EUR",
        "reference": {"message": "Faktura 2026-118"},
        "metadata": {"our_invoice_id": "INV-4472"}
      },
      {
        "recipient": {
          "kind": "bankaccount", "clearing": "8327-9", "number": "64206",
          "name": "Millar Konsult AB"
        },
        "amount": "2450.00", "currency": "SEK",
        "metadata": {"our_invoice_id": "INV-4473"}
      }
    ]
  }'
```

Three things in that body are worth pointing at:

- Amounts are **strings with two decimals**. Not floats, and not öre as an
  integer.
- The third recipient is a `bankaccount` and therefore carries a `name`. The
  giro kinds do not need one — there is a register. For a plain account number
  there is nothing to look up, so an unnamed one is rejected.
- `metadata` comes back unchanged on every response and every webhook. It is how
  you reconcile without keeping your own map of Settla ids.

## 2. Give the link to a person

```json
{
  "id": "pb_01J...",
  "status": "created",
  "sign_url": "https://settla.se/b/9f3c…",
  "total": "9481.00",
  "payments": [ … ]
}
```

Put `sign_url` wherever the person who approves payments already is — your own
approvals screen, an email, a Slack message. They identify with BankID, see
every recipient and amount and the total, and sign once.

They do not need a Settla account.

## 3. Learn what happened, from Settla and not from your own call

```json
{"id": "evt_…", "type": "payment.signed",   "data": {"id": "pay_…", "status": "signed"}}
{"id": "evt_…", "type": "payment.executed", "data": {"id": "pay_…", "status": "executed",
                                                     "executed_at": "2026-08-14T08:12:04Z"}}
```

Verify the delivery signature before acting on the body.

**Reconcile against `executed_at`, never `signed_at`.** A signed payment is a
signed authorisation; the money moves when the bank settles it, and today the
service holds an Account Information consent only, so nothing is instructed at
all. `payment.executed` is the sole event that means money moved.

A person may also decline, and a batch may expire unsigned. Both are ordinary
outcomes, not errors: handle `payment.declined` and `payment.expired`.

## What this deliberately does not offer

No endpoint executes a payment. There is no `POST /v1/payments/{id}/execute` and
there will not be one, because that would be an API key moving money — the exact
thing this design is built to make impossible.
