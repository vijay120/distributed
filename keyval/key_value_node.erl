-module(key_value_node).
-export([main/1, storage_process/1, is_my_process/3]).
-define(TIMEOUT, 2000).

storage_process(_) -> % TODO change when we use Pid
	%io:format("storageTable is ~p~n", [Pid]),
	Table = ets:new(storage_table, []),
	receive 
		{Pid, Ref, store, Key, Value} -> 
			case ets:lookup(Table, Key) of
				[] -> 	io:format("I am empty"),
						ets:insert(Table, {Key, Value}),
						Pid ! {Ref, stored, no_value}; % These have to be banged back the way, I think.
				[{Key, OldVal}] -> 	io:format("I am not empty"),
									ets:insert(Table, {Key, Value}), 
									Pid ! {Ref, stored, OldVal} % These have to be banged back the way, I think.
			end
end.

% Generates all possible node names based on the number of storage processes.
generate_node_nums(0) -> [0];
generate_node_nums(NumStorageProcesses) -> 
	[NumStorageProcesses] ++ generate_node_nums(NumStorageProcesses-1).

list_exponentials(0) -> [];
list_exponentials(NumStorageProcesses) ->						
	[NumStorageProcesses] ++ list_exponentials(NumStorageProcesses div 2). % div forces integer division

% get_closest_neighbour_to_prev(EnteringNodeNum, PrevNodeNum, NodesInNetwork, NumStorageProcesses) ->
% 	% generate all neighbors to EnteringNodeNum mod NumStorageProcesses.
% 	% If PrevNodeNum is in this list, return it.
% 	% Otherwise, return the greatest node num less than PrevNodeNum.
% 	% If no such value exists, return the greatest valued node neighbor.+1 needed because before we made it 2^m-1
% 	ListExps = list_exponentials((NumStorageProcesses+1) div 2), % generates 1,2,4,8...NumStorageProcesses/2
% 	io:format("ListExps is: ~p~n", [ListExps]),
% 	PossibleNeighbours = lists:map(fun(X) -> (X + EnteringNodeNum) rem NumStorageProcesses end, ListExps),
% 	io:format("PossibleNeighbours are: ~p~n", [PossibleNeighbours]),
% 	NeighboursInNetwork = lists:filter(fun(X) -> lists:member(X, NodesInNetwork) end, PossibleNeighbours),
% 	io:format("The neighbors in the network are: ~p~n", [NeighboursInNetwork]),
% 	get_previous_node(EnteringNodeNum, NeighboursInNetwork).


% Given an entering node number and the next node number, returns a list of all storage processes
% numbered between the two. Is kind of complicated due to wrap-around on mod.
calc_storage_processes(EnteringNodeNum, NextNodeNum, NumStorageProcesses) % terminate when we have all our processes
	when EnteringNodeNum == NextNodeNum -> [];
calc_storage_processes(EnteringNodeNum, NextNodeNum, NumStorageProcesses) % case of having to wrap around
	when EnteringNodeNum == NumStorageProcesses -> [EnteringNodeNum] ++ calc_storage_processes(0,NextNodeNum, NumStorageProcesses);
calc_storage_processes(EnteringNodeNum, NextNodeNum, NumStorageProcesses) ->
	[EnteringNodeNum] ++ calc_storage_processes(EnteringNodeNum+1, NextNodeNum, NumStorageProcesses).

% Helper function for calc_storage_neighbours.
% For every element in EnteringStorageProcesses, add every element of ListExps
% in turn. Append them all together as a list (which will have duplicates).
get_storage_neighbours(EnteringStorageProcesses, ListExps, NumStorageProcesses) ->
	if 
		EnteringStorageProcesses == [] -> [];
		true -> lists:map(fun(X) -> (hd(EnteringStorageProcesses) + X) rem (NumStorageProcesses+1) end, ListExps) ++ get_storage_neighbours(tl(EnteringStorageProcesses), ListExps, NumStorageProcesses)
	end.

% Calculates the storage process for a given node.
calc_storage_neighbours(EnteringStorageProcesses, NumStorageProcesses) ->
	ListExps = list_exponentials((NumStorageProcesses+1) div 2),
	io:format("ListExps are: ~p~n", [ListExps]),
	lists:usort(get_storage_neighbours(EnteringStorageProcesses, ListExps, NumStorageProcesses)). % usort removes duplicates

