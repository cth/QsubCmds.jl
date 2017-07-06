### QsubCmds

QsubCmds is package for Julia intented to make it easy to submit 
"shell scripts" represented as Julia external commands on a HPC cluster.


This is a naive bare-bones approach. Unlike
 [ClusterManagers.jl](https://github.com/JuliaParallel/ClusterManagers.jl),
 which supports full distributed julia code and relies on starting remote
 workers, this approach it is _only_ intended 
to run Julia encapsulated _external commands_ (shell commands ) on a HPC cluster and does this through the cluster queue management software directly rather than through Julia workers. It works by translating the Julia encapsulated external commands
to a shell script with suitable directives for the queue submission system. 


Currently, only Sun Grid Engine is supported, but in the future other cluster management systems may be supported too.

### Example usage:

Considering the [pipeline example from the Julia manual](http://docs.julialang.org/en/release-0.4/manual/running-external-programs/#pipelines)

```julia
myjob=pipeline(`do_work`, stdout=pipeline(`sort`, "out.txt"), stderr="errs.txt")
```

External commands like these, can via this package be submitted run as a cluster job using the `qsub` function,

```julia
job=qsub(myjob)
```

This wil not block, but will immediately return the `job`. Usually, this is what one would want since such jobs
may be rather time-consuming. However, to wait for the job to finish, we can use `qwait` which blocks until 
the job finished, e.g., 

```julia
qwait(job)
```

The polling of the job-status will happen at increasing intervals which is incremented by one second
for each polling. To poll in a non-blocking fashion you can use

```julia
isrunning(job)
```

#### Composing a series of commands

A job can consist of one or more commands. Commands can be used stitched together using the `&` operator,e.g., 

```julia
qsub(`echo hello` & `echo world`)
```

The ampersand operator will, in this context, result in the two commands to be run in sequence, i.e, `echo world` will
run after `echo hello` has finished. This is unlike the usual `&` semantics which puts commands in the background.

 
#### Options 

The `qsub` function accepts a number of optional options:

 - `name`::String short name of job (to be used by qsub)
 - `stderr`::String points to a file where stderr from the job is logged. 
 - `stdout`::String points to a file where stdout from the job is logged. 
 - `environment`::String One of the available parallel environments, e.g., `smp`. 
 - `queue`::String specify which queue to use.
 - `vqueue`::VirtualQueue specify virtual queue to use fore throttling 
 - `vmem_mb`::UInt64 Specify how many megabytes of virtual memory to allocate for the job.  
 - `cpus`::UInt64 How many CPUs to allocate for job. 
 - `depends`: An array of submitted jobs that must finished before present job will be run. 
 - `options`: An array of strings that may contain extra options that will be passed unfiltered directly to the underlying qsub program.

For instance, if you want to specify a job that needs four processors in the parallel environment `smp`, then you
could specify this as

```julia
job=qsub(`command`, cpus=4, parallel_environment="smp") 
```

or you could specify this through the extra `options`:

```julia
job=qsub(`command`, options=["-pe smp 4"]) 
```

It is also possible to mix and match both the standard (typed) options and the extra passthrough options, but currently
no redundancy checks etc are performed. 

#### Dependencies

It is also possible to specify dependencies, i.e., jobs that must finish before another can commence, and to parse options to `qsub` like in the example below:

```julia
job=qsub(myjob3, depends=[myjob1,myjob2])
```

This specificies that the two jobs `myjob1` and `myjob2` must finish, before `myjob3` is started on the cluster.
#### Queues

Using the queue argument to `qsub` it possible to submit to a particular queue. 
This may be a system queue (defined by the grid engine) or a virtual queue defined
by the user (see later). 

It is possible to get a list of the system queues using the command

```julia
list_queues() 
```

##### Virtual queues

It is possible limit how many jobs run concurrently using a virtual queue. 
This can be useful if jobs are IO intensive and access the same resource.
A virtual queue is created using the command

```julia
my_queue = virtual_queue(10)
```

where the argument is maximum number of jobs to run concurrently on this queue (10 in the example).
To submit a job using the queue, you specify the virtual queue using the `vqueue` argument of `qsub`, e.g., 

```julia
qsub(`do something`, queue=my_queue)
```

and the job will be associated with the queue.



#### Other functionality

Submitted jobs can be deleted using `qdel`:

```
qdel(myjob)
``` 

Finally, it is possible to get the `qstat` information on a submitted job (as a Dict):

```julia
qstat(myjob)
```



