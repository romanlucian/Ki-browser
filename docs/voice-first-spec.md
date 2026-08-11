# Voice-first browser direction

**Status:** safe initial direction and local macOS input shell, August 2026. Voice is an additional primary interface; visual address/search, pages, answers, and sources remain available.

## Focused experience

The intended loop is:

1. The user explicitly presses the microphone button or a keyboard shortcut.
2. Clearframe visibly listens and produces a live transcript in the normal address/search field.
3. The user reviews or edits the transcript and submits it.
4. Clearframe performs ordinary search/retrieval, then presents a concise answer beside visible source links and page context.
5. If requested, the answer can be spoken while the same text, citations, and controls remain on screen.
6. Any consequential action—purchase, message, form submission, account change, download execution, or sharing private data—requires a separate, specific confirmation showing exactly what will happen.

The current implementation covers steps 1–3 only. It never submits a voice query automatically, speaks an uncited answer, or takes actions.

## Current smallest safe macOS phase

The toolbar microphone is user-triggered and uses Apple Speech with `en-US` on-device recognition only when the Mac reports that capability. It:

- requests microphone and speech-recognition permission only after the microphone button is clicked;
- shows a persistent listening state and live transcript;
- fills the visible address/search field for review;
- requires Return or **Go** before navigation;
- stops when the user clicks Stop, changes tabs, closes the view, or the app becomes inactive;
- does not save audio, run in the background, call an external speech provider, or require external credentials;
- leaves typed search fully available when recognition or permission is unavailable.

The app bundle includes narrowly worded microphone and speech permission descriptions. This phase should be tested on supported Macs because on-device recognition availability varies by OS, hardware, language assets, and locale.

## Privacy and permission model

- No wake word and no always-listening process.
- The mic starts only from a clear user action and has an equally clear Stop control.
- The UI must expose whether it is requesting permission, listening, ready for review, or unavailable.
- Audio is ephemeral and not written to disk by Clearframe.
- The transcript stays local until the user submits it as a normal search/address request.
- A future cloud speech provider must be opt-in per use, show the provider and retention implications before capture, minimize transmitted audio/text, and offer an on-device-only setting.
- Voice transcripts must never be mixed into analytics, advertising profiles, or browsing-history sales.

## On-device and provider tradeoffs

On-device recognition offers the clearest privacy boundary, lower marginal cost, offline potential, and low latency. Its limitations are language coverage, model availability, noisy-room accuracy, and hardware/OS variation.

A provider can improve multilingual recognition and difficult audio, but introduces network dependency, cost, retention/subprocessor questions, and a larger breach surface. It should be a later optional capability, not a silent fallback. Product copy must not claim that Apple or a future provider is fully offline, private, or accurate without platform-specific verification.

## Answer and source design

A later retrieval phase should keep voice and visual output synchronized:

- show the interpreted query before retrieval;
- provide a short answer with numbered, clickable sources;
- distinguish page statements from Clearframe inference;
- let the user pause, replay, slow, or disable speech;
- never read sensitive page content aloud without an explicit action;
- decline to summarize when source support is inadequate rather than inventing an answer.

Spoken output can use system text-to-speech initially. It must not remove the visual answer or citations.

## Consequential-action boundary

Voice must not turn the reading assistant into an autonomous agent. A future action flow needs a preview containing the target, exact action, important values, affected account, and data to be sent. Confirmation must be a new interaction, not inferred from the original query. Payments, legal acceptance, credential entry, security changes, and irreversible actions need stronger authentication or may remain unsupported.

## Accessibility requirements

- Every voice function has keyboard, pointer, and screen-reader equivalents.
- Live transcripts are editable and status changes have accessible labels.
- Spoken answers always have visible text and sources; no information is voice-only.
- Support adjustable speech rate, pause/replay, captions, and reduced-motion preferences in later phases.
- Test with VoiceOver, keyboard-only navigation, speech impairments, hearing impairments, accents, and noisy environments.

## Next gated phases

1. Validate explicit dictation and permission comprehension on supported Macs.
2. Add a retrieval result contract that requires source URLs and separates quotes, source claims, and synthesis.
3. Add optional system text-to-speech for the already-visible sourced answer.
4. Threat-model confirmation flows before enabling any page action.
5. Consider opt-in cloud speech only if measured recognition failures justify its privacy and cost burden.
