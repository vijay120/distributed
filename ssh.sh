#!/bin/bash

#chmod u+x ssh.sh


ssh enugent@poinsettia.cs.hmc.edu erl -noshell -run philosopher main p1 > /dev/null 2>&1 &
erl

