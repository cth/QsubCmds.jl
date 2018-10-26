# Submission of external commands via Sun Grid Engine 
# Christian Theil Have, 2016.

module QsubCmds
	export qsub, qwait, qstat, qdel, qthrottle, isrunning, isfinished, virtual_queue
	import Base.Cmd,Base.OrCmds,Base.AndCmds,Base.CmdRedirect

	mutable struct Job
		id::String
		script::String
		stderr::String
		stdout::String
	end

    mutable struct VirtualQueue
		size::Int64
		jobs::Array{Job,1}
        queues::Array{String,1}
    end

    println("version 1")

	virtual_queue(size) = VirtualQueue(size,Array{Job,1}(),[])
	virtual_queue(size,queues::Array{String,1}) = VirtualQueue(size,Array{Job,1}(),queues)

	macro R_str(s)
	    s
	end

    queue_parameter(q) = (length(q.queues) > 0) ? string("-q ", q.queues[1+((length(q.jobs)+1) % length(q.queues))]) : ""

	"Conversion of `external` commands in backticks to shell runable commands"
    to_shell(cmd::String) = cmd
	to_shell(cmd::Cmd) = join(cmd.exec," ")
	to_shell(cmd::OrCmds) = string(to_shell(cmd.a), " | ", to_shell(cmd.b)) 
	to_shell(cmd::AndCmds) = string(to_shell(cmd.a), " & ", to_shell(cmd.b), " & ")
	to_shell(cmd::CmdRedirect) = string(to_shell(cmd.cmd), " ", cmd.stream_no, cmd.stream_no==0 ? "< " : "> ", cmd.handle.filename)

	"Create an array of commands, where AndCmds are "
 	collect_commands(cmd::Cmd) = [ to_shell(cmd) ]
 	collect_commands(cmd::OrCmds) =  [ to_shell(cmd) ] 
 	collect_commands(cmd::AndCmds) = [ collect_commands(cmd.a) ; collect_commands(cmd.b) ]

    "Join an array of commands to a single command - useful for breaking up commands into several lines"
    joincmds(cmds) = foldl((cmd1,cmd2)->`$cmd1 $cmd2`, ``, cmds)

	mutable struct QsubError <: Exception
		var::String
	end
	Base.showerror(io::IO, e::QsubError) = print(io, e.var);



	"Returns a list of available parallel environments"
	parallel_environments() =  split(chomp(read(`qconf -spl`,String)),"\n")


    "Returns a list of queues provided by the queuing system"
    queues()  = error("TODO") 

    
    "Detect the type of cluster"
    function detect_cluster_type()
        qsub_binary = split(read(`whereis qsub`,String))[2]


        if !isfile(qsub_binary)
            throw("QsubCmds: Could not find the qsub command on the system!")
        end

        qsub_binary_strings = read(`strings $qsub_binary`,String)

        if occursin(r"libtorque", qsub_binary_strings)
            :torque
        elseif occursin(r"gridengine", qsub_binary_strings)
            :gridengine
        else
            throw("Unsupported type of cluster")
        end
    end



	"""
	Creates a script with directives for qsub and submits script to the a cluster queuing system.

	`qsub` is normally called with any `AbstractCmd` argument, which can be constructed using 
	backtick notation., e.g., 

	    qsub(pipeline(`echo hello`,`tr 'h' 'H'`) & `echo world`)

	alternatively you can call it by suplying an array of commands as straight strings:

	    qsub(["echo hello|tr 'h' 'H'", "echo world"])

	The qsub command additionally takes a number of optional named arguments:

	 - `name`: A user specified  `String` identifier for the job
	 - `stderr`::String points to a file where stderr from the job is logged. 
	 - `stdout`::String points to a file where stdout from the job is logged. 
	 - `environment`::String One of the available parallel environments, e.g., `smp`. 
	 - `queue`::Union{String,VirtualQueue} specify which queue to use.
	 - `vmem_mb`::UInt64 Specify how many megabytes of virtual memory to allocate for the job.  
	 - `cpus`::UInt64 How many CPUs to allocate for job. 
	 - `depends`: An Array of submitted jobs that must finished before present job will be run. 
	 - `options`: An Array  of strings that may contain extra options that will be passed unfiltered directly to the underlying qsub program.
	"""
	function qsub(commands::Array{T,1} ; rest...) where T<:Union{Base.AbstractCmd,String}
        cluster_type=detect_cluster_type()

        commands = map(to_shell,commands)

        if cluster_type == :torque
           qsub_torque(commands ; rest...) 
        elseif cluster_type == :gridengine
            qsub_gridengine(commands ; rest...)
        end
	end

	qsub(cmd::Union{Cmd,OrCmds,AndCmds,CmdRedirect,String} ; rest...) = qsub([cmd] ; rest...)

    function qsub_torque(commands::Array{String,1} ; 
		basedir=pwd(),
		name=nothing,
		stderr="/dev/null",
		stdout="/dev/null",
		queue=VirtualQueue(1,Array{Job,1}(),Array{String,1}()),
        showscript=false,
        appendlog=false,
        depends=Array{Job,1}(),
        options=Array{String,1}()) 

		if !appendlog
			for i in [ stderr stdout ]
                if i != nothing &&  isfile(i)
                    rm(i)
                end
			end
		end

		push!(options, stderr==nothing ? "-e /dev/null" : string("-e ", stderr))
		push!(options, stdout==nothing ? "-o /dev/null" : string("-o ", stdout))

        commands = map(to_shell,commands) 


		# Add dependencies from specified queue if queue is full
		if length(queue.jobs) >= queue.size 
			push!(depends,queue.jobs[(1+length(queue.jobs))-queue.size])
		end

		if length(depends) > 0 
			depends_str = join(map(x -> x.id, depends), ",")
			push!(options, "-hold_jid $depends_str")
		end

        #push!(options,queue_parameter(queue))
        
		script=tempname()
		push!(options, string("-N ", name==nothing ? basename(script) : name)) 

		# Create a script
		open(script,"w") do file
			write(file,string(R"#PBS ","-S /bin/bash\n"))
            for x in options
			    write(file,string(R"#PBS ", x, "\n"))
            end
			write(file,string(R"#PBS ","-t 1-$(length(commands))\n"))

		    write(file,"cd $basedir\n") # Always run relative to given directory
            for i in 1:length(commands)
			    write(file,string("([ \$PBS_ARRAYID -eq  $i ] && ", to_shell(commands[i]),") ||"))
            end
            write("echo done\n")
		end 

		# Run script and get Job id
		current_directory=pwd()
		cd(basedir)
		output=read(`qsub $script`,String)
		cd(current_directory)

		push!(queue.jobs,Job(chomp(output), script, stderr, stdout))
		return last(queue.jobs)
    end

	function qsub_gridengine(commands::Array{String,1} ; 
		basedir=pwd(),
		name=nothing,
		stderr="/dev/null",
		stdout="/dev/null",
		environment=nothing,
		vmem_mb=nothing,
		cpus=nothing, 
		queue=VirtualQueue(1,Array{Job,1}(),Array{String,1}()),
        showscript=false,
        depends=Array{Job,1}(),
        appendlog=false,
        options=Array{String,1}()) 

		if !appendlog
			for i in [ stderr stdout ]
                if i != nothing &&  isfile(i)
                    rm(i)
                end
			end
		end


        if cpus != nothing 
            if environment == nothing
                environment=first(parallel_environments())
            end
            push!(options, "-pe $environment $cpus")  
        end

		push!(options, stderr==nothing ? "-e /dev/null" : string("-e ", stderr))
		push!(options, stdout==nothing ? "-o /dev/null" : string("-o ", stdout))

		if vmem_mb != nothing 
            push!(options, "-l h_vmem=$(vmem_mb)M") 
        end

		push!(options, "-cwd") # Always run relative to given directory

		# Add dependencies from specified queue if queue is full
		if length(queue.jobs) >= queue.size 
			push!(depends,queue.jobs[(1+length(queue.jobs))-queue.size])
		end

		if length(depends) > 0 
			depends_str = join(map(x -> x.id, depends), ",")
			push!(options, "-hold_jid $depends_str")
		end

  
        push!(options,queue_parameter(queue))
        
		script=tempname()
		push!(options, string("-N ", name==nothing ? basename(script) : name)) 



		# Create a script
		open(script,"w") do file
			write(file,string(R"#$ ","-S /bin/bash\n"))

            for x in options
			    write(file,string(R"#$ ", x, "\n"))
            end
			write(file,string(R"#$ ","-t 1-$(length(commands))\n"))
            for i in 1:length(commands)
			    write(file,string("[ \$SGE_TASK_ID -eq  $i ] && ", to_shell(commands[i]),"\n"))
            end
		end 

		# Run script and get Job id
		current_directory=pwd()
		cd(basedir)
		output=read(`qsub $script`,String)
		cd(current_directory)

		rx=r"Your job-array ([0-9]+).* has been submitted"
		if occursin(rx, output)
			push!(queue.jobs,Job(match(rx,output)[1], script, stderr, stdout))
			return last(queue.jobs)
		else
			throw(QsubError(output))
		end
    end


	# Does this by creating artificial dependencies between jobs 
	"`qthrottle(bottlenecksize, cmds)` - Qsub an array of commands, so that no more that `bottlenecksize` will be running at any given time" 
	function qthrottle(bottlenecksize::UInt64, commands::Array ; rest...)
		warn("qthrottle is deprecated. Use a virtual queue instead")
		submitted_jobs = []
		for i in 1:length(commands) 
			cmd = (typeof(commands[i]) <: Base.AbstractCmd) ? commands[i] : [ commands[i] ]
			if i <= bottlenecksize
				push!(submitted_jobs, qsub(cmd; rest...))
			else
				deps = [ submitted_jobs[i-bottlenecksize] ]
				push!(submitted_jobs, qsub(cmd; depends=deps , rest...))
			end
		end
		submitted_jobs
	end

	"Return the filename of the file associated with the stderr output from job"
	stderr(job::Job) = isnull(job.stderr) ? throw(QsubError(string("No stderr associated with job ", job.id))) : job.stderr

	"Return the filename of the file associated with the stdout output from job"
	stdout(job::Job) = isnull(job.stdout) ? throw(QsubError(string("No stdout associated with job ", job.id))) : job.stdout

	"`qstat(job::Job)` return job statistics for job as a `Dict`"
	function qstat(job::Job)
        cluster_type=detect_cluster_type()
		try
            if cluster_type == :gridengine
			    str = read(`qstat -j $(job.id)`,String) 
			    re = r"(\S+):\s+(\S+)$"
            elseif cluster_type == :torque
			    str = read(`qstat -f $(job.id)`,String) 
			    re = r"\s+(\S+)\s+=\s+(\S+)$"
            end
			f(x) = occursin(re,x) ? (m=match(re,x);Dict(m[1]=>m[2])) : Dict()
			foldl(merge,map(f,split(str,"\n"));init=Dict())
		catch
		end
	end

    "`suspend a `Job` or `VirtualQueue`"
    suspend(job::Job) = run(`qmod -sj $(job.id)`)
    suspend(q::VirtualQueue) = suspend.(q.jobs)

    "`unsuspend a `Job` or `VirtualQueue`"
    unsuspend(job::Job) = run(`qmod -usj $(job.id)`) 
    unsuspend(q::VirtualQueue) = unsuspend.(q.jobs)

	"Returns true if `job` is running"
	isrunning(job::Job) = try 
		read(pipeline(`qstat -j $(job.id)`,stderr=STDOUT),String)
		true
	catch
		false
	end

	isfinished(x) = !isrunning(x)

	"`qdel(job)`: Delete a submitted `job`"
	qdel(job::Job) = run(`qdel $(job.id)`)

	"""
	`qwait(job::Job)`: Waits for `job` to terminate (blocks). The polling interval increases linearly.
	"""
	function qwait(job::Job) 
		try
			backoff = 1
			while true
				# This return 1 if process does not exists (e.g. if finished)
				# in which case run throw a ProcessExited(1) exception
				read(pipeline(`qstat -j $(job.id)`,stderr=STDOUT),String) 
				running = true
				sleep(backoff+=1)
			end
		catch
		end
		println(string("job ", job.id, "finished"))
	end
end
