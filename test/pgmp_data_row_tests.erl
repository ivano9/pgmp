%% Copyright (c) 2022 Peter Morgan <peter.james.morgan@gmail.com>
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.


-module(pgmp_data_row_tests).


-include_lib("eunit/include/eunit.hrl").


decode_test_() ->
    lists:map(
      t(decode(maps:from_list(phrase_file:consult("test/type.terms")))),
      phrase_file:consult("test/data-row-decode.terms")).

decode(Types) ->
    fun
        (Parameters, Format, Type, Data) ->
            pgmp_data_row:decode(Parameters, Format, Types, Type, Data)
    end.


t(F) ->
    fun
        ({Expected, Input} = Test) ->
            {nm(Test), ?_assertEqual(Expected, apply(F, Input))}
    end.


nm(Test) ->
    iolist_to_binary(io_lib:fwrite("~p", [Test])).
