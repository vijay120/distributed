#!/bin/bash

#chmod u+x ssh.sh


ssh enugent@poinsettia.cs.hmc.edu erl -noshell -run philosopher main p1 > /dev/null 2>&1 &
ssh enugent@amazonia.cs.hmc.edu erl -noshell -run philosopher main p2 p1@poinsettia > /dev/null 2>&1 &
ssh enugent@arden.cs.hmc.edu erl -noshell -run philosopher main p3 p2@amazonia p1@poinsettia > /dev/null 2>&1 &
ssh enugent@ash.cs.hmc.edu erl -noshell -run philosopher main p4 p3@arden p2@amazonia p1@poinsettia > /dev/null 2>&1 &
ssh enugent@birnam.cs.hmc.edu erl -noshell -run philosopher main p5 p4@ash p3@arden p2@amazonia p1@poinsettia > /dev/null 2>&1 &
ssh enugent@bluebell.cs.hmc.edu erl -noshell -run philosopher main p6 p5@birnam p4@ash p3@arden p2@amazonia p1@poinsettia > /dev/null 2>&1 &
ssh enugent@broceliande.cs.hmc.edu erl -noshell -run philosopher main p7 p6@bluebell p5@birnam p4@ash p3@arden p2@amazonia p1@poinsettia > /dev/null 2>&1 &
ssh enugent@clover.cs.hmc.edu erl -noshell -run philosopher main p8 p7@broceliande p6@bluebell p5@birnam p4@ash p3@arden p2@amazonia p1@poinsettia > /dev/null 2>&1 &
ssh enugent@columbine.cs.hmc.edu erl -noshell -run philosopher main p9 p8@clover p7@broceliande p6@bluebell p5@birnam p4@ash p3@arden p2@amazonia p1@poinsettia > /dev/null 2>&1 &
ssh enugent@cosmos.cs.hmc.edu erl -noshell -run philosopher main p10 p9@columbine p8@clover p7@broceliande p6@bluebell p5@birnam p4@ash p3@arden p2@amazonia p1@poinsettia > /dev/null 2>&1 &