%Get the greatest storage process less than our smallest if it exists;
%		otherwise get the highest valued one. (To deal with mod)
% If the previous node is a neighbour, just go right to it.
get_closest_neighbour_to_prev(EnteringNodeNum, PrevNodeNum, AllStorageNeighbours, NumStorageProcesses) ->
	AllNeighboursSorted = lists:sort(AllStorageNeighbours),
	case lists:member(PrevNodeNum, AllNeighboursSorted) of
		true -> PrevNodeNum;
		_Else ->	SmallerNeighbours = lists:filter(fun(X) -> X < EnteringNodeNum end, AllStorageNeighbours),
				if
					SmallerNeighbours == [] -> lists:last(AllNeighboursSorted);
					true 					-> lists:last(SmallerNeighbours)
				end
	end.

% Given a storage process number and list of nodes (as ints), find the node
% that the storage process is on. It is the greatest node less than the
% storage process number; if that's none, it's just the greatest node.
node_from_storage_process(StorageProcessNum, NodesInNetwork) ->
	SmallerNodes = lists:filter(fun(X) -> X =< StorageProcessNum end, NodesInNetwork),
	if
		SmallerNodes == [] -> lists:last(NodesInNetwork);
		true			   -> lists:last(SmallerNodes)
	end.


% Send a message to TargetNode from our current node.
request_storage_tables(EnteringNodeNum, TargetNodeNum, NumStorageProcesses, Message) ->
	NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
	NextNodeNum = get_next_node(EnteringNodeNum, NodesInNetwork),
	% PrevNodeNum = get_previous_node(EnteringNodeNum, NodesInNetwork),

	EnteringNode = lists:concat(["Node", integer_to_list(EnteringNodeNum)]),
	NextNode = lists:concat(["Node", integer_to_list(NextNodeNum)]),
	% PrevNode = lists:concat(["Node", integer_to_list(PrevNodeNum)]),

	% NOTE: PROCESS
	% 1. Determine storage processes that should be on the entering node.
	% 2. Calculate all of these processes' neighbors.
	% 3. Get the greatest storage process less than our smallest if it exists;
	%		otherwise get the highest valued one. (To deal with mod)
	% 4. Determine the node that storage process is in.
	% 5. Send message via global:send to that node.

	% 1.
	EnteringStorageProcesses = calc_storage_processes(EnteringNodeNum, NextNodeNum, NumStorageProcesses),% storage processes on our entering node
	io:format("EnteringStorageProcesses are: ~p~n", [EnteringStorageProcesses]),

	% 2.
	AllStorageNeighbours = calc_storage_neighbours(EnteringStorageProcesses, NumStorageProcesses),
	io:format("AllStorageNeighbours are: ~p~n", [AllStorageNeighbours]),

	% 3.
	ClosestStorageNeighbourNum = get_closest_neighbour_to_prev(EnteringNodeNum, TargetNodeNum, AllStorageNeighbours, NumStorageProcesses),
	io:format("ClosestStorageNeighbourNum is: ~p~n", [ClosestStorageNeighbourNum]),

	% 4. 
	ClosestNodeNeighbourNum = node_from_storage_process(ClosestStorageNeighbourNum, NodesInNetwork),
	io:format("ClosestNodeNeighbourNum is: ~p~n", [ClosestNodeNeighbourNum]),
	
	ClosestNeighbour = lists:concat(["Node", integer_to_list(ClosestNodeNeighbourNum)]),

	% 5.
	io:format("Sending message to: ~p~n", [ClosestNeighbour]),
	global:send(ClosestNeighbour, Message).

% TODO: Make sure these are properly handling NumStorageProcesses as 2^m or (2^m)-1.
hash(Key, NumStorageProcesses) -> lists:foldl(fun(X, Acc) -> X+Acc end, 0, Key) rem NumStorageProcesses.


find_all_nodes(PossibleId, Accin, Maximum) ->
	global:sync(),
	GlobalTable = global:registered_names(),
	%io:format("Registered table is: ~p~n", [GlobalTable]), % connect to the network.
	if PossibleId > Maximum -> Accin;
		true -> ConstructName = lists:concat(["Node", integer_to_list(PossibleId)]),
				case global:whereis_name(ConstructName) of
					undefined -> find_all_nodes(PossibleId+1, Accin, Maximum);
					_ -> find_all_nodes(PossibleId+1, lists:concat([Accin, [PossibleId]]), Maximum)
				end
end.


indexAt(Array, IndexAt, Value) ->
	if IndexAt > length(Array) -> -1;
		true -> case lists:nth(IndexAt, Array) == Value of 
					true -> IndexAt;
					false -> indexAt(Array, IndexAt+1, Value)
				end
			end.


