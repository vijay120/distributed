-module(key_value_node).
-export([main/1, storage_process_init/3, is_my_process/3]).
-define(TIMEOUT, 2000).

storage_process(Table, StorageID, NumStorageProcesses) ->
	io:format("FOR TESTING: My Pid is: ~p~n", [self()]),
	receive 
		{Pid, Ref, store, Key, Value, OrigSenderPid, OrigSenderRef} -> 
			case ets:lookup(Table, Key) of
				[] -> 	io:format("I am empty"),
						ets:insert(Table, {Key, Value}),
						Pid ! {Ref, stored, no_value, OrigSenderPid, OrigSenderRef}; % These have to be banged back the way, I think.
				[{Key, OldVal}] -> 	io:format("I am not empty"),
									ets:insert(Table, {Key, Value}), 
									Pid ! {Ref, stored, OldVal, OrigSenderPid, OrigSenderRef} % These have to be banged back the way, I think.
									
			end;

		{Pid, Ref, retrieve, Key} ->
			case ets:lookup(Table, Key) of
				[] -> 	io:format("I am empty"),
						Pid ! {Ref, retrieved, no_value}; % These have to be banged back the way, I think.
				[{Key, Value}] -> 	io:format("I am not empty"),
									Pid ! {Ref, retrieved, Value} % These have to be banged back the way, I think.
			end;

		 {Pid, requestStorageTables, RequestingNodeNum, ParentNodeNum} -> 
		 	ParentNode = lists:concat(["Node", integer_to_list(ParentNodeNum)]),
		 	StorageName = lists:concat(["Storage", integer_to_list(StorageID)]),
		 	DuplicateName = lists:concat(["StorageDuplicate", integer_to_list(StorageID)]),

		 	% Unregister as the official storage table, unregister our duplicate which no longer
		 	% exists. And then register as the duplicate.
		 	global:sync(),
		 	global:unregister_name(StorageName),
		 	global:unregister_name(DuplicateName),
		 	global:register_name(DuplicateName, self()),
		 	global:sync(),
		 	TableList = ets:tab2list(Table),
		 	global:send(ParentNode, {self(), sendStorageTable, TableList, RequestingNodeNum, StorageID});

		{Pid, requestStorageTablesSnapshot} ->
		 	TableList = ets:tab2list(Table),
		 	Pid ! {self(), sendStorageTable, TableList};		

		 {Pid, kill} -> % Message from our parent node that we no longer need to exist. (So we must have been a duplicate.)
		 	io:format("Received kill message. ~n"),
		 	exit("We no longer need to be duplicating data. ~n");
		 {Pid, requestDuplicates, RequestingNodeNum, ParentNodeNum} -> % Sends our table as a duplicate.
		 	ParentNode = lists:concat(["Node", integer_to_list(ParentNodeNum)]),
		 	TableList = ets:tab2list(Table),
		 	global:send(ParentNode, {self(), sendDuplicateTable, TableList, RequestingNodeNum, StorageID});
		 {Pid, makeOfficial} ->
		 	StorageName = lists:concat(["Storage", integer_to_list(StorageID)]),
		 	StorageDupName = lists:concat(["StorageDuplicate", integer_to_list(StorageID)]),

		 	global:sync(), % Unregister as duplicate, make ours official.
		 	global:unregister_name(StorageDupName),
		 	global:unregister_name(StorageName),
		 	global:register_name(StorageName, self()),
		 	global:sync();
		 {Pid, Ref, leave} -> % sent by the outside world; tell our parent node to leave
		 	io:format("Received message to leave~n"),
		 	NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
		 	ParentNodeNum = node_from_storage_process(StorageID, NodesInNetwork),
		 	ParentNode = lists:concat(["Node", integer_to_list(ParentNodeNum)]),
		 	global:send(ParentNode, {self(), leave});
		 Message -> 
		 	io:format("Malformed request ~p~n", [Message])
	end,
	storage_process(Table, StorageID, NumStorageProcesses).

storage_process_init(TableList, StorageID, NumStorageProcesses) ->
	NewTable = ets:new(storage_table, []),
	if TableList == [] ->
				 	storage_process(NewTable, StorageID, NumStorageProcesses);
		true -> 	lists:foldl(fun(X, _) -> ets:insert(NewTable, X) end, [], TableList),
					storage_process(NewTable, StorageID, NumStorageProcesses)
	end.

