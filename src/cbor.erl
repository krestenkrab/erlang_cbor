%% -------------------------------------------------------------------
%%
%% Concise Binary Object Representation (CBOR), RFC 7049
%%
%% Copyright (c) 2015, Trifork A/S
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(cbor).

-export([decode/1, encode/1]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(GREGORIAN_BASE, 62167219200).

%% erlang tags for known terms
-define(TERM_TAG, 99).
-define(ATOM_TAG, 100).
-define(TUPLE_TAG, 101).
-define(MAP_TAG, 102).

decode(Binary) when is_binary(Binary) ->
    case decode_head(Binary) of
        {0, N, Rest} ->
            {N, Rest};
        {1, N, Rest} ->
            {-1 - N, Rest};
        {2, Len, Rest} ->
            decode_bytestring(Len, Rest, []);
        {3, Len, Rest} ->
            decode_string(Len, Rest, []);
        {4, Len, Rest} ->
            decode_list(Len, Rest, []);
        {5, Len, Rest} ->
            decode_map(Len, Rest, []);
        {6, Tag, Rest} ->
            {Item, Rest2} = decode(Rest),
            {tagged(Tag, Item), Rest2};
        {float, Float, Rest} ->
            {Float, Rest};
        {simple, N, Rest} ->
            {simple(N), Rest};
        {break, Rest} ->
            {break, Rest}
    end;
decode(IOList) ->
    decode( iolist_to_binary(IOList) ).


decode_head(<<7:3, N:5, Rest/binary>>) when N < 24 ->
    {simple, N, Rest};
decode_head(<<7:3, 24:5, N:8, Rest/binary>>) ->
    {simple, N, Rest};
decode_head(<<7:3, 25:5, N:2/binary, Rest/binary>>) ->
    {float, decode_ieee745(N), Rest};
decode_head(<<7:3, 26:5, N:4/binary, Rest/binary>>) ->
    {float, decode_ieee745(N), Rest};
decode_head(<<7:3, 27:5, N:8/binary, Rest/binary>>) ->
    {float, decode_ieee745(N), Rest};
decode_head(<<7:3, 31:5, Rest/binary>>) ->
    {break, Rest};

decode_head(<<Major:3, N:5, Rest/binary>>) when N < 24 ->
    {Major, N, Rest};
decode_head(<<Major:3, 24:5, N:8, Rest/binary>>) ->
    {Major, N, Rest};
decode_head(<<Major:3, 25:5, N:16, Rest/binary>>) ->
    {Major, N, Rest};
decode_head(<<Major:3, 26:5, N:32, Rest/binary>>) ->
    {Major, N, Rest};
decode_head(<<Major:3, 27:5, N:64, Rest/binary>>) ->
    {Major, N, Rest};
decode_head(<<Major:3, 31:5, Rest/binary>>) ->
    {Major, indefinite, Rest}.


tagged(0, String) ->
    case rfc3339_decode(String) of
        {ok, {Date, {TH,TM,TS,_}, Offset}} ->
            BaseSecs = calendar:datetime_to_gregorian_seconds({Date, {TH,TM,TS}}),
            GregSecs = case Offset of
                           'Z' -> BaseSecs;
                           {Dir,H,M} when Dir =:= '+'; Dir =:= '-' ->
                               Diff   = (H * 3600) + (M * 60),
                               apply(erlang, Dir, [BaseSecs, Diff])
                       end,
            calendar:gregorian_seconds_to_datetime( GregSecs );
        {error, _} ->
            String
    end;
tagged(1, EpochSeconds) when is_integer(EpochSeconds) ->
    GregSecs = ?GREGORIAN_BASE + EpochSeconds,
    calendar:gregorian_seconds_to_datetime(GregSecs);
tagged(1, EpochSeconds) when is_float(EpochSeconds) ->
    GregSecs = ?GREGORIAN_BASE + round(EpochSeconds),
    calendar:gregorian_seconds_to_datetime(GregSecs);
tagged(2, Binary) when is_binary(Binary) ->
    Length = byte_size(Binary) * 8,
    <<N:Length>> = Binary,
    N;
tagged(3, Binary) when is_binary(Binary) ->
    Length = byte_size(Binary) * 8,
    <<N:Length>> = Binary,
    -1 - N;
tagged(4, [E,V]) ->
    math:pow(10,E) * V;
tagged(?TUPLE_TAG, L) when is_list(L) ->
    erlang:list_to_tuple(L);
tagged(?ATOM_TAG, A) when is_list(A) ->
    try
        erlang:list_to_existing_atom(A)
    catch
        _:badarg -> A
    end;
tagged(?MAP_TAG, {M}) when is_list(M) ->
    try
        maps:from_list(M)
    catch
        _:badarg -> M
    end;
tagged(?TERM_TAG, T) when is_binary(T) ->
    try
        erlang:binary_to_term(T, [safe])
    catch
        _:badarg -> T
    end;
tagged(_N, Value) ->
    Value.

simple(20) ->
    false;
simple(21) ->
    true;
simple(22) ->
    null;
simple(23) ->
    undefined;
simple(N) ->
    {simple, N}.

decode_bytestring(indefinite, Rest, Acc) ->
    case decode(Rest) of
        {break, Rest1} ->
            { iolist_to_binary(lists:reverse(Acc)), Rest1 };
        {ByteString, Rest1} ->
            decode_bytestring(indefinite, Rest1, [ByteString|Acc])
    end;

decode_bytestring(Length, Rest, []) ->
    <<ByteString:Length/binary, Rest1/binary>> = Rest,
    {ByteString, Rest1}.


decode_string(indefinite, Rest, Acc) ->
    case decode(Rest) of
        {break, Rest1} ->
            { lists:flatten(lists:reverse(Acc)), Rest1 };
        {String, Rest1} ->
            decode_string(indefinite, Rest1, [String|Acc])
    end;

decode_string(Length, Rest, []) ->
    <<String:Length/binary, Rest1/binary>> = Rest,
    { unicode:characters_to_list(String), Rest1}.


decode_list(indefinite, Rest, Acc) ->
    case decode(Rest) of
        {break, Rest2} ->
            {lists:reverse(Acc), Rest2};
        {Item, Rest2} ->
            decode_list(indefinite, Rest2, [Item|Acc])
    end;

decode_list(0, Rest, Acc) ->
    { lists:reverse(Acc), Rest };
decode_list(N, Rest, Acc) ->
    { Item, Rest2 } = decode(Rest),
    decode_list(N-1, Rest2, [Item|Acc]).


decode_map(indefinite, Rest, Acc) ->
    case decode(Rest) of
        {break, Rest2} ->
            {{lists:reverse(Acc)}, Rest2};
        {Key, Rest2} ->
            { Value, Rest3 } = decode(Rest2),
            decode_map(indefinite, Rest3, [{Key, Value}|Acc])
    end;

decode_map(0, Rest, Acc) ->
    {{lists:reverse(Acc)}, Rest };
decode_map(N, Rest, Acc) ->
    { Key, Rest2 }   = decode(Rest),
    { Value, Rest3 } = decode(Rest2),
    decode_map(N-1, Rest3, [{Key,Value}|Acc]).

decode_ieee745(<<0:1, 16#1F:5, 0:10>>) ->
    'pos_infinity';
decode_ieee745(<<1:1, 16#1F:5, 0:10>>) ->
    'neg_infinity';
decode_ieee745(<<_:1, 16#1F:5, _:10>>) ->
    'NaN';
decode_ieee745(<<_:1, 16#00:5, 0:10>>) ->
    0.0;
decode_ieee745(<<Sign:1, Exp16:5, Frac:10>>) ->
    Exp32 = (Exp16-15)+127,
    <<Float32:32/float>> = <<Sign:1, Exp32:8, Frac:10, 0:13 >>,
    Float32;

decode_ieee745(<<F:32/float>>) ->
    F;
decode_ieee745(<<0:1, 16#FF:8, 0:23>>) ->
    'pos_infinity';
decode_ieee745(<<1:1, 16#FF:8, 0:23>>) ->
    'neg_infinity';
decode_ieee745(<<_:1, 16#FF:8, _:23>>) ->
    'NaN';
decode_ieee745(<<_:1, 16#00:8, 0:23>>) ->
    0.0;

decode_ieee745(<<F:64/float>>) ->
    F;
decode_ieee745(<<0:1, 16#7FF:11, 0:52>>) ->
    'pos_infinity';
decode_ieee745(<<1:1, 16#7FF:11, 0:52>>) ->
    'neg_infinity';
decode_ieee745(<<_:1, 16#7FF:11, _:52>>) ->
    'NaN';
decode_ieee745(<<_:1, 16#000:11, 0:52>>) ->
    0.0.

rfc3339_decode(String) ->
    {ok, RE} = re:compile("^([0-9]{3,4})-([0-9]{1,2})-([0-9]{1,2})"
                          ++ "([Tt]([0-9]{1,2}):([0-9]{1,2}):([0-9]{1,2})(\\.[0-9]+)?)?"
                          ++ "(([Zz]|([+-])([0-9]{1,2}):([0-9]{1,2})))?"),

    case re:run(String, RE, [{capture, all_but_first, list}]) of
        {match, [Ye,Mo,Da|Rest]} ->
            Year  = case length(Ye) of
                        3 -> 1900 + list_to_integer(Ye);
                        4 -> list_to_integer(Ye)
                    end,
            Month = list_to_integer(Mo),
            Day   = list_to_integer(Da),

            {Hour, Minute, Seconds, Fraction, Rest4} =
                case Rest of
                    [] ->
                        {0, 0, 0, 0.0, []};

                    [ [], _, _, _ |Rest2] ->
                        {0, 0, 0, 0.0, Rest2};

                    [Time,Ho,Mi,Se|Rest2] when Time =/= [] ->
                        Hour1    = list_to_integer(Ho),
                        Minute1  = list_to_integer(Mi),
                        Seconds1 = list_to_integer(Se),

                        {Fraction1, Rest5} =
                            case Rest2 of
                                [ [] | Rest3 ] ->
                                    {0.0, Rest3};
                                [ Frac | Rest3 ] ->
                                    {list_to_float("0" ++ Frac ), Rest3};
                                [] ->
                                    {0.0, []}
                            end,

                        {Hour1, Minute1, Seconds1, Fraction1, Rest5}
                end,

            Offset =
                case Rest4 of
                    [] ->
                        'Z';
                    ["Z","Z"] ->
                        'Z';
                    [_,_,Sign,HOff,MOff] ->
                        { list_to_atom([Sign]),
                          list_to_integer(HOff),
                          list_to_integer(MOff) }
                end,

            {ok, {{Year, Month, Day}, {Hour, Minute, Seconds, Fraction}, Offset}};
        _ ->
            {error, rfc3339}
    end.


-define(TAG(N), encode_head(6, Tag)).

encode(N) when is_integer(N) ->
    encode_integer(N);
encode(B) when is_binary(B) ->
    encode_bytestring(B);
encode(F) when is_float(F) ->
    <<7:3, 27:5, F:64/float>>;
encode({L}) when is_list(L) ->
    encode_map(L);
encode(M) when is_map(M) ->
    [ encode_head(6, ?MAP_TAG) | encode_map( maps:to_list(M) ) ];
encode(L) when is_list(L) ->
    case io_lib:printable_unicode_list(L) of
        true ->
            encode_string(L);
        false ->
            encode_list(L)
    end;

encode(false) ->
    encode_head(7, 20);
encode(true) ->
    encode_head(7, 21);
encode(null) ->
    encode_head(7, 22);
encode(undefined) ->
    encode_head(7, 23);

%% special float values are encoded as 32-bit floats
encode('NaN') ->
    << 7:3, 26:5,  1:1, 16#ff:8, 1:23 >>;
encode('pos_infinity') ->
    << 7:3, 26:5,   0:1, 16#ff:8, 0:23 >>;
encode('neg_infinity') ->
    << 7:3, 26:5,   1:1, 16#ff:8, 0:23 >>;

encode(A) when is_atom(A) ->
    %% encode atoms as tagged strings, to make them JS-compatible
    Name = atom_to_binary(A, latin1),
    [ encode_head(6, ?ATOM_TAG) | encode_string( Name ) ];

encode({{Ye,Mo,Da},{Ho,Mi,Se}}=DateTime)
  when is_integer(Ye),
       Mo >= 1, Mo < 13,
       Da >= 1, Da < 32,
       Ho >= 0, Ho < 24,
       Mi >= 0, Mi < 60,
       Se >= 0, Se < 60 ->
    encode_datetime(DateTime);

encode({Mega,Secs,Micro}=Now)
  when is_integer(Mega), Mega > 0,
       is_integer(Secs), Secs > 0,
       is_integer(Micro), Micro > 0 ->
    encode_datetime( calendar:now_to_datetime(Now) );

encode(T) when is_tuple(T) ->
    List = tuple_to_list(T),
    [ encode_head(6, ?TUPLE_TAG) | encode_list( List ) ];

encode(T) ->
    [ encode_head(6, ?TERM_TAG) | encode_bytestring( erlang:term_to_binary( T ) ) ].


encode_datetime(DateTime={{Y,_,_},{_,_,_}}) when Y >= 1970, Y < 2038 ->
    EpochSeconds = calendar:datetime_to_gregorian_seconds(DateTime) - ?GREGORIAN_BASE,
    [ encode_head(6, 1) | encode_integer( EpochSeconds ) ];

encode_datetime({{Year,Month,Day},{Hour,Minute,Second}}) ->
    String = io_lib:format("~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0BZ",
                           [Year, Month, Day, Hour, Minute, Second]),
    io:format("~s~n", [String]),
    [ encode_head(6, 0) | encode_string( String ) ].


encode_string(S) ->
    Binary = unicode:characters_to_binary(S),
    [ encode_head(3, byte_size(Binary)) | Binary ].

encode_list(L) ->
    Length = length(L),
    [ encode_head(4, Length ) | lists:map( fun encode/1, L ) ].

encode_map(M) ->
    Length = length(M),
    [ encode_head(5, Length ) |
      lists:map( fun({K,V}) ->
                         [ encode(K) | encode(V) ]
                 end, M ) ].

encode_integer(N) when N >= 0, N =< 16#ffffffffffffffff ->
    encode_head(0, N);

encode_integer(N) when N < 0, -(N+1) =< 16#ffffffffffffffff ->
    encode_head(1, -(N+1));

encode_integer(N) when N >= 0 ->
    Length = count_big_bits(N),
    [ encode_head(6,2) | encode_bytestring( << N:Length >> ) ];

encode_integer(N) when N < 0 ->
    NN = -(N+1),
    Length = count_big_bits(NN),
    [ encode_head(6,3) | encode_bytestring( << NN:Length >> ) ].

encode_bytestring(B) ->
    [ encode_head(2, byte_size(B)) | B ].

encode_head(Tag,N) when N < 24 ->
    << Tag:3, N:5 >>;
encode_head(Tag,N) when N =< 16#ff ->
    << Tag:3, 24:5, N >>;
encode_head(Tag,N) when N =< 16#ffff ->
    << Tag:3, 25:5, N:16 >>;
encode_head(Tag,N) when N =< 16#ffffffff ->
    << Tag:3, 26:5, N:32 >>;
encode_head(Tag,N) when N =< 16#ffffffffffffffff ->
    << Tag:3, 26:5, N:64 >>.


count_big_bits(N) when N >= 0, N < 16#ff ->
    8;
count_big_bits(N) when N >= 0 ->
    8 + count_big_bits(N bsr 8).


-ifdef(TEST).

%% utility function to generate binary input

hex_bin(String) ->
    List = decode_binary(String, []),
    iolist_to_binary( List ).
decode_binary([], Acc) ->
    lists:reverse(Acc);
decode_binary([$ |Rest], Acc) ->
    decode_binary(Rest, Acc);
decode_binary([$0, $b, B7, B6, B5, $_, B4, B3, B2, B1, B0 | Rest], Acc) ->
    Byte = list_to_integer([B7,B6,B5,B4,B3,B2,B1,B0], 2),
    decode_binary(Rest,  [Byte | Acc]);
decode_binary([$$, A|Rest], Acc) ->
    decode_binary(Rest, [A|Acc]);
decode_binary([$0, $x, H,L|Rest], Acc) ->
    decode_binary(Rest, [list_to_integer([H,L], 16) | Acc]);
decode_binary([H,L|Rest], Acc) ->
    decode_binary(Rest, [list_to_integer([H,L], 16) | Acc]).

bin_test() ->

    <<16#f8, 16#01>> = hex_bin("f801"),
    <<16#f8, 16#01>> = hex_bin("0xf8 01"),
    <<16#00>> = hex_bin("0b000_00000"),

    ok.

decode_test() ->

    %% decimal fraciton 273.15
    {273.15000000000003, <<>>} = decode( hex_bin("c4 8221196a b3")),

    %% byte string concatenation
    S = hex_bin("0xaabbccdd 0xeeff99"),
    B = hex_bin("0b010_11111 0b010_00100 0xaabbccdd 0b010_00011 0xeeff99 0b111_11111"),
    {S, <<>>} = decode(B),

    %% indefinete length arrays
    {[1,[2,3],[4,5]],<<>>} = decode( hex_bin( "0x83018202039f0405ff" )),
    {[1,[2,3],[4,5]],<<>>} = decode( hex_bin( "0x83019f0203ff820405" )),

    %% indefinite length map
    {{[{"Fun",true},{"Amt",-2}]},<<>>}
        = decode( hex_bin( "0xbf 63$F$u$n f5  63$A$m$t 21  ff" )),

    %% date/time
    {{{1753,9,7},{1,0,0}}, <<>>} =
       decode(<<16#c0, 16#74, "1753-09-07T01:00:00Z">>),

    %% test that we handle Self-Describe CBOR
    { 0, <<>>} =
        decode( hex_bin( "0xd9d9f7 00" )),

    ok.

-define(assertCoding(String, Term),
        ?assertEqual( hex_bin(String), iolist_to_binary( encode(Term) )),
        ?assertEqual( {Term,<<>>}, decode( hex_bin(String) ) )).

basic(Term) ->
    ?assertEqual({Term,<<>>}, decode(encode(Term))).

code_test() ->

    %% fixed length list
    ?assertCoding( "0x8301820203820405", [1,[2,3],[4,5]]),

    %% integer
    ?assertCoding( "00", 0 ),
    ?assertCoding( "20", -1 ),

    %% float (we encode all floats @ 64 bit)
    ?assertCoding( "0xfB 4010 0000 0000 0000", 4.0 ),

    %% bignum
    ?assertCoding( "c2 49 0x010000000000000000", 18446744073709551616 ),

    %% simpe
    ?assertCoding( "0b111_10100", false ),
    ?assertCoding( "0b111_10101", true ),
    ?assertCoding( "0b111_10110", null ),
    ?assertCoding( "0b111_10111", undefined ),

    basic( 7 ),
    basic( foo ),
    basic( "Hello" ),
    basic( [1, 2, 2.3, "xx"] ),

    ok.


decode2_test_() ->
    Tests =
        [
         {0, "0x00"},
         {1, "0x01"},
         {10, "0x0a"},
         {23, "0x17"},
         {24, "0x1818"},
         {25, "0x1819"},
         {100, "0x1864"},
         {1000, "0x1903e8"},
         {1000000, "0x1a000f4240"},
         {1000000000000, "0x1b000000e8d4a51000"},

         {18446744073709551615, "0x1bffffffffffffffff"},
         {18446744073709551616, "0xc249010000000000000000"},
         {-18446744073709551616, "0x3bffffffffffffffff"},
         {-18446744073709551617, "0xc349010000000000000000"},

         {-1, "0x20"},
         {-10, "0x29"},
         {-100, "0x3863"},
         {-1000, "0x3903e7"},

         {0.0,  "0xf90000"},
         {-0.0, "0xf98000"},

         {1.0, "0xf93c00"},

         {1.1, "0xfb3ff199999999999a"},
         {1.5, "0xf93e00"},

         {65504.0, "0xf97bff"},

         {100000.0, "0xfa47c35000"},
         {3.4028234663852886e+38, "0xfa7f7fffff"},

         {1.0e300, "0xfb7e37e43c8800759c"},

         % we don't handle subnormal numbers
         %{5.960464477539063e-8, "0xf90001"},
         {0.00006103515625, "0xf90400"},

         {-4.0, "0xf9c400"},
         {-4.1, "0xfbc010666666666666"},
         {'pos_infinity', "0xf97c00"},
         {'NaN', "0xf97e00"},
         {'neg_infinity', "0xf9fc00"},
         {'pos_infinity', "0xfa7f800000"},
         {'NaN', "0xfa7fc00000"},
         {'neg_infinity', "0xfaff800000"},
         {'pos_infinity', "0xfb7ff0000000000000"},
         {'NaN', "0xfb7ff8000000000000"},
         {'neg_infinity', "0xfbfff0000000000000"},
         {false, "0xf4"},
         {true, "0xf5"},
         {null, "0xf6"},
         {undefined, "0xf7"},

         {{simple, 16}, "0xf0"},
         {{simple, 24}, "0xf818"},
         {{simple, 255}, "0xf8ff"},
         {new_date(1363896240000), "0xc074323031332d30332d32315432303a30343a30305a"},
         {new_date(1363896240000), "0xc1 1a514b67b0"},
         {new_date(1363896240500), "0xc1 fb 41d452d9ec200000"},

         %% {"23(h"01020304")", "0xd74401020304"},
         %% {"24(h"6449455446")", "0xd818456449455446"},

         {"http://www.example.com", "0xd82076687474703a2f2f7777772e6578616d706c652e636f6d"},
         {<<>>, "0x40"},
         {hex_bin("01020304"), "0x4401020304"},
         {"", "0x60"},
         {"a", "0x6161"},
         {"IETF", "0x6449455446"},
         {"\"\\", "0x62225c"},
         {[16#00fc], "0x62c3bc"},
         {[16#6c34], "0x63e6b0b4"},
         {[16#10151], "0x64f0908591"},
         {[], "0x80"},
         {[1, 2, 3], "0x83010203"},
         {[1, [2, 3], [4, 5]], "0x8301820203820405"},
         {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25], "0x98190102030405060708090a0b0c0d0e0f101112131415161718181819"},
         {{[]}, "0xa0"},
         {{[]}, "0xbfff"},
         {{[{1, 2}, {3, 4}]}, "0xa2  01 02  03 04"},
         {{[{"a", 1}, {"b", [2, 3]}]}, "0xa26161016162820203"},
         {["a", {[{"b", "c"}]}], "0x826161a161626163"},
         {{[{"a", "A"}, {"b", "B"}, {"c", "C"}, {"d", "D"}, {"e", "E"}]}, "0xa56161614161626142616361436164614461656145"},
         {hex_bin("0102030405"), "0x5f42010243030405ff"},
         {"streaming", "0x7f657374726561646d696e67ff"},
         {[new_date(1363896240000)], "0x9fd87fc07f6a323031332d30332d323161546832303a30343a3030615affff"},
         {[], "0x9fff"},
         {[1, [2, 3], [4, 5]], "0x9f018202039f0405ffff"},
         {[1, [2, 3], [4, 5]], "0x9f01820203820405ff"},
         {[1, [2, 3], [4, 5]], "0x83018202039f0405ff"},
         {[1, [2, 3], [4, 5]], "0x83019f0203ff820405"},
         {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25], "0x9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff"},
         {{[{"a", 1}, {"b", [2, 3]}]}, "0xbf61610161629f0203ffff"},
         {["a", {[{"b","c"}]}], "0x826161bf61626163ff"}
        ],

    lists:map(fun({Term,Input}) ->
                      fun() ->
                         case catch decode( hex_bin(Input) ) of
                             {Term1,<<>>} ->
                                 ?assertEqual(Term1, Term)
                         end
                      end
                 end,
                 Tests).

new_date(Millis) ->
    calendar:gregorian_seconds_to_datetime(round(Millis / 1000) + ?GREGORIAN_BASE).

-endif.
