// fn main(x: Field, y: pub Field) {
//     assert(x != y);
// }

// #[test]
// fn test_main() {
//     main(1, 2);
//     // Uncomment to make test fail
//     // main(1, 1);
// }
mod utils;
mod substring;

global BODYCHUNKS = 34;

global MAXSUBSTRINGBYTES = 93;
global MAXSUBSTRINGCHUNKS = 3;

use substring::SubString;

struct StringBody<let BODYBYTES: u64, let BODYCHUNKS: u64> {
    body: [u8; BODYBYTES],
    chunks: [Field; BODYCHUNKS],
    byte_length: u64
}

struct StringTarget {
    body: [u8; MAXSUBSTRINGBYTES],
    chunks: [Field; MAXSUBSTRINGCHUNKS],
    byte_length: u64
}

unconstrained fn get_lt_predicate(x: u64, y: u64) -> bool {
    x < y
}

impl<let BODYBYTES: u64, let BODYCHUNKS: u64> StringBody<BODYBYTES, BODYCHUNKS> {

    fn compute_chunks(body: [u8; BODYBYTES]) -> [Field; BODYCHUNKS] {
        let mut chunks: [Field; BODYCHUNKS] = [0; BODYCHUNKS];
        for i in 0..BODYCHUNKS {
            let mut limb: Field = 0;
            for j in 0..31 {
                limb *= 256;
                limb += body[i * 31 + j] as Field;
            }
            chunks[i] = limb;
            std::as_witness(chunks[i]);
        }
        chunks
    }

    fn new<let SubStringBytes: u64>(haystack: SubString<SubStringBytes>) -> Self {
        assert(SubStringBytes <= BODYBYTES, "StringBody::new input max length too large!");
        let mut body: [u8; BODYBYTES] = [0; BODYBYTES];
        for i in 0..SubStringBytes {
            body[i] = haystack.body[i];
        }
        StringBody { body, chunks: StringBody::compute_chunks(body), byte_length: haystack.byte_length }
    }

    fn from_array(data: [u8; BODYBYTES], length: u64) -> Self {
        assert(length <= BODYBYTES);
        StringBody { body: data, chunks: StringBody::compute_chunks(data), byte_length: length }
    }

    fn convert_chunk_to_bytes(self, chunk_idx: u64) -> [u8; 31] {
        let chunk = self.chunks[chunk_idx];
        chunk.to_be_bytes(31).as_array()
    }

