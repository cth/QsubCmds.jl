### ClusterSubmitExternal.jl

ExtQueueSubmit.jl is package for Julia intented to make it easy to submit 
"shell scripts" represented as julia external commands, i.e., shell commands
in backticks.  

Currently, only Sun Grid Engine is supported, but in the future other cluster
managements systems may be supported too.

This package differs from [ClusterManagers.jl](https://github.com/JuliaParallel/ClusterManagers.jl).
For now, this is a bare-bones naive approach. It is _only_ intended 
to submit "shell script" commands to the cluster and does support native
Julia constructs. It works by translating one or more external commands
to a shell script suitable for the grid engine to run. 

It then launches this script through the queue submission program, i.e., `qsub`. This has
the advantage that it not necessary to have Julia available on cluster worker nodes, and in
that avoids overhead related to starting up julia processes on the workers.


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
jobid=qsub(myjob2, depends=myjob1, options=["-l pe smp 4"])
```
