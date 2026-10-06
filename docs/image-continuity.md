# Image continuity assessment

The current app uploads one prepared original for each edit and asks the model to preserve composition and subjects.

The Images edit API accepts multiple input pictures in one request. A second reference adds image-input tokens to the price; requesting one output still remains one image request. See the official [image generation guide](https://developers.openai.com/api/docs/guides/image-generation) and [edit reference](https://developers.openai.com/api/reference/resources/images/methods/edit).

Using the original plus a prior generated wallpaper could improve continuity, but that is an inference requiring an owner comparison. The original should remain the framing and landmark authority. The second picture should guide the appearance of the scene, while the prompt changes time and weather. Repeatedly treating the latest output as the new original could accumulate errors.

A later API trial should only use a prior full wallpaper with the same original, crop, prompt and style. It must exclude drafts and unrelated gallery selections. Freeze the reference when a job is queued, record its digest with the output, and include it in the generation request identity. Keep a separate semantic lookup for already-paid matching hours so advancing the reference does not silently buy them again. Preserve legacy cache compatibility, one output, one ledger submission and serial ordering.

A comparison using the original alone and the original plus one prior full-quality reference remains pending. No dual-reference behavior has been added to the app, and no paid comparison has been run. The implementation continues to upload one prepared original. Any future trial must compare framing, landmark preservation, style drift, elapsed time, and input usage before claiming an improvement.