    // substring has a maximum number of bytes
    // which requires a maximum number of chunks
    // when aligning the substring chunks with the body chunks, we may need 1 additional chunk
    // todo hmm
    fn substring_match<let SSBYTES: u64, let PADDED_SUBSTRING_BYTES: u64, let PADDED_SUBSTRING_CHUNKS: u64>(
        self,
        substring: SubString<SSBYTES/*, PADDED_SUBSTRING_BYTES*/>,
        _: [Field; PADDED_SUBSTRING_CHUNKS],
        __: u64
    ) -> bool {
        // use unconstrained function to determine:
        // a: is the substring present in the body text
        // b: the position of the first match in the body text 
        let (found, position): (bool, u64) = utils::search(
            self.body,
            substring.body,
            self.byte_length,
            substring.byte_length
        );
        assert(found == true, "substring not present in main text!");
        assert(
            position + substring.byte_length <= self.byte_length, "substring not present in main text (match found if a padding text included. is main text correctly formatted?)"
        );
        let substring_length = substring.byte_length;

        let chunk_index: u64 = position / 31;
        let chunk_offset: u64 = position % 31;

        let num_bytes_in_first_chunk = 31 - chunk_offset;
        let mut num_remaining_bytes: u64 = 0;
        if (substring_length >= num_bytes_in_first_chunk) {
            num_remaining_bytes = (substring_length - num_bytes_in_first_chunk);
        }
        let num_full_chunks = num_remaining_bytes / 31;

        let mut starting_substring_byte_index_of_final_chunk: u64 = 0;

        if (substring_length >= num_bytes_in_first_chunk) {
            starting_substring_byte_index_of_final_chunk = num_full_chunks * 31 + num_bytes_in_first_chunk;
        } else {
            starting_substring_byte_index_of_final_chunk = 0;
        }
        let body_chunk_index_of_final_chunk = num_full_chunks + chunk_index + 1; // hmm should this be +1?

        // To minimize the number of comparisons between the haystack bytes and the needle bytes,
        // we pack both the haystack bytes and needle bytes into 31-byte Field "chunks" and compare chunks.
        // To do this correctly, we need to align the needle chunks with the haystack chunks
        /*
            e.g. consider a toy example where we pack 3 bytes into a chunk
            haystack: [VWXZYABCDEQRSTU]
            needle: [ABCDE]

            when constructing needle chunks, we need to align according to where the needle is located in the haystack
            haystack chunks:   [VWX] [ZYA] [BCD] [EQR] [STU]
                                      _..   ...   .__
            processed needle chunks: [ZYA] [BCD] [EQR]

            a "_" symbole means that a chunk byte has been sourced from the haystack bytes,
            a "." symbol means a byte is sourced from the needle bytes

            Both the initial and final chunks of the processed needle are "composite" constructions.
            If chunk byte index < `position` or is > `position + needle length", byte is sourced from haystack, otherwise byte is sourced from needle

            The way we execute this in code is to define an "initial" needle chunk and a "final" needle chunk.
            Num needle bytes in initial chunk = position % 31
            Num needle bytes in final chunk = (needle_length - (position % 31)) % 31

            If needle_length < 31 then the "initial" and "final" chunks
            are actually the *same* chunk and we must perform a merge operation
            (see later in algo for comments)
        */
        // GET INITIAL CHUNK
        // instead of directly reading haystack bytes, we derive the bytes from the haystack chunks.
        // This way we don't have to instantiate the haystack bytes as a ROM table, which would cost 2 * haystack.length gates
        let body_bytes: [u8; 31] = self.chunks[chunk_index].to_be_bytes(31).as_array();
        let offset_to_first_needle_byte_in_chunk: Field = chunk_offset as Field;
        // When defining the initial chunk bytes, we can represent as Field elements as we are deriving values from known bytes.
        // This saves us a few gates
        let mut initial_chunk: [Field; 31] = [0; 31];
        let mut final_chunk: [Field; 31] = [0; 31];
        for i in 0..31 {
            // if i < offset_to_first_needle_byte_in_chunk, we read from the haystack
            // otherwise we read from the needle
            // n.b. this can be done with an if statement, but the following code produces fewer constraints
            let idx: Field = i as Field;
            let predicate: Field = substring::lt_f(i as Field, offset_to_first_needle_byte_in_chunk) as Field;
            let lhs: Field = body_bytes[i] as Field;
            // if i < offset_to_first_needle_byte_in_chunk then `idx - offset_to_first_needle_byte_in_chunk` is negative
            // to ensure we access array correctly we need to set the lookup index to 0 if predicate = 0
            let substring_idx = (1 - predicate) * (idx - offset_to_first_needle_byte_in_chunk);
            let rhs: Field = substring.body[substring_idx] as Field;
            let byte: Field = predicate * (lhs - rhs) + rhs;
            initial_chunk[i] = byte;
        }

        // GET FINAL CHUNK
        let mut new_initial_chunk: [Field; 31] = [0; 31];
        let merge_chunks = (num_bytes_in_first_chunk > substring_length);

        let mut chunk_index_of_final_haystack_chunk_with_matching_needle_bytes = 0;

        // this nasty!
        if (substring_length >= num_bytes_in_first_chunk) {
            chunk_index_of_final_haystack_chunk_with_matching_needle_bytes = num_full_chunks + chunk_index + 1;
        } else {
            chunk_index_of_final_haystack_chunk_with_matching_needle_bytes = chunk_index;
        }

        let final_haystack_chunk = self.chunks[chunk_index_of_final_haystack_chunk_with_matching_needle_bytes];
        let body_bytes: [u8; 31] = final_haystack_chunk.to_be_bytes(31).as_array();
        // let body_bytes = self.convert_chunk_to_bytes(chunk_index_of_final_haystack_chunk_with_matching_needle_bytes);
        println(f"body bytes = {body_bytes}");
        for i in 0..31 {
            let lhs_index = starting_substring_byte_index_of_final_chunk as Field + i as Field;
            let predicate = substring::lt_f(lhs_index, substring_length as Field);
            let lhs: Field = substring.body[lhs_index] as Field;
            let rhs: Field = body_bytes[i] as Field;
            let byte: Field = predicate as Field * (lhs - rhs) + rhs;
            final_chunk[i] = byte;

            let lhs_index = predicate as Field * (lhs_index);

            let lhs = initial_chunk[lhs_index];
            let rhs = body_bytes[i] as Field;
            let byte: Field = lhs as Field * predicate as Field + rhs as Field * (1 - predicate as Field);
            //  initial_chunk[i] = 
            std::as_witness(byte);
            let val = (byte as Field * merge_chunks as Field)
                + initial_chunk[(i as Field) as Field * (1 - merge_chunks as Field)];
            std::as_witness(val);
            new_initial_chunk[i] = val;
        }
        println(f"initial chunk = {initial_chunk}");
        println(f"new initial chunk = {new_initial_chunk}");
        let mut initial_chunk_field: Field = 0;
        for i in 0..31 {
            initial_chunk_field *= 256;
            initial_chunk_field += new_initial_chunk[i];
        }
        std::as_witness(initial_chunk_field);
        let mut final_chunk_field: Field = 0;
        for i in 0..31 {
            final_chunk_field *= 256;
            final_chunk_field += final_chunk[i];
        }
        final_chunk_field = initial_chunk_field * merge_chunks as Field + (final_chunk_field * (1 - merge_chunks as Field));
        let lhs = initial_chunk_field;
        let rhs = self.chunks[chunk_index];
        assert(lhs == rhs);

        println(f"merge chunks = {merge_chunks}");
        println(f"final_chunk_field = {final_chunk_field}");
        let lhs = final_chunk_field;
        let rhs = final_haystack_chunk;
        assert(lhs == rhs);

        // // constituting body chunks is hard because we need to read from unknown index = 2 gates = womp
        let mut substring_chunks: [Field; PADDED_SUBSTRING_CHUNKS] = [0; PADDED_SUBSTRING_CHUNKS];

        for i in 0..PADDED_SUBSTRING_CHUNKS {
            let mut slice: Field = 0;
            for j in 0..31 {
                slice *= 256;
                let mut byte = substring.body[num_bytes_in_first_chunk + (i * 31) + j];
                slice += byte as Field;
            }
            substring_chunks[i] = slice;
        }

        let body_chunk_offset = chunk_index + 1;
        for i in 0..PADDED_SUBSTRING_CHUNKS {
            let mut lhs = substring_chunks[i];

            let rhs = self.chunks[i + body_chunk_offset];

            let predicate = i < num_full_chunks;
            lhs = lhs * (predicate as Field) + rhs * (1 - predicate as Field);
            assert(lhs == rhs);
        }
        true
    }
}

