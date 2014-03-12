% TODO: HANDLE REQUEST FORK AND CREATEFORK IN THINKING, HUNGRY, EATING.


-module(philosopher).
-export([main/1]).
-define(TIMEOUT, 2000).

% NOTE: a fork is defined as a tuple with two neighbours and an isClean boolean
% neighbour1 and neighbour2 are encoded via each one's pid.

%main driver of application
main(Params) ->
		% try
				%set up network connections
				_ = os:cmd("epmd -daemon"),
				Reg_name = hd(Params),
				Neighbours = lists:map(fun(X) -> list_to_atom(X) end, tl(Params)), 
				% taken as list of neighbours, converted to atoms
				io:format("Neighbours are ~p~n", [Neighbours]),
				net_kernel:start([list_to_atom(Reg_name), shortnames]),
				register(philosopher, self()),
				io:format("Registered as ~p at node ~p, currently joining. ~p~n",
								  [philosopher, node(), now()]),
				joinState(length(Neighbours), [], Neighbours),
				% handleMessage(joining, 0, [], Neighbours)
		%catch
		%		_:_ -> io:format("Error parsing command line parameters.~n")
		%end,
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

% Sends identify requests to all neighbours. Receives their responses.
% Tells hungry, thinking, or eating nodes to create forks with it.
% Otherwise, it will join the network once it has the lowest pid of its joining
% neighbours.

% TODO: We need to update numforksneeded when we sendCreateFork()
joinState(NumForksNeeded, Forks, Neighbours) -> 
		io:format("in joining! ~n"),
		io:format("Neighbours are ~p~n", [Neighbours]),
		CanStartThinking = sendIdentifyMessage(Forks, Neighbours, 1),
		if 
				CanStartThinking == true -> 
						io:format("About to become thinking~n"), 
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
sendIdentifyMessage(Forks, Neighbours, CurrCount) ->
		io:format("in sending ~n"),
		if 
				CurrCount =< length(Neighbours) -> 
						ClientNodeName = lists:nth(CurrCount, Neighbours), 
						io:format("before"),
						{philosopher, ClientNodeName} ! {self(), identifyRequest},
						io:format("after"),
						receive
								{ClientPid, identifyResponse, joining} -> 
										if
												ClientPid < self() -> false;
												true -> sendIdentifyMessage(Forks, Neighbours, CurrCount+1)
										end; % otherwise if it's hungry, thinking, or eating create a fork with it
								{ClientPid, identifyResponse, thinking} -> sendCreateFork(Forks, Neighbours, ClientPid),
																													 sendIdentifyMessage(Forks, Neighbours, CurrCount+1);
								{ClientPid, identifyResponse, hungry}   -> sendCreateFork(Forks, Neighbours, ClientPid),
																													 sendIdentifyMessage(Forks, Neighbours, CurrCount+1);
								{ClientPid, identifyResponse, eating}   -> sendCreateFork(Forks, Neighbours, ClientPid),
																												   sendIdentifyMessage(Forks, Neighbours, CurrCount+1);
								{_, identifyResponse, _} -> sendIdentifyMessage(Forks, Neighbours, CurrCount+1)       
						end;
				true -> true
		end.

% Check if the fork already exists with that neighbor. If not, create it by
% sending appropriate message.
sendCreateFork(Forks, Neighbours, ClientPid) ->
		io:format("in sendCreateFork! ~n"),
		IsNeighbourInFork = checkNeighbourInFork(Forks, Neighbours),
		if IsNeighbourInFork == false ->
			ClientPid ! {self(), createFork}
		end.

% listens for messages, responds appropriately. Repeats.
thinkingState(NumForksNeeded, Forks, Neighbours) -> 
		io:format("got to thinking: numforks, forks, neighbours ~p~p~p~n", [NumForksNeeded, Forks, Neighbours]),
		receive
				{ClientPid, identifyRequest} -> io:format("Identifying self as thinking~n"),
																				ClientPid ! {self(), identifyResponse, thinking},
				 																thinkingState(NumForksNeeded, Forks, Neighbours);
				{ClientPid, createFork} -> % see if we need to create the fork. We could get multiple such requests
																	 [NewNumForksNeeded, NewForks, NewNeighbours] = createFork(NumForksNeeded,
																	 																													 Forks, Neighbours,
																	 																													 ClientPid),
																	 thinkingState(NewNumForksNeeded, NewForks, NewNeighbours);
				{ClientPid, requestFork} -> % always send fork
					io:format("Received request for fork from ~p~n", [node(ClientPid)]),
					case findFork(Forks, node(ClientPid)) of % if we have the fork, send it.
						false -> thinkingState(NumForksNeeded, Forks, Neighbours);
						Fork ->
							CleanedFork = {element(1, Fork), element(2, Fork), true},
							ClientPid ! {self(), sendFork, CleanedFork},
							NewSetOfForks = lists:delete(Fork, Forks),
							thinkingState(NumForksNeeded, NewSetOfForks, Neighbours)
					end;
				{ClientPid, Ref, become_hungry} -> io:format("Received message to become hungry!~n"),
																	hungryState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref);
				{ClientPid, Ref, leave} -> leavingState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref);
				{ClientPid, leaving} -> io:format("Received message that node ~p is leaving ~n", [node(ClientPid)]),
																[NewNumForksNeeded, NewForks, NewNeighbours] = deleteForkFromPid(NumForksNeeded, Forks, Neighbours, ClientPid),
																thinkingState(NewNumForksNeeded, NewForks, NewNeighbours);
				Message -> io:format("Couldn't interpret message ~p~n", [Message]) % TODO: REMOVE?
		end.

