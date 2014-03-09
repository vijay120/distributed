
-module(philosopher).
-export([main/1]).
-define(TIMEOUT, 2000).

% NOTE: a fork is defined as a tuple with two neighbours and an isClean boolean
% neighbour1 and neighbour2 are encoded via each one's pid.

%main driver of application
main(Params) ->
		try
				%set up network connections
				_ = os:cmd("epmd -daemon"),
				Reg_name = hd(Params),
				Neighbours = tl(Params), % taken as list of neighbours
				io:format("Neighbours are ~p~n", [Neighbours]),
				net_kernel:start([list_to_atom(Reg_name), shortnames]),
				register(philosopher, self()),
				io:format("Registered as ~p at node ~p, currently joining. ~p~n",
								  [philosopher, node(), now()]),
				joinState(0, [], Neighbours)
				% handleMessage(joining, 0, [], Neighbours)
		catch
				_:_ -> io:format("Error parsing command line parameters.~n")
		end,
		halt().

% %handles all messages and does so recursively
% handleMessage(State, NumForksNeeded, Forks, Neighbours) ->
% 		case State of
% 				joining     -> joinState(NumForksNeeded, Forks, Neighbours);
% 				thinking    -> thinkingState(NumForksNeeded, Forks, Neighbours);
% 				hungry      -> hungryState(NumForksNeeded, Forks, Neighbours);
% 				eating      -> eatingState(NumForksNeeded, Forks, Neighbours);
% 				leaving     -> leavingState(NumForksNeeded, Forks, Neighbours); 
% 				% Leaving and gone will be really awkward to do if we don't pass them directly.
% 				% I think it'll be better if we transition directly between states by 
% 				% calling their respective functions...
% 				gone        -> goneState(NumForksNeeded, Forks, Neighbours);
% 				_Else       -> io:format("Error parsing state. ~n")
% 		end.

joinState(NumForksNeeded, Forks, Neighbours) -> 
		io:format("in joining! ~n"),
		io:format("Neighbours are ~p~n", [Neighbours]),
		CanStartThinking = sendIdentifyMessage(Neighbours, 1),
		if 
				CanStartThinking == true -> 
						io:format("go into thinkin! ~n"), 
						thinkingState(NumForksNeeded, Forks, Neighbours);
						% handleMessage(thinking, NumForksNeeded, Forks, Neighbours);
				true -> io:format("nope, someone is higher than me! ~n"), 
						receive
								{ClientPid, identifyRequest} -> ClientPid ! {self(), identifyResponse, joining}
						after ?TIMEOUT -> io:format("Timed out waiting for reply!~n")
						end,
						joinState(NumForksNeeded, Forks, Neighbours)
		end.

% sends identify message to a particular neighbor. If its pid is less than the
% sender's and there are joining neighbours, then we know we can't join yet.
% if it's greater than all its neighbors, stay joining. 
% if it's the only joining node, it can become thinking.
sendIdentifyMessage(Neighbours, CurrCount) ->
		io:format("in sending ~n"),
		if 
				CurrCount =< length(Neighbours) -> 
						ClientNodeName = list_to_atom(lists:nth(CurrCount, Neighbours)), 
						io:format("before"),
						{philosopher, ClientNodeName} ! {self(), identifyRequest},
						io:format("after"),
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

% listens for any identifyRequests, responds with its state. Repeats.
thinkingState(NumForksNeeded, Forks, Neighbours) -> 
		io:format("got to thinking ~n"),
		receive
				{ClientPid, identifyRequest} -> io:format("Identifying self as thinking~n"),
																				ClientPid ! {self(), identifyResponse, thinking},
				 																thinkingState(NumForksNeeded, Forks, Neighbours);
				{_, _, become_hungry} -> io:format("Received message to become hungry!"),
																	hungryState(NumForksNeeded, Forks, Neighbours);
				{ClientPid, Ref, leave} -> leavingState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref);
				Message -> io:format("Couldn't interpret message ~p~n", [Message])
		end.

% If we have all the forks, go to eating. If we don't, request and wait for
% each in turn. Once we have all, go to eating.
hungryState(NumForksNeeded, Forks, Neighbours) -> io:format("got to hungry"),
		if
			length(Forks) == NumForksNeeded ->
				eatingState(NumForksNeeded, Forks, Neighbours);
			true -> % request the forks we don't have.
				AllForks = sendForkRequest(Forks, Neighbours),
				eatingState(NumForksNeeded, AllForks, Neighbours)
		end.

% repeatedly checks a neighbour to see if we have his fork.
% if we don't, wait to receive it. Eventually we will have all the forks
% for every neighbour, in which case we return.
sendForkRequest(Forks, []) ->
		Forks;

sendForkRequest(Forks, Neighbours) ->
		io:format("Requesting forks ~n"),
		FirstNeighbour  = hd(Neighbours),
		RestNeighbours  = tl(Neighbours),
		DoWeHaveFork 		= checkNeighbourInFork(Forks, FirstNeighbour), % returns a list of 
		if 
			DoWeHaveFork ->
				sendForkRequest(Forks, RestNeighbours);
			true -> % if we need the fork, request it and wait to receive it.
							% in theory, we should eventually receive it without needing
							% to worry about timeout or resending the request.
				FirstNeighbour ! {self(), requestFork},
				receive % TODO: Do we have to worry about other messages here too?
					{_, sendFork, Fork} -> % got fork
						io:format("Received fork ~p ~n", [Fork]),
						sendForkRequest([Fork|Forks], RestNeighbours);
					Message ->
						io:format("Received some other message: ~p~n", [Message])
				end
		end.

% sees if we have the fork with a given neighbour. Uses keyfind, which
% checks if an element is in a list of tuples at the given location.
% returns a tuple if true, so we need the nested ifs to make it always
% return a bool.
checkNeighbourInFork(Forks, Neighbour) ->
		case lists:keyfind(Neighbour, 0, Forks) of
			false -> 
				case lists:keyfind(Neighbour, 1, Forks) of
					false -> false;
					_Else -> true
				end;
			_Else ->
				true
			end.

eatingState(NumForksNeeded, Forks, Neighbours) -> io:format("got to eating").

% NOTE: This requires the extra parameters ClientPid and Ref, as we must send
% 			a message to the controller that sent its leave message, with matching refs,
%				once we go to gone.
leavingState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref) -> io:format("got to leaving").

% ClientPid and Ref required to send gone message back to controller that sent
% leaving message.
goneState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref) -> io:format("got to gone"),
										ClientPid ! {Ref, gone}.
