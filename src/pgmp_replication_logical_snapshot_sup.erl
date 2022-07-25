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


-module(pgmp_replication_logical_snapshot_sup).


-behaviour(supervisor).
-export([init/1]).
-export([start_link/1]).
-import(pgmp_sup, [supervisor/1]).
-import(pgmp_sup, [worker/1]).


start_link(#{config := Config} = Arg) ->
    supervisor:start_link(
      ?MODULE,
      [Arg#{config := Config#{replication => fun replication/0}}]).


init([#{ancestors := Ancestors} = Arg]) ->
    {ok, configuration(children(Arg#{ancestors := [self() | Ancestors]}))}.


configuration(Children) ->
    {#{intensity => length(Children), strategy => one_for_all}, Children}.


replication() ->
    <<"false">>.


children(Arg) ->
    [worker(#{m => M, args => [Arg#{supervisor => self()}]}) || M <- workers()].


workers() ->
    [pgmp_socket, pgmp_mm, pgmp_replication_logical_snapshot_manager].
