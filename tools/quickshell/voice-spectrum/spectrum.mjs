// Fixed-gain speech spectrum. No peak tracking, AGC, or per-frame normalization.
export const sampleRate = 16000;
export const windowSize = 1024;
export const hopSize = 512;
export const bandCount = 19;
export const bandEdges = Array.from({length: bandCount + 1}, (_, i) => 100 * 64 ** (i / bandCount));
const floorDb = -64, ceilingDb = -28;
const window = Float64Array.from({length: windowSize}, (_, i) => 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (windowSize - 1)));
const windowPower = window.reduce((sum, value) => sum + value * value, 0);

export function spectrum(samples) {
  if (samples.length !== windowSize) throw new Error('Expected one complete audio window');
  const real = new Float64Array(windowSize), imag = new Float64Array(windowSize);
  // Remove DC so a microphone offset cannot light up the low bands.
  let mean = 0;
  for (const value of samples) mean += Number.isFinite(value) ? value / windowSize : 0;
  for (let i = 0; i < windowSize; i++)
    real[i] = ((Number.isFinite(samples[i]) ? samples[i] : 0) - mean) * window[i];

  for (let i = 1, j = 0; i < windowSize; i++) {
    let bit = windowSize >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) [real[i], real[j]] = [real[j], real[i]];
  }
  for (let size = 2; size <= windowSize; size *= 2) {
    const angle = -2 * Math.PI / size, stepReal = Math.cos(angle), stepImag = Math.sin(angle);
    for (let start = 0; start < windowSize; start += size) {
      let wr = 1, wi = 0;
      for (let j = 0; j < size / 2; j++) {
        const a = start + j, b = a + size / 2;
        const re = wr * real[b] - wi * imag[b], im = wr * imag[b] + wi * real[b];
        real[b] = real[a] - re; imag[b] = imag[a] - im;
        real[a] += re; imag[a] += im;
        [wr, wi] = [wr * stepReal - wi * stepImag, wr * stepImag + wi * stepReal];
      }
    }
  }
  return Array.from({length: bandCount}, (_, band) => {
    const first = Math.ceil(bandEdges[band] * windowSize / sampleRate);
    const end = Math.ceil(bandEdges[band + 1] * windowSize / sampleRate);
    let power = 0;
    for (let bin = first; bin < end; bin++) power += real[bin] ** 2 + imag[bin] ** 2;
    // One-sided, Hann-corrected RMS power; the dB range is fixed for every frame.
    const db = 10 * Math.log10(Math.max(1e-16, 2 * power / (windowSize * windowPower)));
    return Math.round(Math.max(0, Math.min(1, (db - floorDb) / (ceilingDb - floorDb))) * 10000) / 10000;
  });
}

// Pipe boundaries need not coincide with samples or FFT windows.
export class SpectrumStream {
  pending = Buffer.alloc(0);
  push(chunk, emit) {
    this.pending = Buffer.concat([this.pending, chunk]);
    while (this.pending.length >= windowSize * 4) {
      const samples = Float32Array.from({length: windowSize}, (_, i) => this.pending.readFloatLE(i * 4));
      emit(spectrum(samples));
      this.pending = this.pending.subarray(hopSize * 4);
    }
    // Do not keep a large pipe chunk alive through its small remaining slice.
    this.pending = Buffer.from(this.pending);
  }
}
