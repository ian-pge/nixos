// Independent CPU reference: only the approved Three.js model is sampled.
// Finite parametric derivatives deliberately differ from the GLSL derivatives.
import {cushionProfile} from '../viewer/src/cushion.ts';
import {dimensions, sampleSurface} from '../viewer/src/profile.ts';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const lines=[];
const shapes=[[260,36,18],[480,398,18],[420,440,18],[36,36,18],[800,36,18],[434,250,18],
  [480,398,2],[480,398,1],[800,36,1],[80,650,40]];
for(const [width,height,radius] of shapes) for(const scale of [1,1.6]) {
  const shape={width,height,radius}, profile=cushionProfile(shape), peak=dimensions(shape).centreHeight;
  lines.push([width,height,radius,scale,0,0,0,0,1,1].join(' '));
  const corner=Math.atan2(height,width);
  const angles=[0,.05,.15,.3,.55,.8,1.1,1.4,Math.PI/2,corner-.02,corner-.002,corner,corner+.002,corner+.02];
  for(const rho of [.025,.15,.35,.55,.75,.9,.96,.985,.997]) for(const angle of angles) {
    const [x,y]=profile.point(rho,angle);
    if(sampleSurface(x,y,shape).distance<.5) continue;
    const e=1e-5, a=profile.point(rho-e,angle), b=profile.point(rho+e,angle);
    const c=profile.point(rho,angle-e), d=profile.point(rho,angle+e);
    const rx=(b[0]-a[0])/(2*e), ry=(b[1]-a[1])/(2*e);
    const tx=(d[0]-c[0])/(2*e), ty=(d[1]-c[1])/(2*e);
    const rz=(profile.height(rho+e)-profile.height(rho-e))/(2*e);
    const nx=-rz*ty, ny=rz*tx, nz=rx*ty-ry*tx, norm=Math.hypot(nx,ny,nz);
    lines.push([width,height,radius,scale,x,y,nx/norm,ny/norm,nz/norm,profile.height(rho)/peak].join(' '));
  }
}
if(process.argv.includes('--check')) {
  assert.equal(readFileSync(new URL('./cushion-fixtures.txt',import.meta.url),'utf8').trim(),lines.join('\n'));
  console.log('PASS: '+lines.length+' GPU parity fixtures match the approved cushion');
} else console.log(lines.join('\n'));
