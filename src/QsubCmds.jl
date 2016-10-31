# Submission of external commands via Sun Grid Engine 
# Christian Theil Have, 2016.

module QsubCmds
	export qsub, qwait, qstat, qdel, qthrottle, stderr, stdout, isrunning, isfinished
	import Base.Cmd,Base.OrCmds,Base.AndCmds,Base.CmdRedirect

	type Job
		id::String
		script::String
		stderr::Nullable{String}
		stdout::Nullable{String}
	end

	macro R_str(s)
	    s
	end

	"version of isnull that works for all types and returns false unless it it Nullable()"
	safeisnull(x) = try isnull(x) catch isnull(Nullable(x)) end

	"Conversion of `external` commands in backticks to shell runable commands"
	to_shell(cmd::Cmd) = join(cmd.exec," ")
	to_shell(cmd::OrCmds) = string(to_shell(cmd.a), " | ", to_shell(cmd.b)) 
	to_shell(cmd::AndCmds) = string(to_shell(cmd.a), " & ", to_shell(cmd.b), " & ") 
	to_shell(cmd::CmdRedirect) = string(to_shell(cmd.cmd), " ", cmd.stream_no, "> ", cmd.handle.filename)

	"Create an array of commands, where AndCmds are "
 	collect_commands(cmd::Cmd) = [ to_shell(cmd) ]
 	collect_commands(cmd::OrCmds) =  [ to_shell(cmd) ] 
 	collect_commands(cmd::AndCmds) = [ collect_commands(cmd.a) ; collect_commands(cmd.b) ]

	type QsubError <: Exception
		var::String
	end
	Base.showerror(io::IO, e::QsubError) = print(io, e.var);

	"Returns a list of available parallel environments"
	parallel_environments() =  split(chomp(readstring(`qconf -spl`)),"\n")

	"""
	Creates a script with directives for qsub and submits script to the a cluster queuing system.

	`qsub` is normally called with any `AbstractCmd` argument, which can be constructed using 
	backtick notation., e.g., 

	    qsub(cipeline(`echo hello`,`tr 'h' 'H'`) & `echo world`)

	alternatively you can call it by suplying an array of commands as straight strings:

	    qsub(["echo hello|tr 'h' 'H'", "echo world"])

	The qsub command additionally takes a number of optional named arguments:

	 - `name`: A user specified  `String` identifier for the job
	 - `stderr`::String points to a file where stderr from the job is logged. 
	 - `stdout`::String points to a file where stdout from the job is logged. 
	 - `environment`::String One of the available parallel environments, e.g., `smp`. 
	 - `queue`::String specify which queue to use.
	 - `vmem_mb`::UInt64 Specify how many megabytes of virtual memory to allocate for the job.  
	 - `cpus`::UInt64 How many CPUs to allocate for job. 
	 - `depends`: An Array of submitted jobs that must finished before present job will be run. 
	 - `options`: An Array  of strings that may contain extra options that will be passed unfiltered directly to the underlying qsub program.
	"""
	function qsub(commands::Array{String,1} ; 
		basedir=pwd(),
		name=Nullable{String}(),
		stderr=Nullable{String}(),
		stdout=Nullable{String}(),
		environment=Nullable{String}(),
		queue=Nullable{String}(),
		vmem_mb=Nullable{UInt64}(),
		cpus=Nullable{UInt64}(),
		showscript=false,
		depends=Array{Job,1}(),
		appendlog=false,
		options=Array{String,1}())

		if length(depends) > 0 
			depends_str = join(map(x -> x.id, depends), ",")
			push!(options, "-hold_jid $depends_str")
		end


		if !safeisnull(cpus)
			if safeisnull(environment)
				environment=first(parallel_environments())
			end	
			push!(options, "-pe $environment $cpus")  
		end

		if !safeisnull(queue)
			push!(options,"-q $queue")	
		end

		if !appendlog
			for i in [ stderr stdout ]
				!safeisnull(i) && isfile(i) && rm(i)
			end
		end

		push!(options, safeisnull(stderr) ? "-e /dev/null" : string("-e ", stderr))
		push!(options, safeisnull(stdout) ? "-o /dev/null" : string("-o ", stdout))

		if !safeisnull(vmem_mb)
			push!(options, "-l h_vmem=$(vmem_mb)M") 
		end

		push!(options, "-cwd") # Always run relative to given directory


		script=tempname()
		push!(options, string("-N ", safeisnull(name) ? basename(script) : name)) 

		# Create a script
		open(script,"w") do file
			write(file,string(R"#$ ","-S /bin/bash\n"))
			write(file,map(x -> string(R"#$ ", x, "\n"), options))
			write(file,map(x -> string(x,"\n"),commands))
		end 

		# Run script and get Job id
		current_directory=pwd()
		cd(basedir)
		output=readstring(`qsub $script`)
		cd(current_directory)

		rx=r"Your job ([0-9]+) .* has been submitted"
		if ismatch(rx, output)
			Job(match(rx,output)[1], script, stderr, stdout)
		else
			throw(QsubError(output))
		end
	end

	qsub(cmd::Union{Cmd,OrCmds,AndCmds,CmdRedirect} ; rest...) = qsub(collect_commands(cmd) ; rest...)

	# Why does this work?
	#qsub(cmd::Array{Union{Cmd,OrCmds,AndCmds,CmdRedirect},1} ; rest...) = qsub(collect_commands(cmd) ; rest...)


	"`qthrottle(bottlenecksize, cmds)` - Qsub an array of commands, so that no more that `bottlenecksize` will be running at any given time" 
	# Does this by creating artificial dependencies between jobs 
	function qthrottle(bottlenecksize::UInt64, commands::Array ; rest...)
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
		try
			str = readstring(`qstat -j $(job.id)`) 
			re = r"(\S+):\s+(\S+)$"
			f(x) = ismatch(re,x) ? (m=match(re,x);Dict(m[1]=>m[2])) : Dict()
			foldl(merge,Dict(),map(f,split(str,"\n")))
		end
	end

	"Returns true if `job` is running"
	isrunning(job::Job) = try 
		readstring(pipeline(`qstat -j $(job.id)`,stderr=STDOUT))
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
				readstring(pipeline(`qstat -j $(job.id)`,stderr=STDOUT)) 
				running = true
				sleep(backoff+=1)
			end
		end
		println(string("job ", job.id, "finished"))
	end
end
