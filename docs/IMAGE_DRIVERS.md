# Image drivers

Daydreaming has one active image provider, selected under Settings > Image AI. The scheduler, preview flow, crop, daily ledger and wallpaper application use the same pipeline for every provider. They do not instantiate an API client or read a provider's key.

OpenAI is the default and currently the only provider offered in normal Settings. The generic compatible adapter remains available for integration work, but is hidden until an actual service is verified. An already configured connection remains visible for recovery. A provider chooser appears when more than one supported driver is available.

The compatible adapter implements the OpenAI Images edit contract: HTTPS base URL, image model, optional faster preview model and its own API key. The driver adds `/images/edits` to the base URL. The service must accept a multipart source image, prompt, model, quality, size, PNG output and `n=1`, and return PNG image data in `data[0].b64_json`. This is a protocol adapter, not a claim that every AI service supports it. Actual third-party compatibility requires that service to implement this contract.

Keys stay in Keychain, separately scoped to the driver and server. Other providers never use the OpenAI key or its legacy migration. Switching servers requires that server's own key. Previously configured providers retain their settings and credentials but only the selected provider runs. There is no fallback to another provider, retry against another account or simultaneous connection for generation.

Switching providers pauses automatic updates, cancels unpaid work and keeps the current desktop. Already submitted work finishes under its original provider and is cached, without applying to the desktop. Connecting does not generate an image. Use This Picture & Idea as Wallpaper resumes with the selected connection through the existing counted pipeline.

## Contract

`ImageGenerationDriver` owns request validation and editing. It accepts an `ImageGenerationRequest` and credential, prepares one edit and invokes `willSend` immediately before submitting it. The app's `willSend` gate checks cancellation, the active connection, recipe, window state and remaining budget, then persists the reservation. Known rejected requests invoke `didReject`; ambiguous failures keep the reservation. Drivers return image bytes or throw a useful error. The HTTP adapter has no automatic generation retries and refuses redirects so a picture or credential is never forwarded to a different server.

`ImageGenerationService` resolves the selected driver through `ImageDriverRegistry`, reads only that connection's credential and performs the edit. Unknown or invalid providers fail before reading credentials or submitting work. The registry is injectable for offline tests. Production credentials use `KeychainImageCredentials`; tests use an in-memory implementation.

`ImageDriverDescriptor` supplies the provider name, cost wording, key-management and billing links. Visible help, crop explanations and accessibility text use that descriptor. Settings are non-secret Codable data. Provider, endpoint and configured model identities join the cache recipe; the original default OpenAI configuration leaves existing keys unchanged. Switching back can therefore reuse already purchased images. The daily budget remains shared across providers.

To add another API, implement `ImageGenerationDriver`, supply its descriptor and configuration validation, and register the driver. Map Daydreaming's preview/full profile, source and desired output inside the driver. Add provider-specific authentication or Settings fields if needed. Do not add provider branches to `AppModel`, `HourlyGenerationProcessor`, crop or preview scheduling. Test request mapping, cancellation, rejection accounting, cache identity and credential isolation with a mock transport before a live integration.

## Codex

Codex's existing action is a manual export into the Codex desktop app, not an image driver. It does not return an image to Daydreaming or supply automatic updates. The misleading separate Codex connection section has been removed from Settings; the manual action remains in the Wallpaper menu.

As checked on October 7, 2026, the [official Sign in with ChatGPT preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) explicitly exclude image-generation tools. Native Codex image generation is a different route, discussed in [the stock Codex investigation](research/codex-stock-integration.md). This refactor does not add a custom Codex runtime, use undocumented subscription endpoints or pretend that a chat handoff is a connected provider. A future supported Codex image adapter can implement the same driver contract.

## Verification

Offline tests cover single-driver routing, credential isolation, missing/unknown-provider rejection, edit input and one-image request mapping, legacy cache and settings migration, provider-specific disclosure and switching during both unpaid preparation and an already paid request. No owner's credentials are read by the tests and no image generation is performed against a real service.
