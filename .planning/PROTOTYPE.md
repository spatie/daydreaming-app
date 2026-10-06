# Daydreaming editor redesign

The owner rejected the floating panel and requested a complete redesign using Photos as a reference. The prompt must remain visible and the hour slider must stay fluid. Paid work remains serial, counted, and isolated from visual testing.

## Alternatives

The six named SwiftUI previews in WeatherCanvas/DesignAlternatives.swift are compiled only in Debug. They use local sample data and the bundled Yosemite picture, with no production services.

| Preview | Organizing idea | Assessment |
| --- | --- | --- |
| Photos Desk | Native toolbar, separate canvas, attached editor | Chosen base |
| Quiet Inspector | Canvas plus an inspector | Hides the prompt when collapsed |
| Prompt First | Prompt above the artwork | Gives editing priority over the picture |
| Library Desk | Saved images with a detail editor | Adds navigation to the primary workflow |
| Prompt Conversation | Changes as a conversation | Less direct for hour browsing |
| Day Filmstrip | Hour thumbnails below the image | Replaces the explicitly requested slider |

## Chosen structure

Use a native titlebar and toolbar above an image workspace, with permanent prompt and slider controls below the artwork. Available hours are marked on the slider. A missing hour dims and blurs the fallback image and shows a material-backed status card. Desktop truth lives in the window subtitle; an idle current wallpaper has no primary button pretending to be a status label.

Crop is an inline editing mode. Fit This Display uses the window's display aspect ratio. Drag the frame, resize its corners, or use keyboard adjustment. Reset, Cancel and Done stay in the toolbar. Conflicting menu commands are disabled during cropping. The original stays intact. Only changed Done schedules a counted draft, after closing crop mode.

## States and verification

Actual model tests cover a missing hour, an unsaved prompt, preparation, drafting, ready drafts, full-quality upgrades, desktop selection and queued counts. Geometry tests cover constrained crop movement and resizing. The latest run passes 249 tests and the Release build succeeds.

Artwork transitions use a 0.2 second fade. Waiting light breathes over 3.8 seconds with a restrained 0.95 to 1.1 scale range. Reduce Motion uses static feedback and a ProgressView.

Native layout approval remains provisional until the installed app is inspected with real content. The owner should judge idle, a missing hour while drafting, crop mode, and a portrait picture at the minimum window size. Agent verification makes no paid image request.
