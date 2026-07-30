-module(glsql_ffi).
-export([build_project/1, format_check/1]).

%% Whether the project in the given directory builds. 0 means it does.
%%
%% The first run has to fetch the driver and build it, which is slow enough to
%% need a lot more room than a later run that only recompiles what changed.
build_project(Dir) ->
    run("gleam build", binary_to_list(Dir), 600000).

%% Whether `gleam format` would leave the given directory alone. 0 means the
%% files there are already formatted.
format_check(Dir) ->
    run("gleam format --check " ++ binary_to_list(Dir), ".", 60000).

run(Command, Cwd, Timeout) ->
    Port = open_port({spawn, Command},
                     [exit_status, stderr_to_stdout, binary, {cd, Cwd}]),
    collect(Port, Timeout).

collect(Port, Timeout) ->
    receive
        {Port, {data, _}} -> collect(Port, Timeout);
        {Port, {exit_status, Status}} -> Status
    after Timeout ->
        %% Same code the `timeout` command uses, to tell running out of time
        %% apart from the command itself saying no.
        124
    end.
