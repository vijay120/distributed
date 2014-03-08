
-module(philosopher).
-export([main/1]).


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
                gone        -> goneState(NumForksNeeded, Forks, Neighbours)
                _Else   -> io:format("Error parsing state. ~n")
        end.

joinState(NumForksNeeded, Forks, Neighbours) -> io:format("got to join").

thinkingState(NumForksNeeded, Forks, Neighbours) -> io:format("got to thinking").

hungryState(NumForksNeeded, Forks, Neighbours) -> io:format("got to hungry").

eatingState(NumForksNeeded, Forks, Neighbours) -> io:format("got to eating").

leavingState(NumForksNeeded, Forks, Neighbours) -> io:format("got to leaving").

goneState(NumForksNeeded, Forks, Neighbours) -> io:format("got to gone").
