# Concise Binary Object Representation (CBOR) in Erlang

This library implements a CBOR encoder/decoder in Erlang, see [RFC 7049](http://tools.ietf.org/html/rfc7049).

## Mappings

| Erlang                     | CBOR wire       | JSON |
| -------------              |------------- | -- |
|  `{[{"key", 99}, ..]}`     | map  | `{ "key" : 99, .. }` |
| `<<"abc">>`                | byte string | `"abc"`     
| `"abc"`                    | string | `"abc"`     
| `[1,2,3]`                  | list | `[1,2,3]`     
| `27`                       | integer   | `27`
| `0x010000000000000000`     | tag(bignum) 0x010000000000000000 | ?
| `true`                     | simple(21)     | `true` |
| `foo`                      | tag(100) `"foo"`  | `"foo"` |
| `{ 1, 2, 3 }`              | tag(101) list | `[1, 2, 3]` |
| `#{ a => true }`           | tag(102) map | `{ 'a' : true }` |
| `{{1970,1,10}, {07,05,00}}`| tag(0) `"1970-01-10T07:05:00Z"` | `"1970-01-10T07:05:00Z"`



## Issues

Erlang strings are encoded as CBOR strings, but these are indistinguishable from lists of integers that happen to have the same character codes.  I.e. `[46,46,46]` and `"..."` will both be encoded as strings.  Any list-of-integer where all elements are valid unicode codepoints will be encoded as a string; other lists are encoded as lists.

Maps are encoded as CBOR maps, but CBOR maps are decoded as `{[ {K,V}, ... ]}`.  Only maps encoded with tag 101 will be decoded as an Erlang map.

Tuples are encoded as tagged lists, so they will turn up as lists in foreign environments.

Decimal fractions are decoded as erlang floats, and thus may loose some precision.

Half-precision floats that are subnormal are not decoded correctly (very rare to see such values)

A future version should support passing in some options to control the encoding/decoding.

