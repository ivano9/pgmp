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


-module(pgmp_mm_replication_logical).


-export([callback_mode/0]).
-export([handle_event/4]).
-export([terminate/3]).
-import(pgmp_codec, [demarshal/1]).
-import(pgmp_codec, [marshal/2]).
-import(pgmp_codec, [prefix_with_size/1]).
-import(pgmp_data_row, [decode/2]).
-import(pgmp_mm_common, [field_names/1]).
-import(pgmp_statem, [nei/1]).
-include_lib("kernel/include/logger.hrl").


callback_mode() ->
    [handle_event_function, state_enter].


terminate(Reason, State, Data) ->
    pgmp_mm_common:terminate(Reason, State, Data).


handle_event({call, From},
             {request, #{action := start_replication}},
             waiting_for_snapshot_completion,
             Data) ->
    {next_state,
     replication,
     Data#{wal => #{received => 0,
                    flushed => 0,
                    applied => 0}},
     [nei(start_replication), {reply, From, ok}]};

handle_event(internal, {recv, {copy_both_response, _}}, _, _) ->
    keep_state_and_data;

handle_event(internal, {recv, {copy_data, {Tag, _} = TM}}, _, _)
  when Tag == keepalive; Tag == x_log_data ->
    {keep_state_and_data, nei(TM)};

