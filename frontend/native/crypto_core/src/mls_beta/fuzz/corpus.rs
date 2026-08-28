//! Deterministic PRNG, mutation operators, and the per-target corpus.
//!
//! The mutators are deliberately length-field aware. Every closed-beta frame
//! is a big-endian `u32` length followed by that many bytes, and every count
//! is a big-endian `u16`, so overwriting those positions with boundary values
//! is the mutation most likely to reach an unbounded reservation or a bad
//! slice. Random bit flips alone almost never produce a decodable frame.

use crate::mls_beta::MLS_MAX_IO_BYTES;

/// `xoshiro256++`, seeded through `SplitMix64`. Reproducing a campaign needs
/// only its seed, so no dependency is required for a stable stream.
pub(crate) struct Rng {
    state: [u64; 4],
}

impl Rng {
    pub(crate) fn new(seed: u64) -> Self {
        let mut mix = seed;
        let mut next = || {
            mix = mix.wrapping_add(0x9E37_79B9_7F4A_7C15);
            let mut value = mix;
            value = (value ^ (value >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
            value = (value ^ (value >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
            value ^ (value >> 31)
        };
        Self {
            state: [next(), next(), next(), next()],
        }
    }

    pub(crate) fn next_u64(&mut self) -> u64 {
        let result = self.state[0]
            .wrapping_add(self.state[3])
            .rotate_left(23)
            .wrapping_add(self.state[0]);
        let shifted = self.state[1] << 17;
        self.state[2] ^= self.state[0];
        self.state[3] ^= self.state[1];
        self.state[1] ^= self.state[2];
        self.state[0] ^= self.state[3];
        self.state[2] ^= shifted;
        self.state[3] = self.state[3].rotate_left(45);
        result
    }

    pub(crate) fn byte(&mut self) -> u8 {
        u8::try_from(self.next_u64() & 0xFF).unwrap_or_default()
    }

    /// A value below `bound`, or zero when `bound` is zero.
    pub(crate) fn below(&mut self, bound: usize) -> usize {
        let bound = u64::try_from(bound).unwrap_or(u64::MAX);
        if bound == 0 {
            return 0;
        }
        usize::try_from(self.next_u64() % bound).unwrap_or_default()
    }

    fn pick<T: Copy>(&mut self, values: &[T]) -> T {
        values[self.below(values.len())]
    }
}

/// Values a hostile encoder actually reaches for: the protocol bound, the
/// signed and unsigned edges, and the small counts every loop guard tests.
const INTERESTING_U32: [u32; 16] = [
    0,
    1,
    2,
    49,
    50,
    51,
    100,
    101,
    0x7F,
    0x80,
    0xFFFF,
    0x0001_0000,
    0x7FFF_FFFF,
    0x8000_0000,
    0xFFFF_FFFF,
    MLS_MAX_IO_BYTES_U32,
];

/// The accepted input bound as the `u32` a frame header carries.
const MLS_MAX_IO_BYTES_U32: u32 = 1_048_576;

const INTERESTING_BYTES: [u8; 8] = [0x00, 0x01, 0x02, 0x7F, 0x80, 0xFE, 0xFF, 0x20];

/// Lengths that sit exactly on a protocol boundary.
const BOUNDARY_LENGTHS: [usize; 8] = [
    0,
    1,
    8,
    4_096,
    16_384,
    MLS_MAX_IO_BYTES - 1,
    MLS_MAX_IO_BYTES,
    MLS_MAX_IO_BYTES + 1,
];

/// A per-target corpus: immutable seeds plus inputs that reached a new outcome.
pub(crate) struct Corpus {
    entries: Vec<Vec<u8>>,
    seeds: usize,
}

impl Corpus {
    /// Retaining more than this loses nothing: admission is keyed on a coarse
    /// outcome class, so the tail is dominated by near-duplicates.
    const CAPACITY: usize = 256;

    pub(crate) fn new(seeds: Vec<Vec<u8>>) -> Self {
        let mut entries = seeds;
        if entries.is_empty() {
            entries.push(Vec::new());
        }
        let seeds = entries.len();
        Self { entries, seeds }
    }

    /// Adds an input that reached an outcome no earlier input reached.
    pub(crate) fn retain(&mut self, input: Vec<u8>) {
        if self.entries.len() < Self::CAPACITY {
            self.entries.push(input);
        }
    }

    /// Produces the next input: one corpus entry with one to four mutations.
    pub(crate) fn next_input(&self, rng: &mut Rng) -> Vec<u8> {
        let mut input = self.entries[rng.below(self.entries.len())].clone();
        let rounds = 1 + rng.below(4);
        for _ in 0..rounds {
            self.mutate(rng, &mut input);
        }
        input.truncate(MLS_MAX_IO_BYTES + 1);
        input
    }

    /// Splice donors stay inside the seed range so real protocol structure
    /// keeps circulating instead of the pool degrading to noise.
    fn donor(&self, rng: &mut Rng) -> Vec<u8> {
        self.entries[rng.below(self.seeds)].clone()
    }

    #[allow(clippy::too_many_lines)] // One arm per mutation operator keeps the operator set readable.
    fn mutate(&self, rng: &mut Rng, input: &mut Vec<u8>) {
        match rng.below(11) {
            // Flip one bit.
            0 if !input.is_empty() => {
                let index = rng.below(input.len());
                input[index] ^= 1 << rng.below(8);
            }
            // Overwrite one byte with a boundary value.
            1 if !input.is_empty() => {
                let index = rng.below(input.len());
                input[index] = rng.pick(&INTERESTING_BYTES);
            }
            // Overwrite a big-endian `u32` length prefix.
            2 if input.len() >= 4 => {
                let index = rng.below(input.len() - 3);
                let value = rng.pick(&INTERESTING_U32).to_be_bytes();
                input[index..index + 4].copy_from_slice(&value);
            }
            // Overwrite a big-endian `u16` count.
            3 if input.len() >= 2 => {
                let index = rng.below(input.len() - 1);
                let value = u16::try_from(rng.pick(&INTERESTING_U32) & 0xFFFF)
                    .unwrap_or(u16::MAX)
                    .to_be_bytes();
                input[index..index + 2].copy_from_slice(&value);
            }
            // Erase a run.
            4 if !input.is_empty() => {
                let start = rng.below(input.len());
                let end = (start + 1 + rng.below(input.len() - start)).min(input.len());
                input.drain(start..end);
            }
            // Duplicate a run in place.
            5 if !input.is_empty() => {
                let start = rng.below(input.len());
                let end = (start + 1 + rng.below(input.len() - start)).min(input.len());
                let run = input[start..end].to_vec();
                let at = rng.below(input.len() + 1);
                input.splice(at..at, run);
            }
            // Insert random bytes.
            6 => {
                let count = 1 + rng.below(64);
                let run: Vec<u8> = (0..count).map(|_| rng.byte()).collect();
                let at = rng.below(input.len() + 1);
                input.splice(at..at, run);
            }
            // Splice in a run taken from a seed.
            7 => {
                let donor = self.donor(rng);
                if !donor.is_empty() {
                    let start = rng.below(donor.len());
                    let end = (start + 1 + rng.below(donor.len() - start)).min(donor.len());
                    let at = rng.below(input.len() + 1);
                    input.splice(at..at, donor[start..end].iter().copied());
                }
            }
            // Truncate.
            8 if !input.is_empty() => {
                let length = rng.below(input.len());
                input.truncate(length);
            }
            // Resize onto an exact protocol boundary, including one byte past
            // the accepted maximum.
            9 => {
                let length = rng.pick(&BOUNDARY_LENGTHS);
                let filler = rng.byte();
                input.resize(length, filler);
            }
            // Swap two runs.
            _ if input.len() >= 4 => {
                let half = input.len() / 2;
                let width = 1 + rng.below(half);
                let left = rng.below(half);
                let right = half + rng.below(input.len() - half - width + 1);
                for offset in 0..width {
                    input.swap(left + offset, right + offset);
                }
            }
            _ => input.push(rng.byte()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{Corpus, MLS_MAX_IO_BYTES, MLS_MAX_IO_BYTES_U32, Rng};

    #[test]
    fn the_accepted_bound_and_its_frame_encoding_agree() {
        assert_eq!(u64::from(MLS_MAX_IO_BYTES_U32), MLS_MAX_IO_BYTES as u64);
    }

    #[test]
    fn the_stream_is_reproducible_from_its_seed() {
        let mut first = Rng::new(7);
        let mut second = Rng::new(7);
        let mut third = Rng::new(8);
        let first: Vec<u64> = (0..16).map(|_| first.next_u64()).collect();
        let second: Vec<u64> = (0..16).map(|_| second.next_u64()).collect();
        let third: Vec<u64> = (0..16).map(|_| third.next_u64()).collect();
        assert_eq!(first, second);
        assert_ne!(first, third);
    }

    #[test]
    fn mutation_stays_within_one_byte_of_the_accepted_input_bound() {
        let corpus = Corpus::new(vec![vec![0x11; 64], vec![0x22; 4_096]]);
        let mut rng = Rng::new(0xFEED);
        for _ in 0..2_000 {
            assert!(corpus.next_input(&mut rng).len() <= MLS_MAX_IO_BYTES + 1);
        }
    }

    #[test]
    fn mutation_reaches_the_empty_and_over_bound_lengths() {
        let corpus = Corpus::new(vec![vec![0x33; 128]]);
        let mut rng = Rng::new(0x00C0_FFEE);
        let mut saw_empty = false;
        let mut saw_over_bound = false;
        for _ in 0..5_000 {
            let input = corpus.next_input(&mut rng);
            saw_empty |= input.is_empty();
            saw_over_bound |= input.len() > MLS_MAX_IO_BYTES;
        }
        assert!(saw_empty, "the mutator must produce an empty input");
        assert!(
            saw_over_bound,
            "the mutator must exceed the accepted input bound"
        );
    }
}
