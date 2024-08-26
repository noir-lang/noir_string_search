# noir_string_search

A noir library that can be used to prove that a given "needle" substring is present within a larger "haystack" string.

Features:

- Both the needle and haystack string can have variable runtime lengths (up to a defined maximum)
- Efficient implementation ~2 gates per haystack byte, ~5 gates per needle byte
- Both needle and haystack strings can be dynamically constructed in-circuit if required

## Dependencies

- Noir ≥v0.32.0
- Barretenberg ≥v0.46.1

Refer to [Noir's docs](https://noir-lang.org/docs/getting_started/installation/) and [Barretenberg's docs](https://github.com/AztecProtocol/aztec-packages/blob/master/barretenberg/cpp/src/barretenberg/bb/readme.md#installation) for installation steps.

## Installation

In your _Nargo.toml_ file, add the version of this library you would like to install under dependency:

```
[dependencies]
noir_string_search = { tag = "v0.1", git = "https://github.com/noir-lang/noir_string_search" }
```

## Usage

Verify whether and where a substring is present withing another (larger) string:

```rust
let haystack_text = "the quick brown fox jumped over the lazy dog".as_bytes();
let needle_text = " the lazy dog".as_bytes();

let haystack: StringBody64 = StringBody::new(haystack_text, haystack_text.len());
let needle: SubString32 = SubString::new(needle_text, needle_text.len());

let (result, match_position): (bool, u32) = haystack.substring_match(needle);
```

Both substring and larger string require a type with hardcoded maximum length. See type definitions below for the available lengths. 

Find this code snippet in `/example` and steps for proof generation and verification explained below.

### Dynamic needle construction

An example of dynamically creating the needle from 2 substrings:

```rust
fn validate_account(padded_email_text: [u8; 8192], padded_username: [u8; 100], username_length: u32) {

    let needle_text_init = "account recovery for".as_bytes();

    let needle_start: SubString32 = SubString::new(needle_text_init, needle_text_init.len());
    let needle_end: SubString128 = SubString::new(padded_username, username_length);
    // use concat_into because SubString128 > SubString32
    let needle = needle_start.concat_into(needle_end);

    let haystack: StringBody8192 = StringBody::new(padded_email_text, 8192);
    let (result, match_position): (bool, u32) = haystack.substring_match(needle);
}
```
See all methods available in the next section.

## Types & methods

`StringBody` represents the "haystack" array, where you will check a "needle" (substring) is present. It is a byte array of up to `MaxBytes`. 

The content will be packed into 31-byte chunks and padded with zero. `MaxPaddedBytes`represents the max number of bytes after padding and `PaddedChunks` the number of 31-bytes chunks that are needed. `byte_length` is the length of the initial byte array (without padding). 

```rust
struct StringBody<let MaxPaddedBytes: u32, let PaddedChunks: u32, let MaxBytes: u32> {
    body: [u8; MaxPaddedBytes],
    chunks: [Field; PaddedChunks],
    byte_length: u32
}
```
Example: `type StringBody256 = StringBody<279, 9, 256>;`. 

`SubString` is the struct for the "needle", or the substring that is checked to be in the `StringBody`. It is a byte array of length max `MaxBytes`. 

Also this type is packed into 31-byte chunks and zero-padded to the nearest multiple of 31. `MaxPaddedBytes` is the max number of bytes after padding and `PaddedChunksMinusOne` is the number of chunks needed minus 1. `byte_length` represents the actual length of the substring as a byte array (without padding).

```rust
struct SubString<let MaxPaddedBytes: u32, let PaddedChunksMinusOne: u32, let MaxBytes: u32> {
    body: [u8; MaxPaddedBytes],
    byte_length: u32
}
```

Example: `type SubString32 = SubString<62, 1, 32>;`. 


Multiple type definitions represent different hardcoded maximum lengths for the needle/haystack:


```
Haystack types ranging from 32 max bytes to 16,384 max bytes
StringBody32
StringBody64
StringBody128
StringBody256
StringBody512
StringBody1024
StringBody2048
StringBody4096
StringBody8192
StringBody16384
```

```
Needle types ranging from 32 bytes to 1,024 max bytes
SubString32
SubString64
SubString128
SubString256
SubString512
SubString1024
```

### Methods

#### `StringBody`

- `new(input, input_length)`, create a `StringBody` object from the byte array (that represents the string) and the length of the byte array
- `substring_match(substring)`, validates that the given needle exists in the haystack. 


#### `SubString`

- `new(input, input_length)`, create a `SubString` object from the byte array (that represents the string) and the length of the byte array
- `concat(self, other)`, concatenate two substrings together where `other.MaxBytes <= self.MaxBytes`
- `concat_into(self, other)`, concatenate two substrings together where `other.MaxBytes > self.MaxBytes`
- `len`, actual length of the bytes representing the substring
- `get(self, idx)`, returns byte for given index
- `get_body`, returns the inner array that the SubString contains

## Costs

Matching a SubString128 with a StringBody1024 costs 6,630 gates (as of noir 0.32.0 and bb 0.46.1)

Gate breakdown:

- 2,740 gates: constructing a 14-bit range table
- 1,280 gates: constructing a 1,024 size `u8` array
- 160 gates: constructing a 128 size `u8` array
- 2,444 gates: string matching algorithm

Some rough measurements:

| Haystack Bytes | Needle Bytes | Total Cost | Cost minus range table and byte array init costs |
| -------------- | ------------ | ---------- | ------------------------------------------------ |
| 1,024          | 128          | 6,630      | 2,444                                            |
| 1,024          | 256          | 7,633      | 3,293                                            |
| 2,048          | 128          | 8,471      | 3,011                                            |
| 2,048          | 256          | 9,474      | 3,854                                            |

Extrapolating from this table for some very rough estimates: costs for `substring_match` (excluding range table and byte array init costs) are ~6.5 gates per needle byte, ~0.5 gates per haystack byte and a ~1,100 gate constant cost.

## Example 

Find the example with above usage code in `/example`. 

Run the test:

```bash
nargo test
```

### Prove it

Run `nargo check` to check for errors:

```bash
nargo check
```
In `Prover.toml`, the current value is equal to the test value, but can be adjusted.

Then execute it, and prove it i.e. with barretenberg:

```bash
nargo execute str_search
bb prove -b ./target/example.json -w ./target/str_search.gz -o ./target/proof
```

### Verify it

To verify, we need to export the verification key:

```bash
bb write_vk -b ./target/example.json -o ./target/vk
```

And verify:

```bash
bb verify -k ./target/vk -p ./target/proof
```
If verification passes, nothing is shown. Otherwise errors will pop up. 