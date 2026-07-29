-module(glsql_ffi).
-export([check_project/0]).

check_project() ->
    Port = open_port({spawn, "gleam check"},
                     [exit_status, stderr_to_stdout, binary]),
    collect(Port).

collect(Port) ->
    receive
        {Port, {data, _}} -> collect(Port);
        {Port, {exit_status, Status}} -> Status
    after 60000 ->
        1
    end.
