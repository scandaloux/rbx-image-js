# rbx-image-js

The nodejs src takes in 1 or multiple images and processes them all in parallel, then returns the compressed and base64 encoded format.
This format is used to be efficiently and quickly read by decode.luau in Roblox.

(The js is written in ESM, so you may need to convert them to .mjs or use "type": "module" in packages.json respectively.)
