-module(key_value_node).
-export([main/1, storage_process/1, is_my_process/3]).
-define(TIMEOUT, 2000).

% TODO EOIN: Monitor and deal with leaving node.
% TODO EOIN: Deregister node on duplicate and reregister.
% TODO EOIN: Send message for the new node's predecessor to delete its storage table
%			 duplicates.

% NOTE VIJAY: I made it also take its own process number. 
% This was so it could respond with it so a new node knows
% when it receives a table which process it should be registered as.
storage_process_helper(Table, StorageID) ->
	receive 
		{Pid, Ref, store, Key, Value} -> 
			case ets:lookup(Table, Key) of
				[] -> 	io:format("I am empty"),
						ets:insert(Table, {Key, Value}),
						Pid ! {Ref, stored, no_value}; % These have to be banged back the way, I think.
						% storage_process(Table); % TODO VIJAY: I changed this from storage_process to storage_process_helper
												% and am pulling it out of the receive--everything will do it at the end.
				[{Key, OldVal}] -> 	io:format("I am not empty"),
									ets:insert(Table, {Key, Value}), 
									Pid ! {Ref, stored, OldVal} % These have to be banged back the way, I think.
									% storage_process(Table)
			end;
		 {Pid, requestStorageTables, RequestingNodeNum, ParentNodeNum} -> 
		 	ParentNode = lists:concat(["Node", integer_to_list(ParentNodeNum)]),
		 	global:send(ParentNode, {self(), sendStorageTable, Table, RequestingNodeNum, StorageID}); % TODO: Transform our table into a duplicate.
		 {Pid, kill} -> % Message from our parent node that we no longer need to exist. (So we must have been a duplicate.)
		 	exit("We no longer need to be duplicating data. ~n");
		 Message -> 
		 	io:format("Malformed request ~p~n", [Message])
	end,
	storage_process_helper(Table, StorageID).

% StorageID is its int value in the global registry table
storage_process(StorageID) -> % TODO change when we use Pid
	io:format("Storage process received something~n"),
	Table = ets:new(storage_table, []),
	storage_process_helper(Table, StorageID).

% Generates all possible node names based on the number of storage processes.
generate_node_nums(0) -> [0];
generate_node_nums(NumStorageProcesses) -> 
	[NumStorageProcesses] ++ generate_node_nums(NumStorageProcesses-1).

%% Lists all powers of 2 from NumStorageProcesses to 1; i.e. [8,4,2,1] if num=8
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

%If we have a storage process from TargetStorageProcesses as a neighbour, return that
%	 storage process. Otherwise, return the greatest neighbour less than
%	 smallest target storage process.
get_closest_neighbour_to_target(SenderNodeNum, TargetNodeNum, AllStorageNeighbours, TargetStorageProcesses, NumStorageProcesses) ->
	AllNeighboursSorted = lists:sort(AllStorageNeighbours),
	% see if any element in AllStorageNeighbours is in TargetStorageProcesses
	NeighboursInTarget = lists:filter(fun(X) -> lists:member(X, TargetStorageProcesses) end, AllStorageNeighbours),
	if
		NeighboursInTarget == [] -> % filter out neighbours less than the target
			SmallerNeighbours = lists:filter(fun(X) -> X < TargetNodeNum end, AllStorageNeighbours),
			if
				SmallerNeighbours == [] -> 
					lists:last(AllNeighboursSorted); % if none less, take biggest
				true ->
					lists:last(SmallerNeighbours) % otherwise take greatest less than it
			end;
		true -> lists:nth(1, NeighboursInTarget) % if we have a neighbour in the target, just pick it
	end.