is_my_process(NodeId, ProcessId, NumStorageProcesses) ->	
	PossibleIDs = find_all_nodes(0, [], NumStorageProcesses-1),
	%PossibleIDs = [3, 10, 12],
	IndexAt = indexAt(PossibleIDs, 1, NodeId),
	if IndexAt == length(PossibleIDs) -> 
		IDIsGreaterThanLast = (ProcessId >= NodeId) and (ProcessId < NumStorageProcesses),
		IDIsLesserThanLast = (ProcessId >= 0) and (ProcessId < lists:nth(1, PossibleIDs)),
		%io:format("greater is ~p and less than is ~p", [IDIsGreaterThanLast], [IDIsLesserThanLast]),
		case IDIsGreaterThanLast or IDIsLesserThanLast of
			true -> true;
			false -> false
		end;

		true -> 
			NextNode = lists:nth(IndexAt+1, PossibleIDs),
			case (ProcessId >= NodeId) and (ProcessId < NextNode) of
				true -> true;
				false -> false
			end
		end.


% Given the number of our current node and a sorted list of all node numbers in
% the network, return the number of the previous node.
% Returns either the greatest value less than it if it exists,
% or the greatest value in the list.
get_previous_node(NodeNum, ListNodeNums) -> 
	% try and find greatest less than it. If none less than it, find highest valued node.
	LesserNodes = lists:filter(fun(X) -> X < NodeNum end, ListNodeNums),
	if 
		LesserNodes /= [] -> lists:last(LesserNodes);
		%lists:concat(["Node", integer_to_list(lists:last(LesserNodes))]);
		true -> lists:last(ListNodeNums)
		%lists:concat(["Node", integer_to_list(lists:last(ListNodeNums))])
	end.

% We know the number of our current node (NodeNum), return the string
% in the global registry of the node after it.
% This is either the smallest node greater than it or the smallest node of all
% nodes.
get_next_node(NodeNum,ListNodeNums) -> 
	GreaterNodes = lists:filter(fun(X) -> X > NodeNum end, ListNodeNums),
	if
		GreaterNodes /= [] -> lists:nth(1, GreaterNodes);
		%lists:concat(["Node", integer_to_list(lists:nth(1, GreaterNodes))]);
		true -> lists:nth(1, ListNodeNums)
		%lists:concat(["Node", integer_to_list(lists:nth(1, ListNodeNums))])
	end.

% Node adds itself to the network, gets its storage processes (and facilitates
% all other rebalancing).

% NOTE: All the "nodes" mentioned below are actually just the number they are
% registered as. E.x., "Node1" = 1 below.
% ALSO: NumStorageProcesses is presumed to be (2^m)-1.
enter_network(NodeInNetwork, NumStorageProcesses) ->
	net_kernel:connect_node(NodeInNetwork),
	
	global:sync(),

	% Select our node to register as.
	NodesInNetworkList = find_all_nodes(0, [], NumStorageProcesses), % a sorted list TODO see if it's sorted sensibly
	io:format("Our sorted list is: ~p~n", [NodesInNetworkList]),
	NodesInNetworkSet = ordsets:from_list(NodesInNetworkList),
	AllNodes = ordsets:from_list(generate_node_nums(NumStorageProcesses)),
	NodesAvailable = ordsets:to_list(ordsets:subtract(AllNodes, NodesInNetworkSet)),
	% io:format("The available nodes are: ~p~n", [NodesAvailable]),
	RandomVal = random:uniform(length(NodesAvailable)),
	RandomFreeNodeNum = lists:nth(RandomVal, NodesAvailable),
	RandomFreeNode = lists:concat(["Node", integer_to_list(RandomFreeNodeNum)]),
	io:format("Random free node is: ~p~n", [RandomFreeNode]),

	PreviousNodeNum = get_previous_node(RandomFreeNodeNum, NodesInNetworkList),
	NextNodeNum = get_next_node(RandomFreeNodeNum, NodesInNetworkList),

	io:format("Previous Node is: ~p~n", [PreviousNodeNum]),
	io:format("Next Node is: ~p~n", [NextNodeNum]),

	% send message that can be transferred onwards:
	% {sender (i.e. self()), requestStorageTables (atom), original node, target node}
	% chill then knows whether to call request_storage_tables with the updated stuff
	RequestStorageTablesMsg = {self(), requestStorageTables, RandomFreeNodeNum, PreviousNodeNum},

	request_storage_tables(RandomFreeNodeNum, PreviousNodeNum, NumStorageProcesses, RequestStorageTablesMsg), % send a message from RandomFreeNode to
																  % previous node requesting all
																  % storage processes from r to next.

	global:register_name(RandomFreeNode, self()),
	{RandomFreeNodeNum, RandomFreeNode}. % do things before registering us.
	
	%io:format("Registered table is: ~p~n", [GlobalTable]). % connect to the network.

