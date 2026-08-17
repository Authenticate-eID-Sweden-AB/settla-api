# Settla API

The public HTTP API companies use to move money from their own systems — an
ERP, a billing job, a checkout, or an AI agent acting for a person — where a
human with a BankID is always the last word.

> ## Status: live
>
> **`/v1` answers.** API keys exist, are created in the Settla portal, and the
> capabilities marked **Live** below work today against the running service.
> The service's own declaration of what it can do is `GET /v1` — public, no
> key — and every capability it lists carries a kind: `read`, `act` or
> `signed`. Where this repository and a running answer disagree, the running
> answer wins; open an issue so we fix the text.
>
> Capabilities marked **Proposed** below are still contract-only: batches,
> hosted checkout, webhooks, and sending documents for signature through the
> API. They answer `501 not_implemented`, which is a roadmap, not a bug.

## What Settla is

A Swedish signing and payment service where **BankID is the only key**. There
are no passwords: a personnummer identifies a person, and an account is created
the first time they log in.

**Settla never holds money.** A payment is placed at the payer's own bank and
settles from their account to the recipient's. There is no Settla balance,
wallet or float, and no API call can create one.

## The one rule this API is built around

**An API key cannot sign.** A key lets your system *prepare* — place a payment
at the bank, open a bank connection — and every one of those preparations ends
in a BankID signature by a named human, in their BankID app, on their own
device. The signature, not the API call, is what moves money. This is
deliberate, and it is the reason an autonomous system can be given a key at
all: the worst outcome of a leaked key, a bad prompt or a runaway loop is a
queue of unsigned orders that expire.

So every capability is one of three declared kinds:

| Kind | What it means |
|---|---|
| `read` | Answers immediately. The majority. |
| `act` | Changes something that is Settla's to change — cancelling a request, revoking a key. Immediate. |
| `signed` | Places the thing and returns a **signing order**: a QR to show, an autostart token for the device that holds the BankID app, and one route to poll. The person signs; you poll. |

A caller integrating `signed` endpoints is not doing bank integration. Behind
one identical flow sit several Swedish banks with different authorisation
models, payment products and status vocabularies — absorbing that difference
is the product.

## Endpoints

The authoritative list is `GET /v1`. As of 2026-08-17:

| Endpoint | Purpose | Status |
|---|---|---|
| `GET /v1` | The capability list itself. No key needed. | **Live** |
| `GET /v1/me` | The account behind this key | **Live** |
| `GET /v1/banks` | Banks that can be connected and paid from, with per-bank availability | **Live** |
| `GET /v1/accounts` | Every account at every connected bank, with balances (`?refresh=false` reads without touching the banks) | **Live** |
| `GET /v1/accounts/{id}/transactions` | Transactions for one account | **Live** |
| `POST /v1/bank-connections` | Connect a bank — returns a signing order | **Live** |
| `POST /v1/payments` | Place one payment — returns a signing order | **Live** |
| `GET /v1/orders/{id}` | Poll a signing order: pending (QR rotates), completed, failed, expired | **Live** |
| `POST /v1/payments/{id}/cancel` | Withdraw an unsigned payment, by its order id | **Live** |
| `GET /v1/payments` · `GET /v1/payments/{id}` | Payments placed through Settla, with the bank's own status | **Live** |
| `POST /v1/payment-requests` | Ask one or more people for money; returns and mails a link per payer | **Live** |
| `GET /v1/payment-requests` · `POST /v1/payment-requests/{id}/cancel` | Read who has paid; withdraw | **Live** |
| `GET /v1/documents` | Documents sent for signature, with signing state | **Live** |
| `GET /v1/documents/{id}/evidence` | The BankID evidence for a document you sent | **Live** |
| `GET /v1/api-keys` · `POST /v1/api-keys/{id}/revoke` | Enumerate and kill this account's keys, from code | **Live** |
| `GET /v1/events` | A held-open SSE stream: nudges when your account's state changes | **Live** |
| `POST /api/verify` | Check whether a PDF is a document Settla holds signatures for. No key. | **Live** |
| `GET /api/verify/evidence/{sha256}` | The raw BankID evidence for that document. No key. | **Live** |
| `POST /v1/documents` · `POST /v1/documents/{id}/sign` | Send and sign documents through the API | Proposed |
| `POST /v1/payments/batch` | Several payments under one signature | Proposed |
| `POST /v1/checkout/sessions` | Hosted checkout | Proposed |
| Webhooks | Push delivery of outcomes | Proposed |