get_closest_neighbor_node_to_target(AllStorageNeighbours, TargetStorageNum, NumStorageProcesses) ->
	AllNeighboursSorted = lists:sort(AllStorageNeighbours),
	NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
	case lists:member(TargetStorageNum, AllNeighboursSorted) of
		true -> node_from_storage_process(TargetStorageNum, NodesInNetwork);
		_Else -> 	SmallestNeighborLessThanTarget = lists:filter(fun(X) -> X < TargetStorageNum end, AllStorageNeighbours),
					if 
						SmallestNeighborLessThanTarget == [] -> node_from_storage_process(lists:last(AllStorageNeighbours), NodesInNetwork);
						true								-> lists:last(SmallestNeighborLessThanTarget)
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
% NOTE: Any message should keep track of the original sender (if it matters) in
%		the message itself. It should also be designed so any intermediary
%		could check the intended recipient, and forward along or read if needed.
% 		NumStorageProcesses MUST BE (2^m)-1
send_node_message(SenderNodeNum, TargetNodeNum, NumStorageProcesses, Message) ->
	NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
	NextNodeNum = get_next_node(SenderNodeNum, NodesInNetwork),
	NextFromTargetNum = get_next_node(TargetNodeNum, NodesInNetwork),
	% PrevNodeNum = get_previous_node(EnteringNodeNum, NodesInNetwork),

	SenderNode = lists:concat(["Node", integer_to_list(SenderNodeNum)]),
	NextNode = lists:concat(["Node", integer_to_list(NextNodeNum)]),
	% PrevNode = lists:concat(["Node", integer_to_list(PrevNodeNum)]),

	% NOTE: PROCESS
	% 1. Determine storage processes that should be on the entering node.
	% 1.5. Determine storage processes that should be on the target node.
	% 2. Calculate all of entering node's processes' neighbors.
	% 3. If we have a storage process from 1.5 as a neighbour, return that
	%	 storage process. Otherwise, return the greatest neighbour less than
	%	 smallest target storage process.
	% 4. Determine the node that storage process is in.
	% 5. Send message via global:send to that node.

	% 1.
	SenderStorageProcesses = calc_storage_processes(SenderNodeNum, NextNodeNum, NumStorageProcesses),% storage processes on our entering node
	% io:format("EnteringStorageProcesses are: ~p~n", [SenderStorageProcesses]),

	% 1.5.
	TargetStorageProcesses = calc_storage_processes(TargetNodeNum, NextFromTargetNum, NumStorageProcesses),
	% io:format("TargetStorageProcesses are: ~p~n", [TargetStorageProcesses]),

	% 2.
	AllStorageNeighbours = calc_storage_neighbours(SenderStorageProcesses, NumStorageProcesses),
	% io:format("AllStorageNeighbours are: ~p~n", [AllStorageNeighbours]),

	% 3.
	ClosestStorageNeighbourNum = get_closest_neighbour_to_target(SenderNodeNum, TargetNodeNum, AllStorageNeighbours, TargetStorageProcesses, NumStorageProcesses),
	% io:format("ClosestStorageNeighbourNum is: ~p~n", [ClosestStorageNeighbourNum]),

	% 4. 
	ClosestNodeNeighbourNum = node_from_storage_process(ClosestStorageNeighbourNum, NodesInNetwork),
	% io:format("ClosestNodeNeighbourNum is: ~p~n", [ClosestNodeNeighbourNum]),
	
	ClosestNeighbour = lists:concat(["Node", integer_to_list(ClosestNodeNeighbourNum)]),

	% 5.
	io:format("Sending message to: ~p~n", [ClosestNeighbour]),
	io:format("Message is: ~p~n", [Message]),
	global:send(ClosestNeighbour, Message).

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
	RequestStorageTablesMsg = {self(), requestStorageTables, RandomFreeNodeNum, PreviousNodeNum},

	send_node_message(RandomFreeNodeNum, PreviousNodeNum, NumStorageProcesses, RequestStorageTablesMsg), % send a message from RandomFreeNode to
																  % previous node requesting all
																  % storage processes from r to next.

	global:register_name(RandomFreeNode, self()),
	{RandomFreeNodeNum, RandomFreeNode}. % do things before registering us.

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
				 process_messages(NumStorageProcesses, CurrentNodeID);
			3 -> NodeInNetwork = list_to_atom(hd(tl(tl(Params)))), % third parameter
				 % CurrentNodeID = list_to_atom(NodeInNetwork),
				 %process_messages(NumStorageProcesses, CurrentNodeID),
				 % io:format("NodeInNetwork is: ~p~n", [NodeInNetwork]),
				 {OurNodeNum, OurNode} = enter_network(NodeInNetwork, NumStorageProcesses-1),
				 process_messages(NumStorageProcesses, OurNodeNum);
			_Else -> io:format("Error: bad arguments (too few or too many) ~n"),
					  halt()
		end,
		halt().

request_and_response_for_storage_table(Pid, NodeID, StorageID) ->
	global:send(StorageID, {Pid, requestStorageTables, NodeID, NodeID}),
	receive
		{NewPid, sendStorageTable, Table, DestinationNodeNum, StorageID} ->
		if
		 	NewPid == Pid -> % table meant for us
		 		io:format("Received table with ID. Not fully implemented yet: ~p~n", [StorageID]),
		 		ets:foldl(fun(X,Acc) -> lists:append([element(1,X)], Acc) end, [], Table);
		 	true -> % not meant for us, forward onwards
		 		io:format("Table not meant for us"),
		 		[]
		 end,
		end.

