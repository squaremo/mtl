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
    {ok, #state{ context = Context,
                 socket = Socket,
                 command_state = init_command_state() }}.

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
handle_info({zmq, Sock, Data}, State = #state{ command_state = CmdSt }) ->
    ?TRACE("Data ~p~n", [Data]),
    State1 =
        case msg(CmdSt, Data) of
            {command, Cmd} ->
                {ok, Reply, NewState} = handle_command(Cmd, State),
                ?TRACE("Command: ~p~nReply: ~p~n", [Cmd, Reply]),
                send_reply(Reply, NewState),
                NewState#state{ command_state = init_command_state() };
            {more, NewCmdSt} ->
                %% Check that there's more to come -- this won't
                %% work with active, of course.
                %{ok, 1} = erlzmq:getsockopt(Sock, rcvmore),
                State#state{ command_state = NewCmdSt };
            {error, Reason} ->
                State#state{ command_state = init_command_state() }
        end,
    {noreply, State1}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
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

init_command_state() ->
    address.

msg(address, Addr) ->
    {more, {empty, Addr}};
msg({empty, Addr}, <<>>) ->
    {more, {name, Addr}};
msg({name, Addr}, Command) ->
    {more, {body, Addr, Command}};
msg({body, Addr, Command}, Body) ->
    {command, command(Addr, Command, Body)};
msg(_, Msg) ->
    ?TRACE("invalid message ~p~n", [Msg]),
    {error, invalid_message}.

command(Addr, Name0, Body) ->
    Name = string:to_lower(unicode:characters_to_list(Name0)),
    {Addr, Name, Body}.

handle_command({Addr, "connection.open", Body}, State) ->
    Reply = {Addr, "201",
             "{\"status\":\"Ready\",\"profiles\":[\"test\"]}"},
    {ok, Reply, State}.

send_reply({Addr, Code, Body}, State = #state{ socket = Sock }) ->
    ok = erlzmq:send(Sock, Addr, [sndmore]),
    ok = erlzmq:send(Sock, <<>>, [sndmore]),
    ok = erlzmq:send(Sock, iolist_to_binary(Code), [sndmore]),
    ok = erlzmq:send(Sock, iolist_to_binary(Body)),
    {ok, State}.
