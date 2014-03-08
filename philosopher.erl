
-module(philosopher).
-export([main/1]).


%main driver of application
main(Reg_name) ->
        try
                %set up network connections
                _ = os:cmd("epmd -daemon"),
                net_kernel:start([list_to_atom(Reg_name), shortnames]),
                register(philosopher, self()),
                io:format(node()),
                handleMessage()
        catch
                _:_ -> io:format("Error parsing command line parameters.~n")
        end,
        halt().

%handles all messages and does so recursively
handleMessage() ->
        receive
                {ClientPid, Word} -> io:format(Word), ClientPid ! {self(), Word}, handleMessage();
                SomeMessage -> io:format(SomeMessage)
        end.