% % StorageID is its int value in the global registry table
% storage_process(StorageID) -> % TODO change when we use Pid
% 	% io:format("Storage process received something~n"),
% 	Table = ets:new(storage_table, []),
% 	storage_process_helper(Table, StorageID).

% Generates all possible node names based on the number of storage processes.
generate_node_nums(0) -> [0];
generate_node_nums(NumStorageProcesses) -> 
	[NumStorageProcesses] ++ generate_node_nums(NumStorageProcesses-1).

%% Lists all powers of 2 from NumStorageProcesses to 1; i.e. [8,4,2,1] if num=8
list_exponentials(0) -> [];
list_exponentials(NumStorageProcesses) ->						
	[NumStorageProcesses] ++ list_exponentials(NumStorageProcesses div 2). % div forces integer division

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
calc_storage_neighbours_helper(EnteringStorageProcesses, ListExps, NumStorageProcesses) ->
	if 
		EnteringStorageProcesses == [] -> [];
		true -> lists:map(fun(X) -> (hd(EnteringStorageProcesses) + X) rem (NumStorageProcesses+1) end, ListExps) ++ calc_storage_neighbours_helper(tl(EnteringStorageProcesses), ListExps, NumStorageProcesses)
	end.

% Calculates the storage processes that are neighbours to a given list of storage processes.
calc_storage_neighbours(EnteringStorageProcesses, NumStorageProcesses) ->
	ListExps = list_exponentials((NumStorageProcesses+1) div 2),
	io:format("ListExps are: ~p~n", [ListExps]),
	lists:usort(calc_storage_neighbours_helper(EnteringStorageProcesses, ListExps, NumStorageProcesses)). % usort removes duplicates

%	 If we have a storage process from TargetStorageProcesses as a neighbour, return that
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

% Uses the hash suggested by the assignment--just add characters.
hash(Key, NumStorageProcesses) -> 
	lists:foldl(fun(X, Acc) -> X+Acc end, 0, Key) rem NumStorageProcesses.

% Finds all the nodes in the global registry table.
find_all_nodes(PossibleId, Accin, Maximum) ->
	global:sync(),
	GlobalTable = global:registered_names(),
	% io:format("GlobalTable is: ~p~n", [GlobalTable]),
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
		true              -> lists:last(ListNodeNums)
	end.

% We know the number of our current node (NodeNum), return the string
% in the global registry of the node after it.
% This is either the smallest node greater than it or the smallest node of all
% nodes.
get_next_node(NodeNum,ListNodeNums) -> 
	GreaterNodes = lists:filter(fun(X) -> X > NodeNum end, ListNodeNums),
	if
		GreaterNodes /= [] -> lists:nth(1, GreaterNodes);
		true               -> lists:nth(1, ListNodeNums)
	end.

% Node adds itself to the network, gets its storage processes (and facilitates
% all other rebalancing).
%
% NOTE: NumStorageProcesses is presumed to be (2^m)-1.
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

	global:register_name(RandomFreeNode, self()),
	global:sync(), % force a sync prior to message passing

	PreviousNodeNum = get_previous_node(RandomFreeNodeNum, NodesInNetworkList),
	NextNodeNum = get_next_node(RandomFreeNodeNum, NodesInNetworkList),

	io:format("Requesting the duplicates from our successor (i.e. his actual nodes) ~n"),
	NextNode = lists:concat(["Node", integer_to_list(NextNodeNum)]),
	PreviousNode = lists:concat(["Node", integer_to_list(PreviousNodeNum)]),
	global:send(NextNode, {self(), requestDuplicates, RandomFreeNodeNum}),

	io:format("Previous Node is: ~p~n", [PreviousNodeNum]),
	io:format("Next Node is: ~p~n", [NextNodeNum]),

	% send message that can be transferred onwards:
	% {sender (i.e. self()), requestStorageTables (atom), original node, target node}
	RequestStorageTablesMsg = {self(), requestStorageTables, RandomFreeNodeNum, PreviousNodeNum},

	send_node_message(RandomFreeNodeNum, PreviousNodeNum, NumStorageProcesses, RequestStorageTablesMsg), % send a message from RandomFreeNode to
																  % previous node requesting all
																  % storage processes from r to next.

	RandomFreeNodeNum. % do things before registering us.

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
				 net_kernel:monitor_nodes(true), % monitor all nodes.
				 io:format("Does it register? ~p~n", [DoesRegister]),	
				 spawn_tables(NumStorageProcesses-1, NumStorageProcesses-1),
				 GlobalTable = global:registered_names(),
				 io:format("Registered table is: ~p~n", [GlobalTable]),
				 process_messages(NumStorageProcesses, CurrentNodeID);
			3 -> NodeInNetwork = list_to_atom(hd(tl(tl(Params)))), % third parameter
				 OurNodeNum = enter_network(NodeInNetwork, NumStorageProcesses-1),
				 net_kernel:monitor_nodes(true), % monitor all nodes
				 process_messages(NumStorageProcesses, OurNodeNum);
			_Else -> io:format("Error: bad arguments (too few or too many) ~n")
		end,
		halt().

