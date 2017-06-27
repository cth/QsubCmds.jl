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
#@test QsubCmds.to_shell(pipeline(`a`,"b")) == "a > b"
@test QsubCmds.to_shell(pipeline("a",`b`)) == "b 0< a"
