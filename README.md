### ClusterSubmitExternal.jl

ClusterSubmitExternal.jl is package for Julia intented to make it easy to submit 
"shell scripts" represented as Julia external commands, i.e., shell commands
in backticks.  

Currently, only Sun Grid Engine is supported, but in the future other cluster
managements systems may be supported too.

For now, this is a naive bare-bones naive approach. Unlike
 [ClusterManagers.jl](https://github.com/JuliaParallel/ClusterManagers.jl),
 which supports full distributed julia code and relies on starting remote
 workers, this approach it is _only_ intended 
to submit Julia encapsulated _external commands_ (shell commands ) through the cluster manager directly
 rather than through Julia workers. It works by translating the external commands
to a shell script with suitable directives for the queue submission system. 

### Example usage:

Considering the [pipeline example from the Julia manual](http://docs.julialang.org/en/release-0.4/manual/running-external-programs/#pipelines)

```julia
myjob=pipeline(`do_work`, stdout=pipeline(`sort`, "out.txt"), stderr="errs.txt")
```

This can be submitted run as a cluster job using to using:

```julia
jobid=qsub(myjob)
```

What happens is that a shell script will be created and launched using the cluster submission program, e.g., `qsub`. 
This will immediately return the job-id. To wait for the job to finish, use `qwait`, e.g., 

```julia
qwait(jobid)
```

It is possible to define dependencies and to parse arbitrary options to `qsub`.

```julia
jobid=qsub(myjob2, depends=[myjob1], options=["-l pe smp 4"])
```
