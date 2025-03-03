pub unconstrained fn search<let N: u32>(
    haystack: [u8; N],
    needle: [u8],
    haystack_length: u32,
    needle_length: u32,
) -> u32 {
    assert(needle_length > 0, "needle length of size 0 not supported");
    assert(haystack_length > 0, "haystack length of size 0 not supported");
    let mut found = false;
    let mut found_index: u32 = 0;
    for i in 0..haystack_length - needle_length + 1 {
        if (found == true) {
            break;
        }
        for j in 0..needle_length {
            if haystack[i + j] != needle[j] {
                break;
            } else if (j == needle_length - 1) {
                found = true;
            }
            if (found == true) {
                found_index = i;
                break;
            }
        }
    }
    assert(found == true, "utils::search could not find needle in haystack");
    found_index
}

unconstrained fn __conditional_select(lhs: u8, rhs: u8, predicate: bool) -> u8 {
    if (predicate) {
        lhs
    } else {
        rhs
    }
}

pub fn conditional_select<T>(lhs: u8, rhs: u8, predicate: bool) -> u8 {
    // Safety: This is all just a very verbose `if (predicate) { lhs } else { rhs }`
    // formulated as `rhs + (lhs - rhs) * predicate`
    unsafe {
        let result = __conditional_select(lhs, rhs, predicate);
        let result_f = result as Field;
        let lhs_f = lhs as Field;
        let rhs_f = rhs as Field;

        let diff = lhs_f - rhs_f;
        std::as_witness(diff);
        assert_eq((predicate as Field) * diff + rhs_f, result_f);
        result
    }
}

pub unconstrained fn get_lt_predicate_f(x: Field, y: Field) -> bool {
    let a = x as u32;
    let b = y as u32;
    a < b
}

pub fn lt_f(x: Field, y: Field) -> bool {
    // Safety: As `x` and `y` are known to be valid `u32`s, this function reimplements the
    // compiler's internal implementation of `lt`
    unsafe {
        let predicate = get_lt_predicate_f(x, y);
        let delta = y as Field - x as Field;
        let lt_parameter = 2 * (predicate as Field) * delta - predicate as Field - delta;
        lt_parameter.assert_max_bit_size::<32>();

        predicate
    }
}

pub struct DebugRandomEngine {
    pub seed: Field,
}

impl DebugRandomEngine {
    unconstrained fn get_random_32_bytes(&mut self) -> [u8; 32] {
        self.seed += 1;
        let input: [u8; 32] = self.seed.to_be_bytes();
        let hash: [u8; 32] = std::hash::blake3(input);
        hash
    }
    unconstrained fn get_random_field(&mut self) -> Field {
        let hash = self.get_random_32_bytes();
        let mut result: Field = 0;
        for i in 0..32 {
            result *= 256;
            result += hash[i] as Field;
        }
        result
    }

    pub unconstrained fn get_random_bytes<let NBytes: u32>(&mut self) -> [u8; NBytes] {
        let num_chunks = (NBytes / 32) + ((NBytes % 32) != 0) as u32;

        let mut result: [u8; NBytes] = [0; NBytes];
        for i in 0..num_chunks - 1 {
            let bytes = self.get_random_32_bytes();
            for j in 0..32 {
                result[i * 32 + j] = bytes[j];
            }
        }

        let bytes = self.get_random_32_bytes();
        for j in 0..(NBytes - (num_chunks - 1) * 32) {
            result[(num_chunks - 1) * 32 + j] = bytes[j];
        }
        result
    }
}
