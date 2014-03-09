
-module(philosopher).
-export([main/1]).
-define(TIMEOUT, 2000).

%main driver of application
main(Params) ->
        try
                %set up network connections
                _ = os:cmd("epmd -daemon"),
                Reg_name = hd(Params),
                Neighbours = tl(Params), % taken as list of neighbours
                net_kernel:start([list_to_atom(Reg_name), shortnames]),
                register(philosopher, self()),
                io:format("Registered as ~p at node ~p, currently joining. ~p~n",
                                  [philosopher, node(), now()]),
                handleMessage(joining, 0, [], Neighbours)
        catch
                _:_ -> io:format("Error parsing command line parameters.~n")
        end,
        halt().

%handles all messages and does so recursively
handleMessage(State, NumForksNeeded, Forks, Neighbours) ->
        case State of
                joining     -> joinState(NumForksNeeded, Forks, Neighbours);
                thinking    -> thinkingState(NumForksNeeded, Forks, Neighbours);
                hungry      -> hungryState(NumForksNeeded, Forks, Neighbours);
                eating      -> eatingState(NumForksNeeded, Forks, Neighbours);
                leaving     -> leavingState(NumForksNeeded, Forks, Neighbours);
                gone        -> goneState(NumForksNeeded, Forks, Neighbours);
                _Else       -> io:format("Error parsing state. ~n")
        end.

joinState(NumForksNeeded, Forks, Neighbours) -> 
        io:format("in joining!"),
        io:format(Neighbours),
        Boolval = sendIdentifyMessage(Neighbours, 1),
        if 
                Boolval == true -> 
                        io:format("go into thinkin!"), 
                        handleMessage(thinking, NumForksNeeded, Forks, Neighbours);
                true -> io:format("nope, someone is higher than me!"), 
                        receive
                                {ClientPid, identifyRequest} -> ClientPid ! {self(), identifyResponse, joining}
                        after ?TIMEOUT -> io:format("Timed out waiting for reply!\n")
                        end,
                        joinState(NumForksNeeded, Forks, Neighbours)
        end.

sendIdentifyMessage(Neighbours, CurrCount) ->
        io:format("in sendin"),
        if 
                CurrCount =< length(Neighbours) -> 
                        ClientPid = lists:nth(Neighbours, CurrCount), 
                        ClientPid ! {self(), identifyRequest},
                        receive
                                {ClientPid, identifyResponse, joining} -> 
                                        if
                                                ClientPid < self() -> false;
                                                true -> sendIdentifyMessage(Neighbours, CurrCount+1)
                                        end;
                                {ClientPid, identifyResponse, _} -> sendIdentifyMessage(Neighbours, CurrCount+1)       
                        end;
                true -> true
        end.

thinkingState(NumForksNeeded, Forks, Neighbours) -> 
        io:format("got to thinking"),
        receive
                {ClientPid, identifyRequest} -> ClientPid ! {self(), identifyResponse, thinking}, thinkingState(NumForksNeeded, Forks, Neighbours)
        end.

hungryState(NumForksNeeded, Forks, Neighbours) -> io:format("got to hungry").

eatingState(NumForksNeeded, Forks, Neighbours) -> io:format("got to eating").

leavingState(NumForksNeeded, Forks, Neighbours) -> io:format("got to leaving").

goneState(NumForksNeeded, Forks, Neighbours) -> io:format("got to gone").
