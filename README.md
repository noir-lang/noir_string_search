# noir_string_search

A noir library that can be used to prove that a given "needle" substring is present within a larger "haystack" string.

Features:

- Both the needle and haystack string can have variable runtime lengths (up to a defined maximum)
- Efficient implementation ~2 gates per haystack byte, ~5 gates per needle byte
- Both needle and haystack strings can be dynamically constructed in-circuit if required

## Noir version compatibility

This library is tested with all Noir stable releases from v0.36.0.

## Typedefs

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

## Usage

### Basic usage

```rust
let haystack_text = "the quick brown fox jumped over the lazy dog".as_bytes();
let needle_text = " the lazy dog".as_bytes();

let haystack: StringBody64 = StringBody::new(haystack_text, haystack_text.len());
let needle: SubString32 = SubString::new(needle_text, needle_text.len());

let (result, match_position): (bool, u32) = haystack.substring_match(needle);
```

### Dynamic needle construction

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

### Costs

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