#[test]
fn test() {
    let mut body_text: [u8; 124] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
        40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
        60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
        80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99,
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
        110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
        120, 121, 122, 123
    ];
    // let mut body_text: [u8; 124] = [0; 124];
    // for i in 0..124 {
    //     body_text[i] = body_text_e[123 - i];
    // }
    // let substring_text: [u8; 62] = [
    //     10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    //     20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
    //     30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
    //     40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
    //     50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
    //     0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    //     0, 0
    // ];
    let substring_text: [u8; 122] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
        40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
        60, 61,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ];
    // let res2 = dep::std::hash::sha256_var(body_text, 50);
    // println(f"{res2}");
    let mut Body: StringBody<124, 4> = StringBody::from_array(body_text, 124);
    let mut substring: SubString<122/*,2*/> = SubString::new(substring_text, 62);
    // StringBody { body: substring_text, chunks: [0; 2], byte_length: 62 };
    let r = Body.substring_match(substring, [0; 2], 0);
    assert(r == true);
}

#[test]
fn test_small_needle() {
    let mut body_text: [u8; 124] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
        40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
        60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
        80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99,
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
        110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
        120, 121, 122, 123
    ];
    let substring_text: [u8; 122] = [
        2, 3, 4, 5, 6, 7, 8, 9,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ];
    let mut Body: StringBody<124, 4> = StringBody::from_array(body_text, 124);
    let mut substring: SubString<122/*,2*/> = SubString::new(substring_text, 8);
    let r = Body.substring_match(substring, [0; 2], 0);
    assert(r == true);
}

#[test]
fn test_needle_aligned_on_byte_boundary() {
    let mut body_text: [u8; 124] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
        40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
        60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
        80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99,
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
        110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
        120, 121, 122, 123
    ];
    let substring_text: [u8; 122] = [
        2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ];
    let mut Body: StringBody<124, 4> = StringBody::from_array(body_text, 124);
    let mut substring: SubString<122/*,2*/> = SubString::new(substring_text, 29);
    let r = Body.substring_match(substring, [0; 2], 0);
    assert(r == true);
}
// 7042 = 1, 1
// 7190 = 2, 1
// 7339 = 3, 1
// 7708 = 3, 2

// 7708 -> 11724 => 30, 2
// 4016 diff for 27 chunks = 837 bytes = 4.8 per byte or 130 per chunk. seems bad?
global BODYLEN = 1054;
global BODYCHUNK = 34;
global SUBSTRINGLEN = 279;
global SUBSTRINGCHUNK = 9;
// 841 - 692 = 149 argh
// 4098 -> 4137 = 39 gates. 31 * 1.25 for u8 bytes = 39 
unconstrained fn get_test_stringbody(
    body_text: [u8; BODYLEN],
    substring_text: [u8; SUBSTRINGLEN],
    _: u64,
    body_length: u64,
    substring_length: u64
) -> (StringBody<BODYLEN, BODYCHUNK>, StringBody<SUBSTRINGLEN,SUBSTRINGCHUNK>) {
    let mut Body: StringBody<BODYLEN, BODYCHUNK> = StringBody::from_array(body_text, body_length);

    let mut SubString: StringBody<SUBSTRINGLEN,SUBSTRINGCHUNK> = StringBody { body: substring_text, chunks: [0; SUBSTRINGCHUNK], byte_length: substring_length };
    (Body, SubString)
}

