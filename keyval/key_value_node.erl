-module(key_value_node).
-export([main/1, storageProcess/1]).
-define(TIMEOUT, 2000).
% NOTE: a fork is defined as a tuple with two neighbours and an isClean boolean
% neighbour1 and neighbour2 are encoded via each one's node name, as an atom.

storageProcess(Pid) ->
	io:format("storageTable is ~p~n", [Pid]),
	TableId = Pid,
	Table = ets:new(storage_table, []),
	receive 
		{pid, ref, store, Key, Value} -> 
			case ets:lookup(Table, Key) of
				[] -> 	ets:insert(Table, {Key, Value}),
						{ref, stored, no_value};
				[{Key, OldVal}] -> 	ets:insert(Table, {Key, Value}), 
									{ref, stored, OldVal}
			end
end.

main(Params) ->
		%set up network connections
		_ = os:cmd("epmd -daemon"),
		{Num_storage_processes, _ } = string:to_integer(hd(Params)),
		Reg_name = hd(tl(Params)),
		net_kernel:start([list_to_atom(Reg_name), shortnames]),
		register(node, self()),
		if length(Params) == 2 -> spawn_tables(Num_storage_processes);
			true -> true
		end,
		halt().

spawn_tables(Num_tables) ->
	if Num_tables == 0
		-> true;
		true ->
			io:format("Num tables is ~p~n", [Num_tables]),
			SpawnPID = spawn(key_value_node, storageProcess, [Num_tables]),
			SpawnName = lists:concat(["Storage", integer_to_list(Num_tables)]),
			global:register_name(SpawnName, SpawnPID),
			spawn_tables(Num_tables-1)
end.