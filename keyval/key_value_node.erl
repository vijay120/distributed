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
			2 -> GlobalNodeName = lists:concat(["Node", integer_to_list(1)]), % TODO: 1 or 0?
				 DoesRegister = global:register_name(GlobalNodeName, self()),
				 io:format("Does it register? ~p~n", [DoesRegister]),	
				 spawn_tables(NumStorageProcesses),
				 GlobalTable = global:registered_names(),
				 io:format("Registered table is: ~p~n", [GlobalTable]);
			3 -> NodeInNetwork = list_to_atom(hd(tl(tl(Params)))), % third parameter
				 io:format("NodeInNetwork is: ~p~n", [NodeInNetwork]),
				 enter_network(NodeInNetwork);
			_Else -> io:format("Error: bad arguments (too few or too many) ~n"),
					  halt()
		end,
		% global:register_name(node, self()), % register in global table as well as shortname
		chill(). % temporary thing to keep it alive.
		% halt().

chill() ->
	chill(). % woot

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