main(Params) ->
		%set up network connections
		_ = os:cmd("epmd -daemon"),
		{NumArg, _ } = string:to_integer(hd(Params)),
		NumStorageProcesses = trunc(math:pow(2, NumArg)), 
		RegName = hd(tl(Params)),
		net_kernel:start([list_to_atom(RegName), shortnames]),
		register(node, self()),
		io:format("Registered as ~p at node ~p. ~p~n",
						  [node, node(), now()]),
		case length(Params) of
			2 -> GlobalNodeName = lists:concat(["Node", integer_to_list(0)]),
				 CurrentNodeID = 0,
				 DoesRegister = global:register_name(GlobalNodeName, self()),
				 io:format("Does it register? ~p~n", [DoesRegister]),	
				 spawn_tables(NumStorageProcesses-1),
				 GlobalTable = global:registered_names(),
				 io:format("Registered table is: ~p~n", [GlobalTable]),
				 processMessages(NumStorageProcesses, CurrentNodeID),
				 chill(CurrentNodeID, GlobalNodeName, NumStorageProcesses-1);
				 % processMessages(NumStorageProcesses, CurrentNodeID);
			3 -> NodeInNetwork = list_to_atom(hd(tl(tl(Params)))), % third parameter
				 % CurrentNodeID = list_to_atom(NodeInNetwork),
				 %process_messages(NumStorageProcesses, CurrentNodeID),
				 % io:format("NodeInNetwork is: ~p~n", [NodeInNetwork]),
				 {OurNodeNum, OurNode} = enter_network(NodeInNetwork, NumStorageProcesses-1),
				 chill(OurNodeNum, OurNode, NumStorageProcesses-1);
			_Else -> io:format("Error: bad arguments (too few or too many) ~n"),
					  halt()
		end,
		halt().

% Handle message routing for requestTables. Pass it along if you're not
% the intended recipient, otherwise somehow actually transfer the
% storage processes themselves to the successor.
chill(OurNodeNum, OurNode, NumStorageProcesses) -> 
	receive
		{Pid, requestStorageTables, OriginalNodeNum, DestinationNodeNum} -> 
			if 
				OurNodeNum == DestinationNodeNum -> % send message to storage processes on this node.
													% receive tables back. Send table via global:send
													% to OriginalNodeNum.
						OurStorageProcessNums = calc_storage_processes(DestinationNodeNum, OriginalNodeNum, NumStorageProcesses),
						OurStorageProcessNames = lists:map(fun(X) -> lists:concat(["Storage", integer_to_list(X)]) end, OurStorageProcesses),
						lists:map(fun(X) -> global:send(X, TODOMESSAGETYPE) end, OurStorageProcessNames),
						io:format("Got the message! We should send the proper storage processes data via global:send ");
				true -> io:format("Not for us! Passing it along to: ~p~n", [DestinationNodeNum]),
						request_storage_tables(OurNodeNum, DestinationNodeNum, NumStorageProcesses, {self(), requestStorageTables, OriginalNodeNum, DestinationNodeNum})
			end;
		_ -> io:format("Received...something? ~n")
	end,
	chill(OurNodeNum,OurNode,NumStorageProcesses).

process_messages(NumStorageProcesses, CurrentNodeID) ->
		io:format("in process messages"),
		receive 
			{Pid, Ref, store, Key, Value} -> 
				io:format("received key: ~p", [Key]),
				ProspectiveStorageTable = hash(Key, NumStorageProcesses),
				case is_my_process(CurrentNodeID, ProspectiveStorageTable, NumStorageProcesses) of
					true -> 
						io:format("This is true"),
						ConstructedStorageProcess = lists:concat(["Storage", integer_to_list(ProspectiveStorageTable)]),
						io:format("Storage process is ~p", [ConstructedStorageProcess]),
						global:send(ConstructedStorageProcess, {self(), make_ref(), store, Key, Value}),
						process_storage_reply_messages(Pid, Ref);
					false -> io:format("I will deal with this case later")
				end;
			_ -> io:format("IN some other message")
		end.

process_storage_reply_messages(OldPid, OldRef) ->
	receive
		{Ref, stored, no_value} -> 
					io:format("I am exiting with no value"),
					OldPid ! {OldRef, stored, no_value};
		{Ref, stored, OldVal} -> 
					io:format("I am exiting with old value"),
					OldPid ! {OldRef, stored, OldVal}
	end.


spawn_tables(NumTables) ->
	if NumTables < 0
		-> true;
		true ->
			%io:format("Num tables is ~p~n", [NumTables]),
			SpawnPID = spawn(key_value_node, storage_process, [NumTables]),
			SpawnName = lists:concat(["Storage", integer_to_list(NumTables)]),
			global:register_name(SpawnName, SpawnPID),
			spawn_tables(NumTables-1)
	end.
