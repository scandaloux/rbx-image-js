import fs from 'node:fs';
import zlib from 'node:zlib';
import sharp from 'sharp';
import path from 'path';
import axios from 'axios';

async function processImage(id, imgpath, resizeHeight, resizeWidth, compression) {
  try {
    let img;

    if (imgpath.startsWith("http")) {
      img = await axios({
          url: imgpath,
          responseType: "arraybuffer",
      });
      img = img.data;
    } else {
      img = fs.readFileSync(path.join(import.meta.dirname, "content", imgpath));
    }

    img = await sharp(img).toFormat("png");
    const metadata = await img.metadata();
    if (resizeHeight || resizeWidth) {
      img.resize({
          height: resizeHeight && parseInt(resizeHeight) || metadata.height, 
          width: resizeWidth && parseInt(resizeWidth) || metadata.width
      });
    }

    let {data, info} = await img.removeAlpha().raw().toBuffer({ resolveWithObject: true });

    let finalData;

    if (compression == -1) {
      finalData = data.toString("base64");
    } else {
      finalData = zlib.deflateRawSync(data.toString("base64"), { level: compression && parseInt(compression) || 9 }).toString("base64");
    }

    process.send([id, 200, {
      data: finalData,
      width: info.width,
      height: info.height,
      bufferlen: data.length,
    }]);
  } catch (error) {
    console.error(error);
    process.send([id, 500, "Internal server error."]);
  }
}

process.on('message', async (message) => {
  for (const i in message.data) {
    const query = message.data[i];
    const { path, resizeHeight, resizeWidth, compression } = query;
    if (!path) {
        return process.send([id, 400, "Missing 'path' parameter."]);
    }
    
    processImage(i, path, resizeHeight, resizeWidth, compression);
  }
});
