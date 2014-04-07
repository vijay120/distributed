-module(key_value_node).
-export([main/1, storage_process/1]).
-define(TIMEOUT, 2000).

storage_process(Pid) ->
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

hash(Key, Num_storage_processes) -> lists:foldl(fun(X, Acc) -> X+Acc end, 0, Key) rem Num_storage_processes.

find_all_nodes(PossibleId, Accin, Maximum) ->
	global:sync(),
	GlobalTable = global:registered_names(),
	io:format("Registered table is: ~p~n", [GlobalTable]), % connect to the network.
	if PossibleId > Maximum -> Accin;
		true -> ConstructName = lists:concat(["Node", integer_to_list(PossibleId)]),
				case global:whereis_name(ConstructName) of
					undefined -> find_all_nodes(PossibleId+1, Accin, Maximum);
					_ -> find_all_nodes(PossibleId+1, lists:concat([Accin, [PossibleId]]), Maximum)
				end
end.

is_my_process(NodeId, ProcessId) ->	
	PossibleIDs = find_all_nodes(0, [], 10),
	io:format("List of possible ids ~p", PossibleIDs),
	


% Node adds itself to the network, gets its storage processes (and facilitates
% all other rebalancing).
enter_network(NodeInNetwork) ->
	net_kernel:connect_node(NodeInNetwork),
	global:sync(),
	global:register_name(stupid, self()), % do things before registering us.
	GlobalTable = global:registered_names(),
	io:format("Registered table is: ~p~n", [GlobalTable]). % connect to the network.

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
			2 -> GlobalNodeName = lists:concat(["Node", integer_to_list(0)]), % TODO: 1 or 0?
				 CurrentNodeID = 0,
				 DoesRegister = global:register_name(GlobalNodeName, self()),
				 io:format("Does it register? ~p~n", [DoesRegister]),	
				 spawn_tables(NumStorageProcesses),
				 GlobalTable = global:registered_names(),
				 io:format("Registered table is: ~p~n", [GlobalTable]),
				 processMessages(NumStorageProcesses, CurrentNodeID);
			3 -> %StringNodeInNetwork = atom_to_list(hd(tl(tl(Params)))),
				 NodeInNetwork = list_to_atom(hd(tl(tl(Params)))), % third parameter
				 %CurrentNodeID = list_to_atom(NodeInNetwork),
				 CurrentNodeID = string:to_integer(string:substr(hd(tl(tl(Params))), length(hd(tl(tl(Params)))), length(hd(tl(tl(Params)))))),
				 processMessages(NumStorageProcesses, CurrentNodeID),
				 %io:format("NodeInNetwork is: ~p~n", [NodeInNetwork]),
				 enter_network(NodeInNetwork);
			_Else -> io:format("Error: bad arguments (too few or too many) ~n"),
					  halt()
		end,
		halt().

processMessages(NumStorageProcesses, CurrentNodeID) ->
		io:format("in process messages"),
		receive 
			{Pid, Ref, store, Key, Value} -> 
				io:format("recieved key: ~p", [Key]),
				is_my_process(CurrentNodeID, hash(Key, NumStorageProcesses));
			_ -> io:format("IN some other message")
			%check if hash(key) == one of your storage processes
		end.


spawn_tables(NumTables) ->
	if NumTables == 0
		-> true;
		true ->
			%io:format("Num tables is ~p~n", [NumTables]),
			SpawnPID = spawn(key_value_node, storage_process, [NumTables]),
			SpawnName = lists:concat(["Storage", integer_to_list(NumTables)]),
			global:register_name(SpawnName, SpawnPID),
			spawn_tables(NumTables-1)
end.