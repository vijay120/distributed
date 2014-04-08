-module(key_value_node).
-export([main/1, storage_process/1]).
-define(TIMEOUT, 2000).

storage_process(_) -> % TODO change when we use Pid
	%io:format("storageTable is ~p~n", [Pid]),
	Table = ets:new(storage_table, []),
	receive 
		{pid, ref, store, Key, Value} -> 
			case ets:lookup(Table, Key) of
				[] -> 	ets:insert(Table, {Key, Value}),
						{ref, stored, no_value}; % These have to be banged back the way, I think.
				[{Key, OldVal}] -> 	ets:insert(Table, {Key, Value}), 
									{ref, stored, OldVal} % These have to be banged back the way, I think.
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
get_closest_neighbour_to_prev(EnteringNodeNum, AllStorageNeighbours, NumStorageProcesses) ->
	AllNeighboursSorted = lists:sort(AllStorageNeighbours),
	SmallerNeighbours = lists:filter(fun(X) -> X < EnteringNodeNum end, AllStorageNeighbours),
	if
		SmallerNeighbours == [] -> lists:last(AllNeighboursSorted);
		true 					-> lists:last(SmallerNeighbours)
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


% Send a message to PrevNode requesting all the storage tables indexed from 
% EnteringNode to NextNode in our global registry table.
request_storage_tables(EnteringNodeNum, NextNodeNum, PrevNodeNum, NodesInNetwork, NumStorageProcesses, Message) ->
	EnteringNode = lists:concat(["Node", integer_to_list(EnteringNodeNum)]),
	NextNode = lists:concat(["Node", integer_to_list(NextNodeNum)]),
	PrevNode = lists:concat(["Node", integer_to_list(PrevNodeNum)]),

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
	ClosestStorageNeighbourNum = get_closest_neighbour_to_prev(EnteringNodeNum, AllStorageNeighbours, NumStorageProcesses),
	io:format("ClosestStorageNeighbourNum is: ~p~n", [ClosestStorageNeighbourNum]),

	% 4. 
	ClosestNodeNeighbourNum = node_from_storage_process(ClosestStorageNeighbourNum, NodesInNetwork),
	io:format("ClosestNodeNeighbourNum is: ~p~n", [ClosestNodeNeighbourNum]),
	
	ClosestNeighbour = lists:concat(["Node", integer_to_list(ClosestNodeNeighbourNum)]),

	global:send(ClosestNeighbour, Message), 
	io:format("Got here!").

% TODO: Make sure these are properly handling NumStorageProcesses as 2^m or (2^m)-1.
hash(Key, NumStorageProcesses) -> lists:foldl(fun(X, Acc) -> X+Acc end, 0, Key) rem NumStorageProcesses.



find_all_nodes(PossibleId, Accin, Maximum) ->
	if PossibleId > Maximum -> Accin;
		true -> ConstructName = lists:concat(["Node", integer_to_list(PossibleId)]),
				case global:whereis_name(ConstructName) of
					undefined -> find_all_nodes(PossibleId+1, Accin, Maximum);
					_ -> find_all_nodes(PossibleId+1, lists:concat([Accin, [PossibleId]]), Maximum)
				end
	end.
%trying to resolve stuff

is_my_process(NodeId, ProcessId) ->	
	PossibleIDs = find_all_nodes(0, [], 10),
	io:format("List of possible ids ~p", PossibleIDs).

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

	request_storage_tables(RandomFreeNodeNum, NextNodeNum, PreviousNodeNum, NodesInNetworkList, NumStorageProcesses, {self(), hello}), % send a message from RandomFreeNode to
																  % previous node requesting all
																  % storage processes from r to next.

	global:register_name(RandomFreeNode, self()). % do things before registering us.
	
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
				 chill();
				 % processMessages(NumStorageProcesses, CurrentNodeID);
			3 -> NodeInNetwork = list_to_atom(hd(tl(tl(Params)))), % third parameter
				 % CurrentNodeID = list_to_atom(NodeInNetwork),
				 %process_messages(NumStorageProcesses, CurrentNodeID),
				 % io:format("NodeInNetwork is: ~p~n", [NodeInNetwork]),
				 enter_network(NodeInNetwork, NumStorageProcesses-1),
				 chill();
			_Else -> io:format("Error: bad arguments (too few or too many) ~n"),
					  halt()
		end,
		halt().

% Temporary function to test sending/receiving global messages.
chill() -> 
	receive
		{Pid, hello} -> io:format("Received a message! ~n");
		_ -> io:format("Received...something? ~n")
	end,
	chill().

process_messages(NumStorageProcesses, CurrentNodeID) ->
		io:format("in process messages"),
		receive 
			{Pid, Ref, store, Key, Value} -> 
				io:format("recieved key: ~p", [Key]),
				is_my_process(CurrentNodeID, hash(Key, NumStorageProcesses));
			_ -> io:format("IN some other message")
			%check if hash(key) == one of your storage processes
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
