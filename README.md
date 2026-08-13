# Settla API

The public HTTP API companies use to move money from their own systems — an
ERP, a billing job, a checkout, or an AI agent acting for a person — where a
human with a BankID is always the last word.

> ## Status: not live
>
> **Nothing under `/v1` is implemented.** No base URL is allocated, no API keys
> exist, and no endpoint in this repository will answer a request today. This is
> the contract, published while it is still cheap to change, so the companies
> who will use it can argue with it before it is built.
>
> Two endpoints *are* live and callable right now, and they are marked **Live**
> below: the public document verifier. They need no key and no account.
>
> Follow this repository for the change from proposed to live. When it happens,
> this block is what will say so.

## What Settla is

A Swedish signing and settlement service where **BankID is the only key**. There
are no passwords: a personnummer identifies a person, and an account is created
the first time they log in.

**Settla never holds money.** Payments settle directly from the payer's own bank
account to the recipient. There is no Settla balance, wallet or float, and no
API call can create one.

## The one rule this API is built around

**An API key cannot move money.** A key lets your system *prepare* a payment. It
produces something a person must then sign with their BankID, and the signature
— not the API call — is the instruction. This is deliberate, and it is the
reason an autonomous system can be given a key at all: the worst outcome of a
leaked key, a bad prompt or a runaway loop is a queue of payments nobody signs.

So every payment moves through the same three stages:

| Stage | Who acts | What exists |
|---|---|---|
| `created` | your system, with an API key | An authorisation, with a URL a person can open |
| `signed` | a person, with BankID | A signed authorisation, with evidence attached |
| `executed` | the bank | Money has moved |

The gap between `signed` and `executed` is real and is not a formality — see
[What `signed` does not mean](#what-signed-does-not-mean).

## Endpoints

| Endpoint | Purpose | Status |
|---|---|---|
| `POST /api/verify` | Check whether a PDF is a document Settla holds signatures for | **Live** |
| `GET /api/verify/evidence/{sha256}` | Download the raw BankID evidence for that document | **Live** |
| `POST /v1/payments` | Prepare one payment for signature | Proposed |
| `POST /v1/payments/batch` | Prepare several payments settled under one signature | Proposed |
| `GET /v1/payments/{id}` | Read a payment's stage | Proposed |
| `POST /v1/payment-requests` | Ask someone for money; returns a link per payer | Proposed |
| `GET /v1/payment-requests/{id}` | Read who has paid | Proposed |
| `POST /v1/checkout/sessions` | Hand a customer to Settla's hosted checkout and get them back | Proposed |
| `POST /v1/documents` | Send a document for signature | Proposed |
| `GET /v1/documents/{id}` | Read who has signed and who is outstanding | Proposed |

The full contract, including every field and error, is in
[`openapi.yaml`](openapi.yaml).

## Verification, which works today

The verifier is public, unauthenticated, and answers on the running portal. You
hold the file; the hash is the entitlement. Nothing is stored.

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

## Authentication (proposed)

```
Authorization: Bearer sk_live_…
```

Keys are created in the Settla portal, on a personal or a company account, and
are shown exactly once. A key acts **for one account** — everything it creates
belongs to that account and nothing else is visible to it.

Two headers matter beyond the key:

- `Idempotency-Key` — required on every POST that creates something. Replaying a
  request with the same key returns the original object rather than making a
  second one. Payments are exactly the place an agent's retry loop must not cost
  money twice.
- `Settla-Version` — the dated contract version your integration was written
  against. Omitting it pins you to the account's default, which we may move.

## Signing, and how your system finds out

A created payment carries a `sign_url`. Give it to the person who must sign: put
it in your own UI, mail it, or hand it to them in whatever channel your product
already uses. They identify with BankID, see what they are signing, and sign it.
They need no Settla account to pay.

Your system learns the outcome in one of two ways:

- **Webhooks** — `payment.signed`, `payment.executed`, `payment.declined`,
  `payment.expired`, `request.paid`, `document.signed`. Each delivery is signed;
  verify the signature before acting on the body.
- **Polling** — `GET /v1/payments/{id}`, if you would rather not run an endpoint.

Do not treat your own API call as the outcome. The person may decline.

## What `signed` does not mean

The portal today signs a payment *authorisation* and records it. It does not
instruct any bank. The bank connection it holds is an **Account Information**
consent — it can read the payer's accounts and balances after they identify at
their bank, and that is all.

Whether Settla may initiate payments, and under whose PSD2 authorisation, is an
open legal question rather than an unfinished piece of code. Until it is settled,
a payment reaching `signed` has moved no money, `executed_at` stays null, and
nothing in this API will claim otherwise.

This is stated here, in the spec, and on every screen the payer sees, for the
same reason: an integrator who reads `signed` as `paid` will reconcile a month
that never happened.

## Amounts, recipients and references

Swedish payment detail, because getting it wrong is the most common integration
bug:

- **Amounts** are decimal strings — `"7031.00"`, never a float and never öre as
  an integer. Currency is ISO 4217. Both `SEK` and foreign-currency invoices
  occur.
- **Recipients** are one of four kinds: `bankgiro`, `plusgiro`, `bankaccount`
  (clearing plus account number) and `iban`. `bankaccount` **requires a
  recipient name**, because unlike the giro registers there is nothing to look
  it up in.
- **References** are either an OCR number, which is validated with a Luhn check
  and a length check, or a free-text message. Not every invoice has either.
- Amounts are displayed to the payer in Swedish convention (`7 031,00 SEK`)
  regardless of how you send them.

## Contributing

This contract is published to be argued with. If a field is missing, an error is
unhelpful, or a flow does not survive contact with your system, open an issue —
that is worth considerably more now than after it ships.

## Related

- [settla-signature-verifier](https://github.com/Authenticate-eID-Sweden-AB/settla-signature-verifier)
  — verify a Settla signature without trusting Settla.