% Sees if we have a fork with a given neighbour. If not, creates it and adds
% that node to our list of neighbours.
createFork(NumForksNeeded, Forks, Neighbours, ClientPid) ->
	 io:format("Creating fork!~n"),
	 DoWeHaveFork = checkNeighbourInFork(Forks, node(ClientPid)),
	 if
	 	 DoWeHaveFork == false -> 
	 	 	NewFork = {node(self()), node(ClientPid), true},
	 	 	[NumForksNeeded+1, [NewFork|Forks], [node(ClientPid)|Neighbours]];
		true ->
			[NumForksNeeded, Forks, Neighbours]
		end.

% If we have all the forks, go to eating. If we don't, request and wait for
% each in turn. Once we have all, go to eating.
% First we listen for any existing messages to identify, create, or request
% forks from us. We do this first so that we never hold on to a fork that someone
% else has priority on.
hungryState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref) -> io:format("got to hungry~n"),
		receive
			{ReceiverClientPid, identifyRequest} -> io:format("Identifying self as hungry~n"),
																	ReceiverClientPid ! {self(), identifyResponse, hungry},
																	hungryState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref);
			{ReceiverClientPid, createFork} -> % see if we need to create the fork. We could get multiple such requests
															 [NewNumForksNeeded, NewForks, NewNeighbours] = createFork(NumForksNeeded,
															 																													 Forks, Neighbours,
															 																													 ReceiverClientPid),
															 hungryState(NewNumForksNeeded, NewForks, NewNeighbours, ClientPid, Ref);
			{ReceiverClientPid, Ref, leave} -> leavingState(NumForksNeeded, Forks, Neighbours, ReceiverClientPid, Ref);
			{ReceiverClientPid, leaving} ->
																io:format("Received message that node ~p is leaving ~n", [node(ReceiverClientPid)]),
																[NewNumForksNeeded, NewForks, NewNeighbours] = deleteForkFromPid(NumForksNeeded, Forks, Neighbours, ReceiverClientPid),
																hungryState(NewNumForksNeeded, NewForks, NewNeighbours, ClientPid, Ref);
			{ReceiverClientPid, requestFork} -> % someone wants our fork.
																				% we must give it to them if the fork
																				% is dirty.
				io:format("Received request for fork from ~p~n", [node(ReceiverClientPid)]),
				case findFork(Forks, node(ClientPid)) of
					false -> hungryState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref);
					Fork ->
						if element(3, Fork) == false -> % if dirty, send fork
								CleanedFork = {element(1, Fork), element(2, Fork), true},
								ReceiverClientPid ! {self(), sendFork, CleanedFork},
								NewSetOfForks = lists:delete(Fork, Forks),
								hungryState(NumForksNeeded, NewSetOfForks, Neighbours, ClientPid, Ref);
							true -> hungryState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref)
						end
				end
		after ?TIMEOUT -> 
				if
					length(Forks) == NumForksNeeded ->
						eatingState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref);
					true -> % request the forks we don't have.
						AllForks = sendForkRequest(Forks, Neighbours, ClientPid, Ref),
						hungryState(NumForksNeeded, AllForks, Neighbours, ClientPid, Ref) % in case we have to give up forks
				end
		end.

% repeatedly checks a neighbour to see if we have his fork.
% if we don't, wait to receive it. Eventually we will have all the forks
% for every neighbour, in which case we return.
sendForkRequest(Forks, [], _, _) ->
		Forks;

sendForkRequest(Forks, Neighbours, ClientPid, Ref) ->
		io:format("Requesting forks ~n"),
		FirstNeighbour  = hd(Neighbours),
		RestNeighbours  = tl(Neighbours),
		DoWeHaveFork 		= checkNeighbourInFork(Forks, FirstNeighbour),
		if 
			DoWeHaveFork ->
				sendForkRequest(Forks, RestNeighbours, ClientPid, Ref);
			true -> % if we need the fork, request it and wait to receive it.
							% in theory, we should eventually receive it without needing
							% to worry about timeout or resending the request.
				{philosopher, FirstNeighbour} ! {self(), requestFork},
				receive 
					{_, sendFork, Fork} -> % got fork
						io:format("Received fork ~p ~n", [Fork]),
						sendForkRequest([Fork|Forks], RestNeighbours, ClientPid, Ref)
					after ?TIMEOUT ->
						sendForkRequest(Forks, Neighbours, ClientPid, Ref)
				end
		end.

