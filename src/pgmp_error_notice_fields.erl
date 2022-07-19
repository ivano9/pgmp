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


-module(pgmp_error_notice_fields).


-export([callback_mode/0]).
-export([init/1]).
-export([name/1]).
-export([start_link/0]).
-import(pgmp_statem, [nei/1]).
-include_lib("stdlib/include/ms_transform.hrl").


start_link() ->
    gen_statem:start_link(?MODULE, [], []).


name(Id) ->
    case ets:lookup(?MODULE, Id) of
        [{_, Name}] ->
            Name;

        [] ->
            error(badarg, [Id])
    end.


init([]) ->
    process_flag(trap_exit, true),
     ets:insert_new(
       ets:new(?MODULE, [named_table]),
       pgmp:priv_consult("error-notice-fields.terms")),
    {ok, ready, #{}}.


callback_mode() ->
    handle_event_function.
