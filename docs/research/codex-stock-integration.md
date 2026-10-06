# Stock Codex integration

Reviewed October 6, 2026 against installed Codex 0.159.3 help, pristine 0.159.3 source and official documentation. No inference, sign-in, credential access, compilation or installed-app changes were performed.

Stock Codex supports native image generation and editing. Its supported app-server surface does not provide the controls needed to make it a bounded Daydreaming image provider. Do not add it as a selectable image provider with promises of one approved edit per request.

## Shipped manual handoff

Daydreaming offers **Create in Codex…** as an explicit manual action. It exports the currently chosen, cropped source picture as an orientation-corrected PNG without its original EXIF metadata, alongside the supplied instructions, in a new folder selected by the user. It opens the stock desktop app with a [supported new-chat link](https://learn.chatgpt.com/docs/reference/commands#chats), containing that folder's absolute path and the instructions as composer text. The user reviews and sends the message in Codex. Opening the chat does not send it or start generation.

This route does not bundle or compile Codex, read credentials, invoke an agent process, change the wallpaper, create a queue job, or use the Daydreaming image ledger. Sending in Codex uses that app's own account and usage limits. The request asks for one reference edit, but this is a prompt, not a technical call limit. Stock Codex retains its own tools and permissions. There is no automated import or background Codex schedule. Daydreaming's automatic previews and wallpaper updates continue to use the OpenAI Images API.

The exported folder is intentionally retained as a user-owned exchange folder. If the desktop app is unavailable, Daydreaming provides an installation help link and performs no export. If opening fails after export, the files remain available for the user. Returning a result through Daydreaming's ordinary picture chooser adopts it as a new source picture and follows that chooser's normal preview behavior.

Offline tests cover exact URL query encoding without automatic-send parameters, export contents and metadata, preservation of the source, use of the approved crop and failure cleanup. They do not prove a live Codex edit, because no signed-in or paid call was performed.

## Two different routes

The [Sign in with ChatGPT preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) exclude image-generation tools for ChatGPT plan usage through `api.openai.com/v1`, including app-server configured for that route. Image inputs remain supported. That restriction does not establish that native Codex image generation is unavailable.

The [native image-generation documentation](https://learn.chatgpt.com/docs/image-generation) explicitly supports CLI image references with `-i` or `--image`. Built-in generation uses `gpt-image-2` and counts toward Codex usage limits. In 0.159.3, `features.image_generation` is stable and enabled by default, subject to model, provider and account eligibility.

## Verified stock limitations

The [app-server workflow](https://learn.chatgpt.com/docs/app-server) is `initialize`, `initialized`, `thread/start`, then `turn/start` with text and image input. There is no direct image-generation or image-edit RPC in the pinned client protocol. The model invokes the `image_gen.imagegen` function tool during an agent turn.

The stock tool accepts a prompt, transparency choice and either up to five absolute image paths or one to five recent conversation images. No reference selects generation; a reference selects editing. Both routes use automatic quality and size. The tool emits `item/completed` with an `imageGeneration` item containing base64 image data and optional saved-path metadata, then agent execution can continue.

The Rust extension API contains `ToolPolicy.allowed_tools`, but stock CLI configuration and app-server requests do not expose it. No exposed configuration or protocol field provides a hard image-call budget. Neither prompting nor stopping after the first image event guarantees one paid edit or use of the approved attachment.

[PreToolUse hooks](https://learn.chatgpt.com/docs/hooks) can block or rewrite supported calls, including this function-tool path. Their documented error, timeout and malformed-response behavior can continue execution. They are not a strict spending or attachment boundary.

Experimental `environments: []` removes environment-dependent shell, patch and image-view tools. An inline image can still support a history-based edit, but the model can choose generation instead, invoke image generation again or use remaining utility and extension tools. This does not establish an image-only registry.

## Isolation and the supported alternative

[Configuration](https://learn.chatgpt.com/docs/config-file/config-reference) can disable shell, code mode, apps, plugins, multi-agent tools, hooks and web search. MCP servers require individual disabling or verification of the effective configuration. An isolated `CODEX_HOME` does not suppress system or managed configuration. Command network restrictions do not cover every other tool's traffic.

App-server supports `externalSandbox` when the host already confines the process, avoiding Codex sandbox enforcement. [Apple child-process sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) inherits the app's access scope, not an approved-image-only scope. Stock execution inside Daydreaming's sandbox has not been validated.

Daydreaming's existing direct OpenAI Image API provider remains the supported programmatic alternative. It uses an API key and API billing, with the app controlling the submitted attachment and request. Native image documentation directs programmatic generation to the [Image API guide](https://developers.openai.com/api/docs/guides/image-generation). ChatGPT plan sign-in cannot currently replace that API key through the documented SIWC route.

Adding stock Codex as a bounded provider requires a supported direct image RPC or exposed, enforceable tool and call restrictions. A custom fork is outside the owner's requested approach.
