use crate::substring;
use crate::substring::get_lt_predicate;

unconstrained pub fn search<let N: u64, let M: u64>(
    haystack: [u8; N],
    needle: [u8; M],
    haystack_length: u64,
    needle_length: u64
) -> (bool, u64) {
    let mut found = false;
    let mut found_index: u64 = 0;
    for i in 0..haystack_length - needle_length {
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
    (found, found_index)
}

/**
 * @brief validate the body text contains zero-values for all indices >= byte_length
 * @note NOT NEEDED. Consider removing. Values beyond byte_length are not used in matching algorithm so no need to constrain them
 **/
fn validate_body<let BODYBYTES: u64, let BODYCHUNKS: u64>(data: [u8; BODYBYTES], length: u64, _: [Field; BODYCHUNKS]) {
    // we want a conditional assert for cases where i >= length
    // if i >= length we want to assert that data = 0
    let mut delta: Field = length as Field;
    for i in 0..BODYBYTES {
        let predicate = substring::lt(i, length);
        let predicate = get_lt_predicate(i, length);

        let lt_parameter = 2 * (predicate as Field) * delta - predicate as Field - delta;
        lt_parameter.assert_max_bit_size(14);
        delta = delta - 1;
        std::as_witness(delta);

        // assert that if predicate = 0 then byte = 0
        assert(data[i] as Field * predicate as Field == data[i] as Field);
    }
}
