-module(glsql_ffi).
-export([check_project/0, format_check/1]).

check_project() ->
    run("gleam check").

%% Whether `gleam format` would leave the given directory alone. 0 means the
%% files there are already formatted.
format_check(Dir) ->
    run("gleam format --check " ++ binary_to_list(Dir)).

run(Command) ->
    Port = open_port({spawn, Command},
                     [exit_status, stderr_to_stdout, binary]),
    collect(Port).

collect(Port) ->
    receive
        {Port, {data, _}} -> collect(Port);
        {Port, {exit_status, Status}} -> Status
    after 60000 ->
        1
    end.
