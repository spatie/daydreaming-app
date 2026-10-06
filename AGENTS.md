# Owner instructions

## Installed builds

The owner gave standing permission on October 6, 2026 to install Daydreaming updates. After review, passing tests, and a successful Release build, install and open the verified signed build at `~/Applications/Daydreaming.app` without asking again.

For every verified production update, force quit the process at the exact installed app path before replacing the bundle, then launch the new installed app. Verify its new PID and source stamp. This automatic restart preference was explicitly requested on October 6, 2026. Let an in-flight paid image finish before an automatic update; an explicit request to force quit now authorizes an immediate restart. Scratch builds and test runs do not restart the owner's app.

Coordinate one installer at a time. Preserve the production bundle identifier, Spatie Developer ID signature, preferences, and Keychain identity. Build from an isolated immutable copy of the reviewed sources and stamp the source revision or snapshot digest in the bundle.

Agent test builds use isolated preview identifiers and services. Never install a preview build or invoke paid image creation as an installation check. Commits and deployment still require their own authorization.