process_table_response(AllMyStorageProcesses, Pid, NodeID) ->
	foldl(func(X, Accin) -> StorageID = lists:concat(["Storage", X]), 
										lists:append(request_and_response_for_storage_table(Pid, NodeId, StorageID), Accin) end,
										[], AllMyStorageProcesses),
end.


% Handle any message into the non-storage process for a node.
process_messages(NumStorageProcesses, CurrentNodeID) ->
		io:format("in process messages"),
		receive 
			{Pid, Ref, first_key} ->
				% gather all your data across your multiple tables
				NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
				NextNodeNum = get_next_node(CurrentNodeID, NodesInNetwork),
				AllMyStorageProcesses = calc_storage_processes(CurrentNodeID, NextNodeNum, NumStorageProcesses),
				process_table_response(AllMyStorageProcesses, Pid, CurrentNodeID)


				
				% then msg your nearest neighbor about giving their







			{Pid, Ref, retrieve, Key} -> 
				%calculate the hash value of key
				%if hash(key) matches one of our storage processes, then send and retrieve
				%else, bounce to the nearest neighbour and ask for it!
				StorageTableToRetrieve = hash(Key, NumStorageProcesses),
				case is_my_process(CurrentNodeID, StorageTableToRetrieve, NumStorageProcesses) of
					true -> 
						io:format("Key is hashble to one of my processes ~n"),
						ConstructedStorageProcess = lists:concat(["Storage", integer_to_list(StorageTableToRetrieve)]),
						io:format("Storage process is ~p", [ConstructedStorageProcess]),
						global:send(ConstructedStorageProcess, {self(), make_ref(), retrieve, Key}),
						process_storage_reply_messages(Pid, Ref);
					false -> 
						io:format("key not hashable to any of my processes ~n"),
						NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
						NextNodeNum = get_next_node(CurrentNodeID, NodesInNetwork),
						AllMyStorageProcesses = calc_storage_processes(CurrentNodeID, NextNodeNum, NumStorageProcesses),
						AllMyNeighbors = calc_storage_neighbours(AllMyStorageProcesses, NumStorageProcesses),
						ClosestNeighbor = get_closest_neighbor_node_to_target(AllMyNeighbors, StorageTableToRetrieve, NumStorageProcesses),
						MakeNeighborName = lists:concat(["Node", integer_to_list(ClosestNeighbor)]),
						global:send(MakeNeighborName, {Pid, Key, retrieve, Key}),
						process_messages(NumStorageProcesses, CurrentNodeID)
				end;
			{Pid, Ref, store, Key, Value} -> % Insert key-value into a storage process if it fits our hash.
				io:format("received key: ~p", [Key]),
				ProspectiveStorageTable = hash(Key, NumStorageProcesses),
				case is_my_process(CurrentNodeID, ProspectiveStorageTable, NumStorageProcesses) of
					true -> 
						io:format("Key is hashble to one of my processes ~n"),
						ConstructedStorageProcess = lists:concat(["Storage", integer_to_list(ProspectiveStorageTable)]),
						io:format("Storage process is ~p", [ConstructedStorageProcess]),
						global:send(ConstructedStorageProcess, {self(), make_ref(), store, Key, Value}),
						process_storage_reply_messages(Pid, Ref);
					false -> 
						io:format("key not hashable to any of my processes ~n"),
						NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
						NextNodeNum = get_next_node(CurrentNodeID, NodesInNetwork),
						AllMyStorageProcesses = calc_storage_processes(CurrentNodeID, NextNodeNum, NumStorageProcesses),
						AllMyNeighbors = calc_storage_neighbours(AllMyStorageProcesses, NumStorageProcesses),
						ClosestNeighbor = get_closest_neighbor_node_to_target(AllMyNeighbors, ProspectiveStorageTable, NumStorageProcesses),
						MakeNeighborName = lists:concat(["Node", integer_to_list(ClosestNeighbor)]),
						global:send(MakeNeighborName, {Pid, Key, store, Key, Value}),
						process_messages(NumStorageProcesses, CurrentNodeID)
				end;
			{Pid, requestStorageTables, OriginalNodeNum, DestinationNodeNum} ->  % forward along or send to a storage process we own
				if 
					CurrentNodeID == DestinationNodeNum -> % send message to storage processes on this node.
														% receive tables back. Send table via global:send
														% to OriginalNodeNum.
							io:format("IN REQUESTSTORAGETABLES"),
							OurStorageProcessNums = calc_storage_processes(DestinationNodeNum, OriginalNodeNum, NumStorageProcesses-1),
							OurStorageProcessNames = lists:map(fun(X) -> lists:concat(["Storage", integer_to_list(X)]) end, OurStorageProcessNums),
							RequestTablesMessage = {self(), requestStorageTables, OriginalNodeNum, DestinationNodeNum}, % Original is the requester, destination node received it.
							lists:map(fun(X) -> global:send(X, RequestTablesMessage) end, OurStorageProcessNames),
							io:format("Got the message! We should send the proper storage processes data via global:send "), 
							% Unless the predecessor is the same as the OriginalNode.
							NodesInNetworkList = find_all_nodes(0, [], NumStorageProcesses),
							PredNodeNum = get_previous_node(CurrentNodeID, NodesInNetworkList),
							PredNode = lists:concat(["Node", integer_to_list(PredNodeNum)]),
							if
								PredNodeNum == OriginalNodeNum -> % Then we have no duplicates to delete. Case of 2 nodes in network.
									true;
								true -> % send message to our predecessor having him delete our duplicates--we become the duplicate.
									DeleteDuplsMessage = {self(), deleteStorageDuplicates, CurrentNodeID},
									send_node_message(CurrentNodeID, PredNode, NumStorageProcesses-1, DeleteDuplsMessage)
							end;
							% TODO leave the duplicates registered on the node with the same value
							% TODO tell pred node to delete any duplicates it shouldn't have (it could calculate this using
							% register, and then kill those)
					true -> io:format("Not for us! Passing it along to: ~p~n", [DestinationNodeNum]),
							send_node_message(CurrentNodeID, DestinationNodeNum, NumStorageProcesses-1, {self(), requestStorageTables, OriginalNodeNum, DestinationNodeNum})
				end;
			{Pid, deleteStorageDuplicates, SuccessorNum} -> 
				io:format("Got a deleteStorageDuplicates message. Not implemented yet."),
				% delete every duplicate storage table we have from SuccessorNum to its successor--kill their processes
				NodesInNetworkList = find_all_nodes(0, [], NumStorageProcesses),
				TwoNodesAwayNum = get_next_node(SuccessorNum, NodesInNetworkList),
				StorageProcessNumsToKill = calc_storage_processes(SuccessorNum, TwoNodesAwayNum, NumStorageProcesses-1),
				StorageProcessesToKill = lists:map(fun(X) -> list_to_atom(lists:concat(["Storage", integer_to_list(X)])) end, StorageProcessNumsToKill),
				KillMessage = {self(), kill},
				% lists:map(fun(X) -> X ! KillMessage end, StorageProcessesToKill),
				% lists:map(fun(X) -> kill(X) end, StorageProcessesToKill), % TODO kill every duplicate process 
				true;
			{Pid, sendStorageTable, Table, DestinationNodeNum, StorageID} ->
				if
				 	CurrentNodeID == DestinationNodeNum -> % table meant for us
				 		% StorageName = lists:concat(["Storage", integer_to_list(StorageID)]),
				 		% global:unregister_name(StorageName), % unregister old one, register new one
				 		% global:sync(),
				 		% SpawnPID = spawn(key_value_node, storage_process, [[], StorageID]),
				 		% global:register_name(StorageName, SpawnPID),
				 		io:format("Received table with ID. Not fully implemented yet: ~p~n", [StorageID]);
				 	true -> % not meant for us, forward onwards
				 		send_node_message(CurrentNodeID, DestinationNodeNum, NumStorageProcesses-1, {self(), sendStorageTable, Table, DestinationNodeNum, StorageID})
				 end; 
			Message -> 
				io:format("Received some malformed message ~p~n", [Message])
		end,
		process_messages(NumStorageProcesses, CurrentNodeID).

process_storage_reply_messages(OldPid, OldRef) ->
	receive
		{Ref, stored, no_value} -> 
					io:format("I am exiting with no value"),
					OldPid ! {OldRef, stored, no_value};
		{Ref, stored, OldVal} -> 
					io:format("I am exiting with old value ~p", [OldVal]),
					OldPid ! {OldRef, stored, OldVal};
		{Ref, retrieved, Value} ->
					io:format("Got the retrieved value which is ~p", [Value]),
					OldPid ! {OldRef, retrieved, Value}
	end.


spawn_tables(NumTables) ->
	if NumTables < 0
		-> true;
		true ->
			SpawnPID = spawn(key_value_node, storage_process, [NumTables]), % TODO VIJAY: Couldn't we change [] to ets:new(storage_table, [])
																	 % TODO VIJAY: and then just spawn with storage_process_helper?
			SpawnName = lists:concat(["Storage", integer_to_list(NumTables)]),
			register(list_to_atom(SpawnName), SpawnPID), % registers it locally with the node-- so we can access it after it's globally deregistered
			global:register_name(SpawnName, SpawnPID), % and globally
			spawn_tables(NumTables-1)
	end.