// 3215 -> 3230 = 15 gates per it
global OtherBytes = 20;
global MaxBytes = 32;

// fn main(body: [u8; MaxBytes], other_body: [u8; MaxBytes], byte_length: u64, other_byte_length: u64) {
//     let A : substring::SubString<MaxBytes> = substring::SubString::new(body, byte_length);
//     let B : substring::SubString<OtherBytes> = substring::SubString::new(other_body, other_byte_length);

//     let C = A.concat(B);
//     println(f"{C}");
//     // assert(
//     //     OtherBytes <= MaxBytes, "SubString::concat. SubString being concatted has larger max length. Try swapping params around and call prepend"
//     // );
//     // assert(
//     //     byte_length + other_byte_length <= MaxBytes, "SubString::concat, concatenated string exceeds MaxBytes"
//     // );
//     // //  let mut body = body;
//     // let offset: u64 = byte_length;
//     // for i in 0..OtherBytes {
//     //     let predicate = i < other_byte_length; // TODO optimize
//     //     let lhs = body[i as Field + offset as Field];
//     //     let rhs = other_body[i];
//     //     println(f"{predicate}");
//     //     println(f"{lhs}");
//     //     println(f"{rhs}");
//     //     // 1 it = 2989
//     //     // 2 it = 3004 = 15 gates
//     //     // 1 it = 2982
//     //     // 2 it = 2991 = 9 gates => 6 gates
//     //     //    let byte: Field = (lhs as Field - rhs as Field) * predicate as Field + rhs as Field;
//     //     //    println(f"{byte}");
//     //     //    let byte: u8 = conditional_select(lhs, rhs, predicate);
//     //     // (lhs - rhs) * predicate + rhs = 2 gates
//     //     let mut byte: u8 = 0;
//     //     if (predicate) {
//     //         byte = lhs;
//     //     } else {
//     //         byte = rhs;
//     //     }
//     //     println(f"{byte}");
//     //     // 13 / 2 = 6.5
//     //     //   body[i + offset] = byte;
//     // }
//     //   println(f"{body}");
//     //  SubString { body, byte_length: self.byte_length + other_byte_length }
// }

fn main(
    body_text: [u8; BODYLEN],
    substring_text: [u8; SUBSTRINGLEN],
    position: u64,
    body_length: u64,
    substring_length: u64
) {
    (position as Field).assert_max_bit_size(14);
    //   for i in 0..1 {
    // for i in 0..124 {
    //     body_text[i] = body_text[i] + 1;
    // }
    // for i in 0..900 {
    //     substring_text[i] = substring_text[i] + 1;
    // }
    //  let mut Body = StringBody::validate_body(body_text, body_length, [0; 40]);
    let mut Body: StringBody<BODYLEN, BODYCHUNK> = StringBody::from_array(body_text, body_length);

    let mut SubString: SubString<SUBSTRINGLEN> = SubString::new(substring_text, substring_length);
    //vStringBody { body: substring_text, chunks: [0; SUBSTRINGCHUNK], byte_length: substring_length };

    assert(Body.chunks[position as Field] != 0); // this adds ~600 gates because we instantiate as ROM array
    // let (Body, SubString) = get_test_stringbody(
    //     body_text,
    //     substring_text,
    //     position,
    //     body_length,
    //     substring_length
    // );
    let r = Body.substring_match(SubString, [0; SUBSTRINGCHUNK], position);
    println(f"{SubString}");
    println(f"{r}");
}
// 4574 to 6578 = 2002
// 6963 to 15412 = 8449 for 1860 bytes , searching 610

// 110,55 to 11,455 = 400 for 31 bytes = 13 gates per byte. meh
#[test]
unconstrained fn test_partial_match() {
    let mut foo: [u8; 10] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    let mut bar: [u8; 3] = [4, 5, 6];
    let mut Engine = DebugRandomEngine { seed: 0 };
    let mut foo: [u8; 8192] = Engine.get_random_bytes();
    let mut bar: [u8; 512] = Engine.get_random_bytes();
    println(f"{foo}");
    println(f"{bar}");
    let (res, _) = utils::search(foo, bar, 10, 3);

    assert(res == false);
}

struct DebugRandomEngine {
    seed: Field,
}

impl DebugRandomEngine {
    unconstrained fn get_random_32_bytes(&mut self) -> [u8; 32] {
        self.seed += 1;
        let input: [u8; 32] = self.seed.to_be_bytes(32).as_array();
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

    unconstrained fn get_random_bytes<let NBytes: u64>(&mut self) -> [u8; NBytes] {
        let num_chunks = (NBytes / 32) + ((NBytes % 32) != 0) as u64;

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

