use dep::noir_string_search::{StringBody, StringBody64, SubString, SubString32};

fn main(needle_text: str<13>) {
    let haystack_text = "the quick brown fox jumped over the lazy dog".as_bytes();
    let needle_text_bytes = needle_text.as_bytes();

    let haystack: StringBody64 = StringBody::new(haystack_text, haystack_text.len());
    let needle: SubString32 = SubString::new(needle_text_bytes, needle_text_bytes.len());

    let (result, _): (bool, u32) = haystack.substring_match(needle);
    assert(result);
}

#[test]
fn test_main() {
    let needle_text = " the lazy dog";
    main(needle_text);
}
