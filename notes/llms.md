# VoiceInk's Recommended Models — Limitations & Costs

Per [tryvoiceink.com/docs/recommended-models](https://tryvoiceink.com/docs/recommended-models), VoiceInk supports both **transcription** and **enhancement** models.

## Transcription Models

| Model | Type | Cost | Strengths | Limitations |
|---|---|---|---|---|
| **Parakeet** (NVIDIA) | Local / offline | **Free** (runs on-device) | Best real-time accuracy; no latency; no internet needed; fully private | English and major languages only; requires Apple Silicon / sufficient hardware; no non-standard speech support |
| **Whisper large-v3-turbo** (OpenAI) | Cloud | **Free via Groq** free tier; paid tiers vary by provider | Fast, accurate, broad language support | Requires internet; adds network latency; not designed for non-standard / atypical speech |

**Local vs Cloud:** Local models (Parakeet) are recommended for English and major languages due to zero latency and privacy. Cloud models are best for less common languages or when local processing isn't suitable.

### Whisper on Groq (Cloud)

VoiceInk uses Groq-hosted Whisper for cloud transcription. Pricing is per hour of audio transcribed.

| Model | Free Tier Rate Limits | Free Tier Cost | Developer Tier Cost |
|---|---|---|---|
| Whisper large-v3 | 20 RPM / 2K RPD / 7.2K audio sec/hr / 28.8K audio sec/day | **$0** | **$0.111/hr** transcribed |
| Whisper large-v3-turbo | 20 RPM / 2K RPD / 7.2K audio sec/hr / 28.8K audio sec/day | **$0** | **$0.04/hr** transcribed |

> Sources: [Groq Pricing](https://groq.com/pricing) · [Groq Rate Limits](https://console.groq.com/docs/rate-limits)

## Comparing Tokens to Time Spoken

To estimate enhancement costs from audio duration:

- **~150 words/minute** of typical speech → **~200 tokens/minute** (at ~1.3 tokens/word in English)
- **1 hour of speech ≈ 9,000 words ≈ 12,000 tokens** of transcript

| Audio Duration | Approx. Words | Approx. Tokens |
|---|---|---|
| 1 minute | 150 | 200 |
| 10 minutes | 1,500 | 2,000 |
| 1 hour | 9,000 | 12,000 |

So transcription dominates cost. Enhancement token usage from speech is tiny — you'd need ~80+ hours of transcribed text to reach 1M tokens.

## Enhancement Models (AI Post-Processing)

These transform raw transcriptions — fixing grammar, punctuation, formatting, etc.

**Performance guideline:** If enhancement takes >2 seconds, switch providers. The VoiceInk developer currently uses **Gemini 2.0 Flash** for speed and accuracy.

### Groq

> Sources: [Groq Pricing](https://groq.com/pricing) · [Groq Rate Limits](https://console.groq.com/docs/rate-limits)

| Model | Free Tier Limits | Developer Tier Pricing |
|---|---|---|
| gpt-oss-120b | 30 RPM / 1K RPD / 8K TPM / 200K TPD | $0.15 input / $0.60 output per M tokens |
| Kimi-K2 | 60 RPM / 1K RPD / 10K TPM / 300K TPD | $1.00 input / $3.00 output per M tokens |
| Qwen-3-32B | 60 RPM / 1K RPD / 6K TPM / 500K TPD | $0.29 input / $0.59 output per M tokens |

**Developer tier** starts with no minimum — add a credit card and pay per token. Provides higher rate limits than free. Exceeding free tier limits returns HTTP 429 until quota resets; you are never charged while on the free plan.

### Cerebras

> Sources: [Cerebras Pricing](https://www.cerebras.ai/pricing) · [Cerebras Rate Limits](https://inference-docs.cerebras.ai/support/rate-limits)

| Model | Free Tier Limits | Developer Tier Pricing |
|---|---|---|
| gpt-oss-120b | 30 RPM / 900 RPH / 14.4K RPD / 60K TPM / 1M TPH / 1M TPD | $0.35 input / $0.75 output per M tokens |
| Qwen-3-32B | 30 RPM / 900 RPH / 14.4K RPD / 60K TPM / 1M TPH / 1M TPD | $0.40 input / $0.80 output per M tokens |

**Developer tier** starts at **$10** deposit (pay-as-you-go). Provides 10× higher rate limits than free (1K RPM / 1M TPM) with no hourly or daily caps.

### Gemini (Google)

> Sources: [Gemini API Pricing](https://ai.google.dev/gemini-api/docs/pricing) · [Gemini Rate Limits](https://ai.google.dev/gemini-api/docs/rate-limits)

| Model | Free Tier Limits | Paid Tier 1 Pricing |
|---|---|---|
| gemini-2.0-flash | 5–15 RPM / 100–1K RPD / 250K TPM | $0.15 input / $0.60 output per M tokens |
| gemini-2.5-flash-lite | 5–15 RPM / 100–1K RPD / 250K TPM | $0.10 input / $0.40 output per M tokens |

**Paid Tier 1** activates by adding a billing account (no minimum spend). Provides ~10–30× higher RPM. Free tier data may be used to improve Google products; paid tier data is not. ⚠️ Free tier limits were reduced significantly in Dec 2025 and can change without notice. gemini-2.0-flash is deprecated and will shut down June 1, 2026 — migrate to gemini-2.5-flash.

### OpenRouter

> Sources: [OpenRouter Pricing](https://openrouter.ai/pricing) · [OpenRouter Rate Limits](https://openrouter.ai/docs/api/reference/limits)

| Model | Free Tier Limits | Pay-as-you-go |
|---|---|---|
| gpt-oss-120b (via `:free` variant) | 20 RPM / 50 RPD (or 1K RPD with ≥$10 credits purchased) | Pass-through provider pricing + 5.5% platform fee on credit purchases |

**Pay-as-you-go** has no minimum spend. Provides access to 300+ models across 60+ providers. OpenRouter passes through the underlying provider's per-token pricing with no markup on inference — only the 5.5% fee when purchasing credits.
