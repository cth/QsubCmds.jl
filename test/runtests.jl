using QsubCmds 
using Base.Test

# write your own tests here
@test 1 == 1

macro with_qsub_env(expr::Expr)
    mktempdir() do tmpdir
        cd(tmpdir) do
            info("running tests in: $(pwd())")
            open("qsub", "w") do w
                write(w,"#!/bin/sh\n")
                write(w,"echo Your job 123 blah has been submitted\n")
            end

            chmod("qsub",0o777)

            withenv("PATH" => "$tmpdir:/bin") do 
                eval(expr)
            end
        end
    end
end

@with_qsub_env @test typeof(qsub(`test`)) == QsubCmds.Job


@test QsubCmds.to_shell(`ls`) == "ls"
@test QsubCmds.to_shell(pipeline(`a`,`b`)) == "a | b"
@test QsubCmds.to_shell(pipeline(`a`,"b")) == "a 1> b"
@test QsubCmds.to_shell(pipeline("a",`b`)) == "b 0< a"

# A virtual queue without explicit queue parameter should use the default queue:
@test QsubCmds.queue_parameter(virtual_queue(42)) == ""

# A virtual queue with one specific queue should always specify that queue:
vq1 = virtual_queue(100, ["1"]) 
@test QsubCmds.queue_parameter(vq1) == "-q 1" 
push!(vq1.jobs,QsubCmds.Job("1","","",""))
@test QsubCmds.queue_parameter(vq1) == "-q 1" 

# A virtual quque initialized with more than one queue should alternate between queues in round robin fashion: 
vq2 = virtual_queue(100, ["1","2"]) 

observed_queues = []
for i in 1:10
    push!(vq2.jobs,QsubCmds.Job("1","","",""))
    push!(observed_queues,QsubCmds.queue_parameter(vq2))
end

@test all(map(x->x∈["-q 1","-q 2"], observed_queues))

for i in 2:10
    @test observed_queues[i-1] != observed_queues[i] 
end



