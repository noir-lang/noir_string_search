struct SubString<let MaxBytes: u64> {
    body: [u8; MaxBytes],
    byte_length: u64,
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

fn conditional_select<T>(lhs: u8, rhs: u8, predicate: bool) -> u8 {
    let result = __conditional_select(lhs, rhs, predicate);
    let result_f = result as Field;
    let lhs_f = lhs as Field;
    let rhs_f = rhs as Field;

    let diff = lhs_f - rhs_f;
    std::as_witness(diff);
    assert((predicate as Field) * (diff) + rhs_f == result_f);
    result
}

unconstrained fn get_lt_predicate(x: u64, y: u64) -> bool {
    x < y
}

unconstrained fn get_lt_predicate_f(x: Field, y: Field) -> bool {
    let a = x as u64;
    let b = y as u64;
    let r = a < b;
    r
}

pub fn lt(x: u64, y: u64) -> bool {
    let predicate = get_lt_predicate(x, y);
    let delta = y as Field - x as Field;
    let lt_parameter = 2 * (predicate as Field) * delta - predicate as Field - delta;
    lt_parameter.assert_max_bit_size(14);

    predicate
}

pub fn lt_f(x: Field, y: Field) -> bool {
    let predicate = get_lt_predicate_f(x, y);
    let delta = y as Field - x as Field;
    let lt_parameter = 2 * (predicate as Field) * delta - predicate as Field - delta;
    lt_parameter.assert_max_bit_size(14);

    predicate
}

// need to convert SubString into Chunks

// 3209 -> 3213 = 4
impl<let MaxBytes: u64> SubString<MaxBytes> {
    fn new<let InputBytes: u64>(input: [u8; InputBytes], input_length: u64) -> Self {
        assert(InputBytes <= MaxBytes);
        assert(input_length <= InputBytes);
        let mut body: [u8; MaxBytes] = [0; MaxBytes];
        for i in 0..InputBytes {
            body[i] = input[i];
        }
        SubString { body, byte_length: input_length }
    }

    fn concat<let OtherBytes: u64>(self, other: SubString<OtherBytes>) -> Self {
        assert(
            OtherBytes <= MaxBytes, "SubString::concat. SubString being concatted has larger max length. Try swapping params around and call prepend"
        );
        assert(
            self.byte_length + other.byte_length <= MaxBytes, "SubString::concat, concatenated string exceeds MaxBytes"
        );
        let mut body = self.body;
        let offset: u64 = self.byte_length;
        for i in 0..OtherBytes {
            let predicate = lt(i, other.byte_length); // 3.36 gates

            let lhs_index = predicate as Field * (i as Field + offset as Field); // ensure array index does not overflow
            let lhs = body[lhs_index];
            let rhs = other.body[i];
            // an if statement costs 6.5 gates, this method costs 3.25 gates
            let byte: u8 = conditional_select(lhs, rhs, predicate);
            body[i + offset] = byte;
        }
        SubString { body, byte_length: self.byte_length + other.byte_length }
    }
}

