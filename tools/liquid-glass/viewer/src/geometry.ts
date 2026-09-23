import * as THREE from 'three';
import {boundaryPoint, sampleSurface, type Shape, type SurfaceProfile} from './profile.ts';
import {pebbleContour, pebbleHeight, pointOnContour, samplePebbleHeight} from './pebble.ts';
import {cushionProfile} from './cushion.ts';

export const WORLD_SCALE = 0.01;
export type ViewerProfile = SurfaceProfile | 'cushion';

export function makeGlass(shape: Shape, heightScale: number, join: ViewerProfile, selection: boolean,
  rings = 112, sectors = 384) {
  const positions: number[] = [], normals: number[] = [], colors: number[] = [], indices: number[] = [];
  const cushion = join === 'cushion' ? cushionProfile(shape) : undefined;
  const levelSurface = join === 'pebble' || join === 'cushion';
  const blue = new THREE.Color('#7dc4e4');
  const add = (x: number, y: number, levelHeight?: number) => {
    if (join === 'pebble' || join === 'cushion') {
      if (levelHeight === undefined) throw new Error('Hauteur du contour manquante');
      positions.push(x * WORLD_SCALE, levelHeight * heightScale * WORLD_SCALE, y * WORLD_SCALE);
    } else {
      const sample = sampleSurface(x, y, shape, join);
      positions.push(x * WORLD_SCALE, sample.height * heightScale * WORLD_SCALE, y * WORLD_SCALE);
      const n = new THREE.Vector3(-sample.dx * heightScale, 1, -sample.dy * heightScale).normalize();
      normals.push(n.x, n.y, n.z);
    }
    const selected = selection && Math.abs(y / shape.height + 0.02) < 0.065 && Math.abs(x) < shape.width / 2 - 12;
    const c = new THREE.Color(1, 1, 1).lerp(blue, selected ? 0.2 : 0);
    colors.push(c.r, c.g, c.b);
  };
  add(0, 0, cushion ? cushion.height(0) : join === 'pebble' ? pebbleHeight(1, shape) : undefined);
  const boundary = Array.from({length: sectors}, (_, i) => boundaryPoint(2 * Math.PI * i / sectors, shape));
  for (let ring = 1; ring <= rings; ring++) {
    // Denser sampling at the rim; the small meniscus must not become a bevel
    // simply because its triangles are wider than its curvature transition.
    const rho = 1 - (1 - ring / rings) ** 2;
    if (cushion) {
      const h = cushion.height(rho);
      for (let i = 0; i < sectors; i++) {
        const [x, y] = cushion.point(rho, 2 * Math.PI * i / sectors);
        add(x, y, h);
      }
    } else if (join === 'pebble') {
      const level = 1 - rho, contour = pebbleContour(level, shape), h = pebbleHeight(level, shape);
      for (let i = 0; i < sectors; i++) {
        const [x, y] = pointOnContour(2 * Math.PI * i / sectors, contour);
        add(x, y, h);
      }
    } else {
      for (const [x, y] of boundary) add(x * rho, y * rho);
    }
  }
  for (let i = 0; i < sectors; i++) {
    const next = (i + 1) % sectors;
    indices.push(0, 1 + next, 1 + i);
    for (let ring = 1; ring < rings; ring++) {
      const a = 1 + (ring - 1) * sectors + i, d = 1 + (ring - 1) * sectors + next;
      const b = 1 + ring * sectors + i, c = 1 + ring * sectors + next;
      indices.push(a, c, b, a, d, c);
    }
  }
  const surface = new THREE.BufferGeometry();
  surface.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  if (!levelSurface) surface.setAttribute('normal', new THREE.Float32BufferAttribute(normals, 3));
  surface.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  surface.setIndex(indices);
  if (levelSurface) surface.computeVertexNormals();
  surface.computeBoundingSphere();

  // This closure is illustrative, not a second surface in the compositor's
  // thin-lens shader. It can be hidden independently in the viewer.
  const basePositions = [0, 0, 0], baseIndices: number[] = [];
  for (const [x, y] of boundary) basePositions.push(x * WORLD_SCALE, 0, y * WORLD_SCALE);
  for (let i = 0; i < sectors; i++) baseIndices.push(0, 1 + i, 1 + (i + 1) % sectors);
  const base = new THREE.BufferGeometry();
  base.setAttribute('position', new THREE.Float32BufferAttribute(basePositions, 3));
  base.setIndex(baseIndices);
  base.computeVertexNormals();

  const cutPositions: number[] = [], cutIndices: number[] = [], line: THREE.Vector3[] = [];
  for (let i = 0; i <= 768; i++) {
    const x = -shape.width / 2 + shape.width * i / 768;
    const rawHeight = join === 'cushion' ? cushion!.sectionHeight(x)
      : join === 'pebble' ? samplePebbleHeight(x, 0, shape) : sampleSurface(x, 0, shape, join).height;
    const h = rawHeight * heightScale * WORLD_SCALE;
    cutPositions.push(x * WORLD_SCALE, 0, 0, x * WORLD_SCALE, h, 0);
    line.push(new THREE.Vector3(x * WORLD_SCALE, h + 0.002, 0.002));
    if (i > 0) { const a = (i - 1) * 2; cutIndices.push(a, a + 2, a + 1, a + 2, a + 3, a + 1); }
  }
  const section = new THREE.BufferGeometry();
  section.setAttribute('position', new THREE.Float32BufferAttribute(cutPositions, 3));
  section.setIndex(cutIndices);
  section.computeVertexNormals();
  const edge = new THREE.BufferGeometry().setFromPoints(line);
  return {surface, base, section, edge};
}