handle_event(internal, {x_log_data, #{stream := Stream}}, _, _) ->
    {keep_state_and_data, nei(Stream)};

handle_event(internal, {begin_transaction, _}, _, _) ->
    keep_state_and_data;

handle_event(internal,
             {insert, #{relation := Relation, tuple := Values}},
             _,
             #{relations := Relations, parameters := Parameters}) ->
    #{Relation := #{columns := Columns, name := Table}} = Relations,
    ets:insert_new(
      binary_to_atom(Table),
      list_to_tuple(
        pgmp_data_row:decode(
          Parameters,
          lists:map(
            fun
                ({#{type := Type}, null = Value}) ->
                    {#{format => text, type_oid => Type}, Value};

                ({#{type := Type}, #{format := Format, value := Value}}) ->
                    {#{format => Format, type_oid => Type}, Value}
            end,
            lists:zip(Columns, Values))))),
    keep_state_and_data;

handle_event(internal,
             {relation, #{id := Id} = Relation},
             _,
             #{relations := Relations} = Data) ->
    {keep_state,
     Data#{relations := Relations#{Id => maps:without([id], Relation)}}};

handle_event(internal, {commit, _}, _, _) ->
    keep_state_and_data;


handle_event(internal,
             {keepalive,
              #{clock := Clock,
                end_wal := _,
                reply := true = Reply}},
             _,
             #{wal := #{received := ReceivedWAL,
                        flushed :=  FlushedWAL,
                        applied := AppliedWAL}}) ->
    {keep_state_and_data,
     nei({standby_status_update,
          #{received_wal => ReceivedWAL,
            flushed_wal => FlushedWAL,
            applied_wal => AppliedWAL,
            clock => Clock,
            reply => Reply}})};

handle_event(internal, {keepalive, _}, _, _) ->
    keep_state_and_data;

handle_event(internal,
             {response, #{label := pgmp_replication_logical_snapshot_manager, reply :=  ok}},
             _,
             _) ->
    keep_state_and_data;

handle_event(internal,
             {response, #{label := pgmp_types, reply := ready}},
             waiting_for_types,
             #{types_ready := false} = Data) ->

    {next_state,
     identify_system,
     Data#{types_ready := true},
     [nei(snapshot_manager), nei(identify_system)]};

handle_event(internal,
             bootstrap_complete,
             _,
             #{types_ready := false} = Data) ->
    {next_state, waiting_for_types, Data};

handle_event(internal,
             bootstrap_complete,
             _,
             #{types_ready := true} = Data) ->
    {next_state,
     identify_system,
     Data,
     [nei(snapshot_manager), nei(identify_system)]};

handle_event(internal,
             snapshot_manager,
             _,
             #{config := Config, ancestors :=  [_, LogicalSup]} = Data) ->

    {_, SnapSup, supervisor, _} =  pgmp_sup:get_child(
                                     LogicalSup,
                                     replication_logical_snapshot_sup),

    {_, SnapMan, worker, _} = pgmp_sup:get_child(
                                SnapSup,
                                replication_logical_snapshot_manager),
    {keep_state, Data#{config := Config#{manager => SnapMan}}};

handle_event(internal, identify_system, _, _) ->
    {keep_state_and_data, nei({query, [<<"IDENTIFY_SYSTEM">>]})};

handle_event(internal,
             {recv, {command_complete, Command}},
             _,
             Data) when Command == identify_system;
                        Command == create_replication_slot ->
    {keep_state, maps:without([columns], Data)};


handle_event(internal,
             {recv, {ready_for_query, idle}},
             identify_system,
             Data) ->
    {next_state, replication_slot, Data, nei(create_replication_slot)};

handle_event(
  internal,
  {recv, {ready_for_query, idle}},
  replication_slot,
  #{config := #{manager := Manager},
    requests := Requests,
    replication_slot := #{<<"snapshot_name">> := Snapshot}} = Data) ->
    {next_state,
     waiting_for_snapshot_completion,
     Data#{requests := pgmp_replication_logical_snapshot_manager:snapshot(
                         #{server_ref => Manager,
                           id => Snapshot,
                           requests => Requests})}};

handle_event(internal, create_replication_slot = Command, _, _) ->
    {keep_state_and_data,
     nei({Command, pgmp_config:replication(logical, slot_name)})};

handle_event(internal, {create_replication_slot, SlotName}, _, _) ->
    {keep_state_and_data,
     nei({query,
          [iolist_to_binary(
             io_lib:format(
               <<"CREATE_REPLICATION_SLOT ~s TEMPORARY LOGICAL pgoutput">>,
               [SlotName]))]})};

handle_event(internal, start_replication, _, _Data) ->
    {keep_state_and_data,
     nei({start_replication,
          pgmp_config:replication(logical, proto_version),
          pgmp_config:replication(logical, publication_names)})};

handle_event(internal,
             {start_replication, ProtoVersion, PublicationNames},
             _,
             #{identify_system := #{<<"xlogpos">> := _Location},
               replication_slot := #{<<"slot_name">> := SlotName}} = Data) ->
    {keep_state,
     Data#{relations => #{}},
     nei({query,
          [iolist_to_binary(
             io_lib:format(
               <<"START_REPLICATION SLOT ~s LOGICAL ~s ",
                 "(proto_version '~b', publication_names '~p')">>,
               [SlotName, "0/0", ProtoVersion, PublicationNames]))]})};

handle_event(internal, {recv, {row_description, Columns}}, _, Data) ->
    {keep_state, Data#{columns => Columns}};

handle_event(internal,
             {recv, {data_row, Values}},
             State,
             #{parameters := Parameters,
               columns := Columns} = Data) ->
    {keep_state,
     maps:put(State,
              lists:foldl(
                fun
                    ({#{field_name := FieldName}, Value}, A) ->
                        A#{FieldName => Value}
                end,
                maps:get(State, Data, #{}),
                lists:zip(Columns,
                          decode(
                            Parameters,
                            lists:zip(Columns, Values)))),
              Data)};

handle_event(internal, {query, [SQL]}, _, _) ->
    {keep_state_and_data,
     nei({send, [<<$Q>>, prefix_with_size([marshal(string, SQL)])]})};

handle_event(internal,
             {standby_status_update,
              #{received_wal := ReceivedWAL,
                flushed_wal := FlushedWAL,
                applied_wal := AppliedWAL,
                clock := Clock,
                reply := Reply}},
             _,
             _) ->
    {keep_state_and_data,
     nei({send,
          [<<$d>>,
           prefix_with_size(
             ["r",
              <<ReceivedWAL:64,
                FlushedWAL:64,
                AppliedWAL:64,
                Clock:64,
                (b(Reply)):8>>])]})};

handle_event(EventType, EventContent, State, Data) ->
    pgmp_mm_common:handle_event(EventType,
                                EventContent,
                                State,
                                Data).

b(false) -> 0;
b(true) -> 1;
b(0) -> false;
b(1) -> true.
