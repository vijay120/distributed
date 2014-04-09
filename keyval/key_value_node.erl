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
generateNodeNums(0) -> [0];
generateNodeNums(NumStorageProcesses) -> 
	[NumStorageProcesses] ++ generateNodeNums(NumStorageProcesses-1).


% Send a message to Predecessor requesting all the storage tables indexed from 
% EnteringNode to Successor in our global registry table.
% requestStorageTables(EnteringNode, Successor, Predecessor) ->
requestStorageTables(_, _, _) ->
	io:format("Got here!").

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


% Node adds itself to the network, gets its storage processes (and facilitates
% all other rebalancing).

% NOTE: All the "nodes" mentioned below are actually just the number they are
% registered as. E.x., "Node1" = 1 below.
enter_network(NodeInNetwork, NumStorageProcesses) ->
	net_kernel:connect_node(NodeInNetwork),
	
	global:sync(),

	NodesInNetworkList = find_all_nodes(0, [], NumStorageProcesses), % a sorted list TODO see if it's sorted sensibly
	io:format("Our sorted list is: ~p~n", [NodesInNetworkList]),
	NodesInNetworkSet = ordsets:from_list(NodesInNetworkList),
	AllNodes = ordsets:from_list(generateNodeNums(NumStorageProcesses)),
	NodesAvailable = ordsets:to_list(ordsets:subtract(AllNodes, NodesInNetworkSet)),
	io:format("The available nodes are: ~p~n", [NodesAvailable]),
	RandomVal = random:uniform(length(NodesAvailable)),
	RandomFreeNode = lists:nth(RandomVal, NodesAvailable),
	io:format("Random free node is: ~p~n", [RandomFreeNode]),

	% extra logic needed for edge cases of wrapping around list
	if 
		RandomVal == 0 -> PreviousNodeIndex = NumStorageProcesses;
		true 		   -> PreviousNodeIndex = RandomVal - 1
	end,

	PreviousNode = lists:nth(PreviousNodeIndex, NodesAvailable), % get the previous node,
																 % TODO then send a message across the ring to him.

	io:format("Previous free node is: ~p~n", [PreviousNode]),
	% edge case needed for wrapping around other end of list
	if
		RandomVal == NumStorageProcesses -> NextNodeIndex = 0;
		true 							 -> NextNodeIndex = RandomVal + 1
	end,

	NextNode = lists:nth(NextNodeIndex, NodesAvailable),	
	io:format("Next free node is: ~p~n", [NextNode]),

	requestStorageTables(RandomFreeNode, NextNode, PreviousNode), % send a message from RandomFreeNode to
																  % previous node requesting all
																  % storage processes from r to next.

	global:register_name(lists:concat(["Node", integer_to_list(RandomFreeNode)]), self()). % do things before registering us.
	
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
				 chill();
			3 -> %StringNodeInNetwork = atom_to_list(hd(tl(tl(Params)))),
				 NodeInNetwork = list_to_atom(hd(tl(tl(Params)))), % third parameter
				 %CurrentNodeID = list_to_atom(NodeInNetwork),
				 CurrentNodeID = string:to_integer(string:substr(hd(tl(tl(Params))), length(hd(tl(tl(Params)))), length(hd(tl(tl(Params)))))),
				 %processMessages(NumStorageProcesses, CurrentNodeID),
				 %io:format("NodeInNetwork is: ~p~n", [NodeInNetwork]),
				 enter_network(NodeInNetwork, NumStorageProcesses+1),
				 chill();
			_Else -> io:format("Error: bad arguments (too few or too many) ~n"),
					  halt()
		end,
		halt().

chill() -> chill().

processMessages(NumStorageProcesses, CurrentNodeID) ->
		io:format("in process messages"),
		receive 
			{Pid, Ref, store, Key, Value} -> 
				io:format("recieved key: ~p", [Key]),
				ProspectiveStorageTable = hash(Key, NumStorageProcesses),
				case is_my_process(CurrentNodeID, ProspectiveStorageTable, NumStorageProcesses) of
					true -> 
						io:format("This is true"),
						ConstructedStorageProcess = lists:concat(["Storage", integer_to_list(ProspectiveStorageTable)]),
						io:format("Storage process is ~p", [ConstructedStorageProcess]),
						global:send(ConstructedStorageProcess, {self(), make_ref(), store, Key, Value}),
						processStorageReplyMessages(Pid, Ref);
					false -> io:format("I will deal with this case later")
				end;
			_ -> io:format("IN some other message")
		end.

processStorageReplyMessages(OldPid, OldRef) ->
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
