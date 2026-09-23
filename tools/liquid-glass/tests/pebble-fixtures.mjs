// Independent CPU reference: the exact Three.js profile approved by the user.
// Prints fixtures; no file writes, network, compositor or desktop access.
import {samplePebbleHeight} from '../viewer/src/pebble.ts';
import {dimensions, sampleSurface} from '../viewer/src/profile.ts';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const lines=[];
const shapes = [[260,36,18],[480,398,18],[420,440,18],[36,36,18],[800,36,18],[434,250,18]];
for (const [width,height,radius] of shapes) for (const scale of [1,1.6]) {
  const shape={width,height,radius}, peak=dimensions(shape).centreHeight;
  const points=[[0,0],[.1,.2],[.4,.3],[.7,.5],[.9,.9],[.95,.6],[.99,0],[0,.95],[.7,.95],[.5,.99]]
    .map(([a,b])=>[a*width/2,b*height/2]);
  if(height>200) for(const inset of [10,18,24,30,40,60]) for(const offset of [-1,-.1,0,.1,1])
    points.push([width/2-inset,height/2-inset+offset]);
  for (const [x,y] of points) {
    if (sampleSurface(x,y,shape).distance < 0.5) continue;
    const eps=.02, h=samplePebbleHeight(x,y,shape);
    const dx=(samplePebbleHeight(x+eps,y,shape)-samplePebbleHeight(x-eps,y,shape))/(2*eps);
    const dy=(samplePebbleHeight(x,y+eps,shape)-samplePebbleHeight(x,y-eps,shape))/(2*eps);
    const norm=Math.hypot(dx,dy,1);
    lines.push([width,height,radius,scale,x,y,-dx/norm,-dy/norm,1/norm,h/peak].join(' '));
  }
}
if(process.argv.includes('--check')) {
  assert.equal(readFileSync(new URL('./pebble-fixtures.txt',import.meta.url),'utf8').trim(),lines.join('\n'));
  console.log('PASS: '+lines.length+' GPU parity fixtures match the approved viewer profile');
} else console.log(lines.join('\n'));
