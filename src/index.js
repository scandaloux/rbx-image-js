import { fork } from 'child_process';
import path from 'node:path';

const imageFork = path.join(import.meta.dirname, 'imageFork.js');

export function processImages (bulk) {
    return new Promise((resolve, reject) => {
        const returns = [];
    
        const imageProcessor = fork(imageFork);
        imageProcessor.send(bulk);
    
        imageProcessor.on('message', (data) => {
            const i = data.shift();
            returns[i] = data;
            if (returns.filter(Boolean).length === bulk.data.length) {
                imageProcessor.kill();
                resolve(returns);
            }
        });
    })
}

export default async function (fastify) {
    fastify.post('/process-images', async (req, rep) => {
        const result = await processImages(req.body);
        console.log(result);
        rep.send(result);
    })
}
