-module(mtl_listener).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, { context, socket, command_state }).

-include("mtl.hrl").

-define(TRACE, io:format).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?LISTENER}, ?MODULE, [], []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
    process_flag(trap_exit, true),
    {ok, Context} = erlzmq:context(),
    %% Use active now, though we may wish to change this and have a
    %% listener loop later on.
    {ok, Socket} = erlzmq:socket(Context, [?ROUTER, {active, true}]),
    ok = erlzmq:bind(Socket, "tcp://0.0.0.0:5975"),
    io:format("Listening on tcp://0.0.0.0:5975~n"),
    {ok, fresh_command(#state{ context = Context,
                               socket = Socket})}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({zmq, _Sock, Data}, State = #state{ command_state = CmdSt }) ->
    ?TRACE("Data ~p~n", [Data]),
    NewState =
        case msg(CmdSt, Data) of
            {command, Identity, Cmd, Args} ->
                {ok, Reply, State1} =
                    handle_command(Identity, Cmd, Args, State),
                ?TRACE("Command: ~p~nReply: ~p~n", [Cmd, Reply]),
                {ok, State2} = send_reply(Identity, Reply, State1), 
                fresh_command(State2);
            {more, NewCmdSt} ->
                %% Check that there's more to come -- this won't
                %% work with active, of course.
                %% {ok, 1} = erlzmq:getsockopt(Sock, rcvmore),
                more_command(State, NewCmdSt);
            {error, _} ->
                %% MTL says just drop it all
                fresh_command(State)
        end,
    {noreply, NewState}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, #state{ socket = Socket, context = Context }) ->
    erlzmq:close(Socket, 2000),
    erlzmq:term(Context, 2000),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

fresh_command(State = #state{}) ->
    State#state{ command_state = identity }.

more_command(State = #state{}, NewCmdState) ->
    State#state{ command_state = NewCmdState }.

msg(identity, Addr) ->
    {more, {empty, Addr}};
msg({empty, Addr}, <<>>) ->
    {more, {name, Addr}};
msg({name, Addr}, Command) ->
    {more, {body, Addr, Command}};
msg({body, Addr, Command}, Body) ->
    case parse_command(Command, Body) of
        {ok, CommandAtom, Args} ->
            {command, Addr, CommandAtom, Args};
        Err = {error, _} ->
            Err
    end;
msg(_, Msg) ->
    ?TRACE("invalid message ~p~n", [Msg]),
    {error, invalid_message}.

parse_command(CommandBin, Body) ->
    case catch list_to_existing_atom(
                 string:to_lower(unicode:characters_to_list(CommandBin))) of
        {'EXIT', _} ->
            {error, unknown_command};
        Command ->
            case json:decode(Body) of
                {ok, {Args}} when is_list(Args) ->
                    {ok, Command, Args};
                _Else ->
                    {error, invalid_json}
            end
    end.

handle_command(Addr, 'connection.open', Args, State) ->
    Reply = {"201", [{status, <<"Ready">>}, {profiles, [<<"test">>]}]},
    {ok, Reply, State}.

%% This first variation to avoid an extra case in the main loop
send_reply(_, none, State) ->
    {ok, State};
send_reply(Addr, {Code, Args}, State = #state{ socket = Sock }) ->
    {ok, ArgsBin} = json:encode({Args}),
    ok = erlzmq:send(Sock, Addr, [sndmore]),
    ok = erlzmq:send(Sock, <<>>, [sndmore]),
    ok = erlzmq:send(Sock, iolist_to_binary(Code), [sndmore]),
    ok = erlzmq:send(Sock, ArgsBin),
    {ok, State}.
