-module(key_value_node).
-export([main/1]).
-define(TIMEOUT, 2000).
% NOTE: a fork is defined as a tuple with two neighbours and an isClean boolean
% neighbour1 and neighbour2 are encoded via each one's node name, as an atom.

storageProcess(Pid) ->
	TableId = Pid
	receive _ -> io:format("ey")
	end,
end.


main(Params) ->
		%set up network connections
		_ = os:cmd("epmd -daemon"),

		Num_storage_processes = hd(Params),
		Reg_name = hd(tl(Params)),
		Reg_node = hd(tl(tl(Params))),
		net_kernel:start([list_to_atom(Reg_name), shortnames]),





		halt().