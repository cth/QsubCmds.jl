### QsubCmds

QsubCmds is package for Julia intented to make it easy to submit 
"shell scripts" represented as either Julia external or string encapsulated commands on a HPC cluster.


This is a naive bare-bones approach. Unlike
 [ClusterManagers.jl](https://github.com/JuliaParallel/ClusterManagers.jl),
 which supports full distributed julia code and relies on starting remote
 workers, this approach it is _only_ intended 
to run Julia encapsulated _external commands_ (shell commands ) on a HPC cluster and does this through the cluster queue management software directly rather than through Julia workers. It works by translating the Julia encapsulated external commands
to a shell script with suitable directives for the queue submission system. 
See the blogpost [Shelling out sucks](https://julialang.org/blog/2012/03/shelling-out-sucks) to understand the motivation of Julias builtin shell commands.
Since, this approach is going to "shelling out" in the qsub process anyway, it is also possible to provide commands as plain strings (no meta-character brittleness protection provided). 


Currently, Sun Grid Engine is supported, torque is supported to a limited degree, but in the future other cluster management systems may be supported too.

The library attempts to auto-detect which cluster management system is installed and will then try to use that. 

### Example usage:

Considering the [pipeline example from the Julia manual](http://docs.julialang.org/en/release-0.4/manual/running-external-programs/#pipelines)

```julia
myjob=pipeline(`do_work`, stdout=pipeline(`sort`, "out.txt"), stderr="errs.txt")
```

Julia shell commands will be compiled into suitable shell script strings handling escaping in a sensible way. 


External commands like these, can via this package be submitted run as a cluster job using the `qsub` function,

```julia
job=qsub(myjob)
```

The `qsub` command is also capable of taking `String`s or an Array (any mix of strings/T<:AbstractCmd} which will launch a job-array rather than just a single job.

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


### Job arrays

If `qsub` is called with an array of commands, it will create a job-array running all these jobs in parallel (to the extend possible) on the cluster.
This is preferred to launching many qsub commands, e.g., from within a loop since it will reduce the load on the cluster management system.

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



