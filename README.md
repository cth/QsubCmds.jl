### ClusterSubmitExternal.jl

ClusterSubmitExternal.jl is package for Julia intented to make it easy to submit 
"shell scripts" represented as Julia external commands, i.e., shell commands
in backticks.  

Currently, only Sun Grid Engine is supported, but in the future other cluster
managements systems may be supported too.

For now, this is a naive bare-bones approach. Unlike
 [ClusterManagers.jl](https://github.com/JuliaParallel/ClusterManagers.jl),
 which supports full distributed julia code and relies on starting remote
 workers, this approach it is _only_ intended 
to run Julia encapsulated _external commands_ (shell commands ) on a HPC cluster and does this through the cluster queue management software directly rather than through Julia workers. It works by translating the Julia encapsulated external commands
to a shell script with suitable directives for the queue submission system. 

### Example usage:

Considering the [pipeline example from the Julia manual](http://docs.julialang.org/en/release-0.4/manual/running-external-programs/#pipelines)

```julia
myjob=pipeline(`do_work`, stdout=pipeline(`sort`, "out.txt"), stderr="errs.txt")
```

External commands like these, can via this package be submitted run as a cluster job using the `qsub` function,

```julia
jobid=qsub(myjob)
```

What happens is that a shell script will be created and launched using the cluster submission program, e.g., `qsub`. 
This will immediately return the `jobid`. To wait for the job to finish, use `qwait`, e.g., 

```julia
qwait(jobid)
```

It is possible to specify dependencies, i.e., jobs that must finish before another can commence, and to parse arbitrary options to `qsub` like in the example below:

```julia
jobid=qsub(myjob2, depends=[myjob1], options=["-l pe smp 4"])
```
