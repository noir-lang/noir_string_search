unconstrained pub fn search<let N: u32>(
    haystack: [u8; N],
    needle: [u8],
    haystack_length: u32,
    needle_length: u32
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

/**
 * @brief validate the body text contains zero-values for all indices >= byte_length
 * @note NOT NEEDED. Consider removing. Values beyond byte_length are not used in matching algorithm so no need to constrain them
 **/
fn validate_body<let BODYBYTES: u32, let BODYCHUNKS: u32>(
    data: [u8; BODYBYTES],
    length: u32,
    _: [Field; BODYCHUNKS]
) {
    // we want a conditional assert for cases where i >= length
    // if i >= length we want to assert that data = 0
    let mut delta: Field = length as Field;
    for i in 0..BODYBYTES {
        let predicate = lt_f(i as Field, length as Field);
        let predicate = get_lt_predicate_f(i as Field, length as Field);

        let lt_parameter = 2 * (predicate as Field) * delta - predicate as Field - delta;
        lt_parameter.assert_max_bit_size(32);
        delta = delta - 1;
        std::as_witness(delta);

        // assert that if predicate = 0 then byte = 0
        assert(data[i] as Field * predicate as Field == data[i] as Field);
    }
}

unconstrained fn __conditional_select(lhs: u8, rhs: u8, predicate: bool) -> u8 {
    let mut result: u8 = 0;
    if (predicate) {
        result = lhs;
    } else {
        result = rhs;
    }
    result
}

pub fn conditional_select<T>(lhs: u8, rhs: u8, predicate: bool) -> u8 {
    let result = __conditional_select(lhs, rhs, predicate);
    let result_f = result as Field;
    let lhs_f = lhs as Field;
    let rhs_f = rhs as Field;

    let diff = lhs_f - rhs_f;
    std::as_witness(diff);
    assert((predicate as Field) * (diff) + rhs_f == result_f);
    result
}

unconstrained pub fn get_lt_predicate_f(x: Field, y: Field) -> bool {
    let a = x as u32;
    let b = y as u32;
    let r = a < b;
    r
}

pub fn lt_f(x: Field, y: Field) -> bool {
    let predicate = get_lt_predicate_f(x, y);
    let delta = y as Field - x as Field;
    let lt_parameter = 2 * (predicate as Field) * delta - predicate as Field - delta;
    lt_parameter.assert_max_bit_size(32);

    predicate
}

struct DebugRandomEngine {
    seed: Field,
}

impl DebugRandomEngine {
    unconstrained fn get_random_32_bytes(&mut self) -> [u8; 32] {
        self.seed += 1;
        let input: [u8; 32] = self.seed.to_be_bytes();
        let hash: [u8; 32] = dep::std::hash::sha256(input);
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

    unconstrained fn get_random_bytes<let NBytes: u32>(&mut self) -> [u8; NBytes] {
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