request_and_response_for_storage_table(Pid, NodeID, StorageID) ->
	io:format("In request response ~p", [StorageID]),
	global:send(StorageID, {self(), requestStorageTablesSnapshot}),
	receive
		{NewPid, sendStorageTable, TableList} -> lists:foldl(fun(X,Acc) -> lists:append([element(1,X)], Acc) end, [], TableList)
	end.

process_table_response(AllMyStorageProcesses, Pid, NodeID) ->
	lists:foldl(fun(X, Accin) -> 	StorageID = lists:concat(["Storage", X]), 
								lists:append(request_and_response_for_storage_table(Pid, NodeID, StorageID), Accin) end,
								[], AllMyStorageProcesses).


% Handle any message into the non-storage process for a node.
process_messages(NumStorageProcesses, CurrentNodeID) ->
		global:sync(),
		io:format("in process messages ~n"),
		OrigGlobalTable = lists:sort(global:registered_names()),
		io:format("The state of the global table is: ~p~n", [OrigGlobalTable]),
		receive 

			{Pid, Ref, node_list} ->
				NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
				Pid ! {Ref, result, NodesInNetwork};

			{Pid, Ref, first_key} ->
				% gather all your data across your multiple tables
				NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
				NextNodeNum = get_next_node(CurrentNodeID, NodesInNetwork),
				AllMyStorageProcesses = calc_storage_processes(CurrentNodeID, NextNodeNum, NumStorageProcesses-1),
				AllMyKeys = process_table_response(AllMyStorageProcesses, Pid, CurrentNodeID),
				% then msg your nearest neighbor about giving their
				NextNodeName = lists:concat(["Node", integer_to_list(NextNodeNum)]),
				global:send(NextNodeName, {Pid, Ref, self(), snapshot, "First_Key", AllMyKeys});

			{Pid, Ref, last_key} ->
				% gather all your data across your multiple tables
				NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
				NextNodeNum = get_next_node(CurrentNodeID, NodesInNetwork),
				AllMyStorageProcesses = calc_storage_processes(CurrentNodeID, NextNodeNum, NumStorageProcesses-1),
				AllMyKeys = process_table_response(AllMyStorageProcesses, Pid, CurrentNodeID),
				% then msg your nearest neighbor about giving their
				NextNodeName = lists:concat(["Node", integer_to_list(NextNodeNum)]),
				global:send(NextNodeName, {Pid, Ref, self(), snapshot, "Last_Key", AllMyKeys});

			{Pid, Ref, num_keys} ->
				% gather all your data across your multiple tables
				NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
				NextNodeNum = get_next_node(CurrentNodeID, NodesInNetwork),
				AllMyStorageProcesses = calc_storage_processes(CurrentNodeID, NextNodeNum, NumStorageProcesses-1),
				AllMyKeys = process_table_response(AllMyStorageProcesses, Pid, CurrentNodeID),
				% then msg your nearest neighbor about giving their
				NextNodeName = lists:concat(["Node", integer_to_list(NextNodeNum)]),
				global:send(NextNodeName, {Pid, Ref, self(), snapshot, "Num_Key", AllMyKeys});

   			{Pid, Ref, OriginalPid, snapshot, Method, AggregatedKeys} ->
   				if self() == OriginalPid -> 
   						if 	Method == "First_Key" ->
   								case AggregatedKeys of 
   									[] -> Pid ! {Ref, result, []};
   									_Else -> 
		   								Result = lists:nth(1, lists:usort(AggregatedKeys)),
		   								io:format("Result is ~p", [Result]),
		   								Pid ! {Ref, result, Result}
		   						end;
   							Method == "Last_Key" ->
   								case AggregatedKeys of 
   									[] -> Pid ! {Ref, result, []};
   									_Else -> 
		   								Length = length(AggregatedKeys),
		   								Result = lists:nth(Length, lists:usort(AggregatedKeys)),
		   								io:format("Result is ~p", [Result]),
		   								Pid ! {Ref, result, Result}
		   						end;
   							Method == "Num_Key" ->
   								case AggregatedKeys of 
   									[] -> Pid ! {Ref, result, []};
   									_Else -> 
		   								Length = length(AggregatedKeys),
		   								io:format("Result is ~p", [Length]),
		   								Pid ! {Ref, result, Length}
		   						end;
   							true -> io:format("I dont know what you're talking about")
   						end;
   					true -> 
	   					% gather all your data across your multiple tables
						NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
						NextNodeNum = get_next_node(CurrentNodeID, NodesInNetwork),
						AllMyStorageProcesses = calc_storage_processes(CurrentNodeID, NextNodeNum, NumStorageProcesses-1),
						AllMyKeys = process_table_response(AllMyStorageProcesses, Pid, CurrentNodeID),
						AggregatedKeysWithMine = lists:append(AggregatedKeys, AllMyKeys),
						NextNodeName = lists:concat(["Node", integer_to_list(NextNodeNum)]),
						global:send(NextNodeName, {Pid, Ref, OriginalPid, snapshot, Method, AggregatedKeysWithMine})
					end;

			{Pid, Ref, retrieve, Key} -> 
				%calculate the hash value of key
				%if hash(key) matches one of our storage processes, then send and retrieve
				%else, bounce to the nearest neighbour and ask for it!
				StorageTableToRetrieve = hash(Key, NumStorageProcesses),
				case is_my_process(CurrentNodeID, StorageTableToRetrieve, NumStorageProcesses) of
					true -> 
						io:format("Key is hashable to one of my processes ~n"),
						ConstructedStorageProcess = lists:concat(["Storage", integer_to_list(StorageTableToRetrieve)]),
						io:format("Storage process is ~p", [ConstructedStorageProcess]),
						global:send(ConstructedStorageProcess, {Pid, Ref, retrieve, Key});
						% process_messages(NumStorageProcesses, CurrentNodeID);
					false -> 
						io:format("key not hashable to any of my processes ~n"),
						NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses),
						RetrieveMsg = {Pid, Key, retrieve, Key},
						TargetNode = node_from_storage_process(StorageTableToRetrieve, NodesInNetwork),
						send_node_message(CurrentNodeID, TargetNode, NumStorageProcesses-1, RetrieveMsg)

						% process_messages(NumStorageProcesses, CurrentNodeID)
				end;
			{Pid, Ref, store, Key, Value} -> % Insert key-value into a storage process if it fits our hash.
				io:format("received key: ~p", [Key]),
				ProspectiveStorageTable = hash(Key, NumStorageProcesses),
				case is_my_process(CurrentNodeID, ProspectiveStorageTable, NumStorageProcesses) of
					true -> 
						io:format("Key is hashable to one of my processes ~n"),
						ConstructedStorageProcess = lists:concat(["Storage", integer_to_list(ProspectiveStorageTable)]),
						io:format("Storage process is ~p", [ConstructedStorageProcess]),
						global:send(ConstructedStorageProcess, {self(), make_ref(), store, Key, Value, Pid, Ref});
					false -> 
						io:format("key not hashable to any of my processes ~n"),
						NodesInNetwork = find_all_nodes(0, [], NumStorageProcesses-1),
						StoreMsg = {Pid, Key, store, Key, Value},
						TargetNode = node_from_storage_process(ProspectiveStorageTable, NodesInNetwork),
						send_node_message(CurrentNodeID, TargetNode, NumStorageProcesses-1, StoreMsg)
				end;
			{Ref, stored, no_value, OldPid, OldRef} -> 
					io:format("Confirming store operation ~n"),
					OldPid ! {OldRef, stored, no_value};
			{Ref, stored, OldVal, OldPid, OldRef} -> 
					io:format("Confirming store operation with old value ~p~n", [OldVal]),
					OldPid ! {OldRef, stored, OldVal};
			{Pid, requestStorageTables, OriginalNodeNum, DestinationNodeNum} ->  % forward along or send to a storage process we own
				if 
					CurrentNodeID == DestinationNodeNum -> % send message to storage processes on this node.
														% receive tables back. Send table via global:send
														% to OriginalNodeNum.

							% First, delete the former duplicates on our predecessor.
							NodesInNetworkList = find_all_nodes(0, [], NumStorageProcesses-1),
							PredNodeNum = get_previous_node(CurrentNodeID, NodesInNetworkList),
							PredNode = lists:concat(["Node", integer_to_list(PredNodeNum)]),
							io:format("PredNodeNum, OriginalNodeNum, CurrentNodeID: [~p,~p,~p] ~n", [PredNodeNum, OriginalNodeNum, CurrentNodeID]),
							if
								PredNodeNum == OriginalNodeNum -> % Then we have no duplicates to delete. Case of 2 nodes in network.
									true;
								true -> % send message to our predecessor having him delete our duplicates--we will become the duplicate.
									DeleteDuplsMessage = {self(), deleteStorageDuplicates, CurrentNodeID, PredNodeNum},
									send_node_message(CurrentNodeID, PredNodeNum, NumStorageProcesses-1, DeleteDuplsMessage)
							end,

							io:format("Entering sleep~n"), % to try and give the above process enough time to finish
							timer:sleep(1000),			 % killing the old duplicate before the new one registers
							io:format("Exiting sleep~n"),

							% Then, send a requestStorageTables message to each of our storage nodes
							% greater than or equal to the value of our successor.
							% He will unregister as the actual storage table and reregister as the duplicate.
							
							% Get all the storage processes between the newly added node and its successor.
							% These should all be on our node right now.
							NextNextNode = get_next_node(OriginalNodeNum, NodesInNetworkList),
							StorageProcsForSuccessor = calc_storage_processes(OriginalNodeNum, NextNextNode, NumStorageProcesses-1),
							StorageProcNamesForSuccessor = lists:map(fun(X) -> lists:concat(["Storage", integer_to_list(X)]) end, StorageProcsForSuccessor),
							io:format("StorageProcNamesForSuccessor: ~p~n", [StorageProcNamesForSuccessor]), 
							global:sync(),
							io:format("Global table is: ~p~n", [lists:sort(global:registered_names())]),
							RequestTablesMessage = {self(), requestStorageTables, OriginalNodeNum, DestinationNodeNum}, % Original is the requester, destination node received it.
							lists:map(fun(X) -> global:send(X, RequestTablesMessage) end, StorageProcNamesForSuccessor);
					true -> 
							io:format("Not for us! Passing it along to: ~p~n", [DestinationNodeNum]),
							send_node_message(CurrentNodeID, DestinationNodeNum, NumStorageProcesses-1, {self(), requestStorageTables, OriginalNodeNum, DestinationNodeNum})
				end;
			{Pid, deleteStorageDuplicates, SuccessorNodeNum, DestinationNodeNum} -> 
				io:format("Received message ~p~n: ", [{Pid, deleteStorageDuplicates, SuccessorNodeNum, DestinationNodeNum}]),
				if 
					CurrentNodeID == DestinationNodeNum ->
						% Then we have to delete our duplicates between our successor and the successor's successor (aka the newly added node).
						% This is because these duplicates are already on our successor.
						io:format("Deleting duplicates ~n"),
						NodesInNetworkList = find_all_nodes(0, [], NumStorageProcesses-1),
						TwoNodesAwayNum = get_next_node(SuccessorNodeNum, NodesInNetworkList),
						StorageProcessNumsToKill = calc_storage_processes(SuccessorNodeNum, TwoNodesAwayNum, NumStorageProcesses-1),
						StorageProcessesToKill = lists:map(fun(X) -> lists:concat(["StorageDuplicate", integer_to_list(X)]) end, StorageProcessNumsToKill),
						% io:format("StorageProcessesToKill are: ~p~n", [StorageProcessesToKill]),
						KillMessage = {self(), kill},
						% io:format("Just prior to sending kill message"),
						global:sync(),
						
						io:format("Killing the following duplicates: ~p~n", [StorageProcessesToKill]),
						io:format("State of our global registry table is: ~p~n", [global:registered_names()]),
						lists:map(fun(X) -> global:send(X, KillMessage) end, StorageProcessesToKill),
						io:format("Survived the kill message-sending"); % kill all storage processes
					true -> % forward along, we haven't reached the original's predecessor yet.
						send_node_message(CurrentNodeID, DestinationNodeNum, NumStorageProcesses-1, {self(), deleteStorageDuplicates, SuccessorNodeNum, DestinationNodeNum})
				end;
			{Pid, sendStorageTable, TableList, DestinationNodeNum, StorageID} ->
				if
				 	CurrentNodeID == DestinationNodeNum -> % table meant for us. Spawn a process and register
				 										   % it as the official storage table with given ID.
				 		io:format("Received sendStorageTable, registering with ID: ~p~n", [StorageID]),
				 		StorageName = lists:concat(["Storage", integer_to_list(StorageID)]),
				 		global:sync(), % TODO maybe not needed?
				 		SpawnPID = spawn(key_value_node, storage_process_init, [TableList, StorageID, NumStorageProcesses-1]),
				 		global:register_name(StorageName, SpawnPID), % register as the new official node
				 		io:format("Received new storage table: ~p~n", [StorageID]);
				 	true -> % not meant for us, forward onwards
				 		send_node_message(CurrentNodeID, DestinationNodeNum, NumStorageProcesses-1, {self(), sendStorageTable, TableList, DestinationNodeNum, StorageID})
				 end; 
			{Pid, makeDuplicate, TableList, StorageID} -> 	% Special case when the second node enters, the first must send
													   		% it all the tables that it should duplicate.
				% This is received by the second node, who gets the data to duplicate.
				StorageDupName = lists:concat(["StorageDuplicate", integer_to_list(StorageID)]),
				SpawnPID = spawn(key_value_node, storage_process_init, [TableList, StorageID, NumStorageProcesses-1]),
				global:sync(),
				global:register_name(StorageDupName, SpawnPID);
			{Pid, requestDuplicates, PredNodeNum} ->
				NodesInNetworkList = find_all_nodes(0, [], NumStorageProcesses-1),
				SuccessorNodeNum = get_next_node(CurrentNodeID, NodesInNetworkList),
				StorageProcNumsToDuplicate = calc_storage_processes(CurrentNodeID, SuccessorNodeNum, NumStorageProcesses-1),
				StorageProcsToDuplicate = lists:map(fun(X) -> lists:concat(["Storage", integer_to_list(X)]) end, StorageProcNumsToDuplicate),
				RequestDupsMsg = {self(), requestDuplicates, PredNodeNum, CurrentNodeID},
				io:format("In requestDuplicates, StorageProcsToDuplicate: ~p~n", [StorageProcsToDuplicate]),
				lists:map(fun(X) -> global:send(X, RequestDupsMsg) end, StorageProcsToDuplicate);
			{Pid, sendDuplicateTable, TableList, DestinationNodeNum, StorageID} ->
				% Received by first node from storage process, must forward this table
				% onto the second node to make a duplicate.
				DestinationNode = lists:concat(["Node", integer_to_list(DestinationNodeNum)]),
				global:send(DestinationNode, {self(), makeDuplicate, TableList, StorageID});
			{Pid, leave} -> % Sent from our storage process by the outside world to leave
				exit("We were told to leave.");
			{nodedown, Node} ->
				global:sync(),
				% Use the difference between the original global table and this new one
				% to determine which node (by our registry naming scheme) has left.
				% We can use this to see if we care (i.e. if it's a successor or
				% predecessor).
				OrigGlobalTableSet = ordsets:from_list(OrigGlobalTable),
				NewGlobalTable = lists:sort(global:registered_names()),
				NewGlobalTableSet = ordsets:from_list(NewGlobalTable),
				LeftNodeName = lists:nth(1, ordsets:subtract(OrigGlobalTableSet, NewGlobalTableSet)), % there should only be one in the difference anyways
				{LeftNodeNum, _} = string:to_integer(string:sub_string(LeftNodeName, 5)), % we know it is "NodeINT"; strip out NODE then parse as int
				io:format("The node that left is: ~p~n", [LeftNodeName]),
				io:format("Updated global table is: ~p~n", [NewGlobalTable]),
				io:format("Parsed NodeNum to be: ~p~n", [LeftNodeNum]),

				NodesInNetworkList = find_all_nodes(0, [], NumStorageProcesses-1),
				PredecessorNodeNum = get_previous_node(CurrentNodeID, NodesInNetworkList), % These are after updating global table
				SuccessorNodeNum = get_next_node(CurrentNodeID, NodesInNetworkList);	   % We have to see if the guy that left fell between them
				% case is_between(CurrentNodeID, SuccessorNodeNum, LeftNodeNum, NumStorageProcesses-1) of
				% 	true -> % if less than new successor and
				% 			% greater than current, he must
				% 			% have been our old successor
				% 		% make our duplicates official. These are values between the old successor and the new.
				% 		DupStorageProcessNums = calc_storage_processes(LeftNodeNum, SuccessorNodeNum, NumStorageProcesses-1),
				% 		% are all of these necessarily duplicates?
				% 		DupStorageProcessNames = lists:map(fun(X) -> lists:concat(["StorageDuplicate", integer_to_list(X)]) end, DupStorageProcessNums),
				% 		lists:map(fun(X) -> global:send(X, {self(), makeOfficial}) end, DupStorageProcessNames), 

				% 		StorageProcessNames = lists:map(fun(X) -> lists:concat(["Storage", integer_to_list(X)]) end, DupStorageProcessNums),
				% 		% Then send these on to our predecessor to be duplitized.
				% 		PredecessorNode = lists:concat(["Node", integer_to_list(PredecessorNodeNum)]),
				% 		lists:map(fun(X) -> global:send(X, {self(), requestDuplicates, PredecessorNodeNum, CurrentNodeID}) end, StorageProcessNames);
				% 		% global:send(PredecessorNode, {self(), requestDuplicates, CurrentNodeID}); % TODO get duplicates from our new successor
				% 		%lists:map(fun(X) -> global:send(X, {self(), requestDuplicates, SuccessorNodeNum, CurrentNodeID}) end, StorageProcessNames);
				% 	false ->
				% 		true % Not our successor, we don't care.
				% end,
				% case is_between(PredecessorNodeNum, CurrentNodeID, LeftNodeNum, NumStorageProcesses-1) of
				%   	true -> % by same logic, must've been old predecessor
				% 		% send new predecessor all our official storage processes to duplicate.
				% 		CurrentStorageProcessNums = calc_storage_processes(CurrentNodeID, SuccessorNodeNum, NumStorageProcesses-1),
				% 		CurrentStorageProcessNames = lists:map(fun(X) -> lists:concat(["Storage", integer_to_list(X)]) end, CurrentStorageProcessNums),
				% 		lists:map(fun(X) -> global:send(X, {self(), requestDuplicates, PredecessorNodeNum, CurrentNodeID}) end, CurrentStorageProcessNames);
				% 	false -> % Not our predecessor, we don't care.
				% 		true
				% end;
			{nodeup, Node} ->
				io:format("Node ~p has been added to the network ~n", [Node]);
			Message -> 
				io:format("Received some malformed message ~p~n", [Message])
		end,
		process_messages(NumStorageProcesses, CurrentNodeID).


