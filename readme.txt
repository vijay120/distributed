Names: Eoin Nugent and Vijay Ramakrishnan

The code is generally broken up into one state per function, though with
exceptions. For example, joinState is the only thing that ever sends
identify messages, so we have left sendIdentifyMessage(..) directly
below joinState. Messages are handled by each state, as required by the algorithm,
within that state's function. The handling of messages is generally similar, but
slightly different with each function as required by the algorithm.

Some things are slightly less elegant than the ideal. Some erlang peculiarities
(like having to pass parameters around everywhere and not being able to change
the value of a given variable) made the code awkward in places. But in general
the message receiving and mailbox metaphor greatly simplified the process for 
that sort of thing.

Implementing this, in general, was remarkably straightforward given the 
complexity in terms of the algorithm, the fact that we're dealing with
networked processes, and the total size of code. But it lent itself to
pretty fast coding. 