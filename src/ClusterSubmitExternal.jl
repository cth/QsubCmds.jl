# Submission of external commands via Sun Grid Engine 
# Christian Theil Have, 2016.

module ClusterSubmitExternal
	export qsub, qwait, qerr, qout
	import Base.Cmd,Base.OrCmds,Base.AndCmds,Base.CmdRedirect,Base.AbstractCmd

	macro R_str(s)
	    s
	end

	"Conversion of `external` commands in backticks to shell runable commands"
	to_shell(cmd::Cmd) = join(cmd.exec," ")
	to_shell(cmd::OrCmds) = string(to_shell(cmd.a), " | ", to_shell(cmd.b)) 
	to_shell(cmd::AndCmds) = string(to_shell(cmd.a), " & ", to_shell(cmd.b), " & ") 
	to_shell(cmd::CmdRedirect) = string(to_shell(cmd.cmd), " ", cmd.stream_no, "> ", cmd.handle.filename)


	"Create an array of commands, where AndCmds are "
 	collect_commands(cmd::Cmd) = [ cmd ]
 	collect_commands(cmd::OrCmds) =  [ cmd ] 
 	collect_commands(cmd::AndCmds) = [ collect_commands(cmd.a) ; collect_commands(cmd.b) ]

	type QsubError <: Exception
		var::ASCIIString
	end
	Base.showerror(io::IO, e::QsubError) = print(io, e.var);

	type Job
		id::ASCIIString
		script::ASCIIString
		stderr::Nullable{ASCIIString}
		stdout::Nullable{ASCIIString}
	end

	"Returns a list of available parallel environments"
	parallel_environments() =  split(chomp(readall(`qconf -spl`)),"\n")

	"""
	Creates a script with directives for qsub and submits script to the a cluster queuing system.
	"""
	function qsub(commands::Array{Cmd} ; 
		basedir=pwd(),
		stderr=Nullable{ASCIIString}(),
		stdout=Nullable{ASCIIString}(),
		parallel_environment=Nullable{ASCIIString}(),
		vmem_mb=Nullable{UInt64}(),
		cpus=Nullable{UInt64}(),
		depends=Array{Job,1}(),
		options=Array{ASCIIString,1}())

		if length(depends) > 0 
			depends_str = join(map(x -> x.id, depends), ",")
			push!(options, "-hold_jid $depends_str")
		end

		if !isnull(cpus)
			if isnull(parallel_environment)
				parallel_environment=first(parallel_environments())
			end	
			push!(options, "-pe $parallel_environment $cpus")  
		end

		push!(options, isnull(stderr) ? "-e /dev/null" : "-e $stderr")
		push!(options, isnull(stdout) ? "-o /dev/null" : "-o $stderr")

		if !isnull(vmem_mb) 
			push!(options, "-l h_vmem=$(vmem_mb)M") 
		end

		push!(options, "-cwd") # Always run relative to given directory

		# Create a script
		script=tempname()
		open(script,"w") do file
			write(file,string(R"#$ ","-S /bin/bash\n"))
			write(file,map(x -> string(R"#$ ", x, "\n"), options))
			write(file,map(x -> string(to_shell(x),"\n"),commands))
		end 

		# Run script and get Job id
		current_directory=pwd()
		cd(basedir)
		output=readall(`qsub $script`)
		cd(current_directory)

		rx=r"Your job ([0-9]+) .* has been submitted"
		if ismatch(rx, output)
			Job(match(rx,output)[1], script, stderr, stdout)
		else
			throw(QsubError(output))
		end	
	end

	qsub(cmd::Union{Cmd,OrCmds,AndCmds,CmdRedirect} ; rest...) = qsub(collect_commands(cmd) ; rest...)


	"Return the filename of the file associated with the stderr output from job"
	stderr(job::Job) = isnull(job.stderr) ? throw(QsubError(string("No stderr associated with job ", job.id))) : job.stderr

	"Return the filename of the file associated with the stdout output from job"
	stdout(job::Job) = isnull(job.stdout) ? throw(QsubError(string("No stdout associated with job ", job.id))) : job.stdout

	function qstat(job::Job)
		try
			readall(`qstat -j $(job.id)`) 
		end
	end

#	function qstat(job::Job, key::ASCIIString)
#		try
#			lines = split(readall(`qstat -j $(job.id)`),"\n") 
#			if ismatch(, output)
#		end
#	end
#

	# Wait for job to terminate
	function qwait(job::Job) 
		try
			backoff = 1
			while true
				# This return 1 if process does not exists (e.g. if finished)
				# in which case run throw a ProcessExited(1) exception
				readall(pipeline(`qstat -j $(job.id)`,stderr=STDOUT)) 
				running = true
				sleep(backoff+=1)
			end
		end
		println(string("job ", job.id, finished))
	end
end
