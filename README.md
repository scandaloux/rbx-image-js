# rbx-image-js

The nodejs src takes in 1 or multiple images and processes them all in parallel, then returns the compressed and base64 encoded format.
This format is used to be efficiently and quickly read by decode.luau in Roblox.

(The js is written in ESM, so you may need to convert them to .mjs or use "type": "module" in packages.json respectively.)

## Usage

**Lua example**
```lua
local rbximage = require(module)

local url = "https://localhost:6942/image-data" -- this is an example url from the js below
local body = HttpService:JSONEncode({data = {
  {
    path = , -- image url or path in 'content' dir
    resizeWidth = , -- optional resize width
    resizeHeight = , -- optional resize height
    compression = , -- optional compression level, 9 is most compression, 1 is none, 9 is fine for most things (unless you have a really high quality image, you may want to lower the compression level)
  }
})
local response = HttpService:PostAsync(url, body)

local imageStatus, imageContent = unpack(response[1])
local image = rbximage(imageContent.width, imageContent.height, imageContent.data)
-- 1d array of RGBA values, each RGBA being one pixel, and values being from 0 - 1
-- alpha is ALWAYS 1 (newever versions of rbximage may support alpha)
-- {R, G, B, A, R, G, B, A...}
```

**JS example, using fastify (tests/fastify.js)**
```js
import Fastify from 'fastify';
import rbximage from '../src/index.js'; // import rbximage

const fastify = Fastify({
  logger: true,
})

fastify.post("/image-data", async (req, rep) => {
  const result = await rbximage(req.body); // parse the body
  rep.send(result); // send result
})

try {
  fastify.listen({ port: 6942 })
} catch (err) {
  fastify.log.error(err)
  process.exit(1)
}
```
