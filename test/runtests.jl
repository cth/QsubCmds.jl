using QsubCmds 
using Base.Test

# write your own tests here
@test 1 == 1


macro with_qsub_env(expr::Expr)
    mktempdir() do tmpdir
        cd(tmpdir) do
            info("running tests in: $(pwd())")
            open("qsub", "w") do w
                write(w,"echo Your job 123 blah has been submitted\n")
            end
            chmod("qsub",755)
            withenv("PATH" => tmpdir) do  
                eval(expr)
            end
        end
    end
end

@with_qsub_env @test typeof(qsub(`test`)) == QsubCmds.Job 