The request and response shapes are in [`openapi.yaml`](openapi.yaml).

## Authentication

```
Authorization: Bearer settla_sk_…
```

Keys are created in the Settla portal under **Profil**, and are shown exactly
once — the service stores only an HMAC, so there is no "show again". A key is
issued only to a finished account: identity proven with BankID, terms
accepted, e-mail verified, a bank account connected. That gate is re-checked on
every call, not trusted from mint time.

A key authenticates; it does not authorise beyond the person. It reaches
exactly what the person could reach logged in — one account, nothing else —
and it can revoke itself, which is the correct response to a leak.

`Idempotency-Key` is honoured on `POST /v1/payments`: replaying with the same
key resolves to the payment that already exists at the bank rather than
placing a second one. Without the header one is derived from what the payment
*is* (payer, source, destination, amount, reference), so an identical retry is
safe by default. A `Settla-Version` header is proposed, not yet live.

## Signing, and how your system finds out

A `signed` endpoint answers `201` with an order:

```json
{ "order": { "id": "ord_…", "kind": "payment", "bank": "nordea",
             "status": "pending", "qr_data": "bankid.…", "qr_image": null,
             "autostart_token": "…", "poll": "/v1/orders/ord_…" } }
```

Show the person the QR (`qr_data` encodes it; some banks send a finished PNG
in `qr_image` instead — carry both), or on the device that holds their BankID
app, launch `bankid:///?autostarttoken=…`. **The QR rotates**: render what the
latest poll returns, not what the start returned. Poll `GET /v1/orders/{id}`
until `status` is `completed`, `failed` or `expired`. Orders are minutes-long;
an order lost to a restart is re-placed, and idempotency resolves it to the
same payment.

For being told rather than asking, `GET /v1/events` holds open a Server-Sent
Events stream of nudges — an event says *look again*, never the state itself;
re-read the resource when nudged. Webhooks remain proposed.

Do not treat your own API call as the outcome. The person may decline.

## What a completed payment order does not mean

A completed order means the payer **signed** and the bank **accepted** the
payment. It does not mean the money has arrived. Between signature and
clearing a payment can still fail or be reversed, and different banks report
that window differently — some sit in a reversible accepted state until the
next clearing cycle.

So this API reports the bank's own words: each payment carries the bank's
`status`, and a human-readable `label`/`detail` that deliberately never say
"settled" or "paid". Whether money has arrived is the recipient's conclusion
to draw, from their own account. Reconcile on what your bank statement shows,
never on `signed`.

## Amounts, recipients and references

Swedish payment detail, because getting it wrong is the most common
integration bug:

- **Amounts** are decimal strings — `"7031.00"`, dot decimal, at most two
  decimals. A number is accepted but is refused, not rounded, if it does not
  survive two decimals. Domestic payments are SEK.
- **Recipients** (`to_account`) are an IBAN, or a giro number with
  `to_account_type` set to `BGNR` (bankgiro) or `PGNR` (plusgiro) —
  the service refuses to guess between the two giro registers.
  `creditor_name` is required: the bank shows the signer who is being paid.
- **The source** (`from_account`) is one of the person's own accounts from
  `GET /v1/accounts`. The bank is resolved from it; naming `bank` explicitly
  is allowed and settles ambiguity.
- **References**: a numeric `reference` (2–25 digits) is an OCR number; free
  text goes in `message`.

## Verification, which needs no key

The verifier is public, unauthenticated, and answers on the running portal.
You hold the file; the hash is the entitlement. Nothing is stored.

```sh
curl -s -X POST https://test.settla.se/api/verify \
  -H 'Content-Type: application/pdf' \
  --data-binary @signed-document.pdf
```

A hit returns each signer, when they signed, the BankID certificate, and — the
part worth reading — what was *not* checked. See
[`examples/verify.sh`](examples/verify.sh).

The evidence bundle behind that answer can be verified without trusting Settla
at all, using the open-source tool at
[settla-signature-verifier](https://github.com/Authenticate-eID-Sweden-AB/settla-signature-verifier).

`test.settla.se` is a test host and will change. Do not hard-code it.

## Contributing

This contract is published to be argued with. If a field is missing, an error
is unhelpful, or a flow does not survive contact with your system, open an
issue.

## Related

- [settla-signature-verifier](https://github.com/Authenticate-eID-Sweden-AB/settla-signature-verifier)
  — verify a Settla signature without trusting Settla.