% Sees if NodeNum is between the LowerBoundNum and UpperBoundNum, taking into account the
% ring structure. 
is_between(LowerBoundNum, UpperBoundNum, NodeNum, NumStorageProcesses) ->
	% generate a list of all numbers between lower and upper bound. (i.e. by incrementing/wrapping around)
	% Then see if NodeNum is in that list
	ListNumbers = calc_storage_processes(LowerBoundNum, UpperBoundNum, NumStorageProcesses),
	lists:member(NodeNum, ListNumbers).

% Spawn tables and their duplicates, and register both appropriately.
spawn_tables(NumTables, NumStorageProcesses) ->
	if NumTables < 0
		-> true;
		true ->
			SpawnPID = spawn(key_value_node, storage_process_init, [[], NumTables, NumStorageProcesses]), 
			SpawnDupPID = spawn(key_value_node, storage_process_init, [[], NumTables, NumStorageProcesses]),
			SpawnName = lists:concat(["Storage", integer_to_list(NumTables)]),
			SpawnDupName = lists:concat(["StorageDuplicate", integer_to_list(NumTables)]), % register all duplicates on same node at first.
			register(list_to_atom(SpawnName), SpawnPID), % registers it locally with the node-- so we can access it after it's globally deregistered
			global:sync(),
			global:register_name(SpawnName, SpawnPID), % and globally
			global:register_name(SpawnDupName, SpawnDupPID),
			spawn_tables(NumTables-1, NumStorageProcesses)
	end.
