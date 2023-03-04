-- Copyright (c) 2023 Peter Morgan <peter.james.morgan@gmail.com>
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

create table col_boolean (id serial primary key, a boolean);

insert into col_boolean (a) values (true);
insert into col_boolean (a) values (TRUE);
insert into col_boolean (a) values ('true');
insert into col_boolean (a) values ('yes');
insert into col_boolean (a) values ('on');
insert into col_boolean (a) values ('1');

insert into col_boolean (a) values (FALSE);
insert into col_boolean (a) values (false);
insert into col_boolean (a) values ('false');
insert into col_boolean (a) values ('no');
insert into col_boolean (a) values ('off');
insert into col_boolean (a) values ('0');
