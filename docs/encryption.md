# ClipMate End-to-End Encryption

ClipMate can encrypt clipboard text on the client before it is sent to the relay.

When `Encryption Secret` / `CLIPMATE_SECRET` is set, clients send the `text` field as a JSON envelope:

```json
{
  "v": 1,
  "alg": "AES-256-GCM-SHA256",
  "data": "base64(nonce || ciphertext || tag)"
}
```

The encryption key is:

```text
SHA-256(UTF-8 secret)
```

The relay stores and forwards the encrypted envelope only. It can still see device names, rooms, timestamps, payload size, and access token use, but not clipboard content.

All devices in the same room must use the same `Token`, `Room`, and `Encryption Secret`.