% Finds the fork with a given neighbour, returning it or False.
findFork(Forks, Neighbour) ->
		io:format("In findFork! ~n"),
		io:format("Current forks and neighbour: ~p ~p~n", [Forks, Neighbour]),
		case lists:keyfind(Neighbour, 1, Forks) of
			false ->
				case lists:keyfind(Neighbour, 2, Forks) of
					false -> false;
					Fork  -> Fork
				end;
			Fork ->
				Fork
			end.

% sees if we have the fork with a given neighbour. Uses keyfind, which
% checks if an element is in a list of tuples at the given location.
% returns a tuple if true, so we need the nested ifs to make it always
% return a bool.
checkNeighbourInFork(Forks, Neighbour) ->
		io:format("In checkNeighbourInFork!~n"),
		io:format("Forks are: ~p~n", [Forks]),
		io:format("Neighbour is: ~p~n", [Neighbour]),
		if 
			Forks == [] ->
				false;
			true ->
				case lists:keyfind(Neighbour, 1, Forks) of
					false -> 
						io:format("keyfinds working?~n"),
						case lists:keyfind(Neighbour, 2, Forks) of
							false -> 
								io:format("We should get here?~n"),
								false;
							_Else -> true
						end;
					_Else ->
						true
					end
		end.

% Sends message to controller that made it hungry saying we are now eating.
% Then waits for a stop_eating request or an identifyRequest.
eatingState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref) -> io:format("got to eating~n"),
		io:format("Before ~n"),
		io:format("The forks are: ~p~n", [Forks]),
		DirtyForks = lists:map(fun(X) -> {element(1, X), element(2, X), false} end, Forks), % dirty forks
		io:format("After ~n"),

		ClientPid ! {Ref, eating}, % sent to controller that transitioned hungry
																						 % TODO: currently might be sent more than once.
		receive
			{ReceiverClientPid, identifyRequest} -> io:format("Identifying self as eating~n"),
																			ReceiverClientPid ! {self(), identifyResponse, eating},
																			eatingState(NumForksNeeded, DirtyForks, Neighbours, ClientPid, Ref);
			{ReceiverClientPid, createFork} -> % see if we need to create the fork. We could get multiple such requests
																 [NewNumForksNeeded, NewForks, NewNeighbours] = createFork(NumForksNeeded,
																 																													 DirtyForks, Neighbours,
																 																													 ReceiverClientPid),
																 eatingState(NewNumForksNeeded, NewForks, NewNeighbours, ClientPid, Ref);
			{ReceiverClientPid, ReceiverRef, leave} -> leavingState(NumForksNeeded, Forks, Neighbours, ReceiverClientPid, ReceiverRef);
			{ReceiverClientPid, leaving} -> io:format("Received message that node ~p is leaving ~n", [node(ReceiverClientPid)]),
																[NewNumForksNeeded, NewForks, NewNeighbours] = deleteForkFromPid(NumForksNeeded, Forks, Neighbours, ReceiverClientPid),
																eatingState(NewNumForksNeeded, NewForks, NewNeighbours, ClientPid, Ref);
			{_, requestFork} -> eatingState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref);
			{_, _, stop_eating} -> io:format("No longer hungry~n"),
																			thinkingState(NumForksNeeded, DirtyForks, Neighbours)
		end.

% Deletes the fork with clientPid, if it exists. If so, it also decrements
% numForksNeeded and removes node(ClientPid) from Neighbours.
deleteForkFromPid(NumForksNeeded, Forks, Neighbours, ClientPid) ->
	DoWeHaveFork = checkNeighbourInFork(Forks, node(ClientPid)),
	if
		 DoWeHaveFork -> % if we have the fork
			case lists:keyfind(node(ClientPid), 1, Forks) of
				false -> ForkToDelete = lists:keyfind(node(ClientPid), 2, Forks);
				Fork ->  ForkToDelete = Fork % one of these two must get it
			end,
			NewForks = lists:delete(ForkToDelete, Forks),
			NewNeighbours = lists:delete(node(ClientPid), Neighbours),
			[NumForksNeeded-1, NewForks, NewNeighbours];
		true -> 
			NewNeighbours = lists:delete(node(ClientPid), Neighbours),
			[NumForksNeeded-1, Forks, NewNeighbours] % we didn't have fork, just return as is.
		end.

% NOTE: This requires the extra parameters ClientPid and Ref, as we must send
% 			a message to the controller that sent its leave message, with matching refs,
%				once we go to gone.
leavingState(NumForksNeeded, _, Neighbours, ClientPid, Ref) -> io:format("got to leaving~n"),
		lists:map(fun(X) -> {philosopher, X} ! {self(), leaving} end, Neighbours),
		goneState(NumForksNeeded, [], Neighbours, ClientPid, Ref).

% ClientPid and Ref required to send gone message back to controller that sent
% leaving message.
goneState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref) -> io:format("got to gone~n"),
										ClientPid ! {Ref, gone},
										goneState(NumForksNeeded, Forks, Neighbours, ClientPid, Ref).
