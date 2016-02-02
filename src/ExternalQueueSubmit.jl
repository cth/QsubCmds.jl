# Submission of external commands via Sun Grid Engine 
# Christian Theil Have, 2016.

module ExtQueueSubmit
	export qsub, qwait
	import Base.Cmd,Base.OrCmds,Base.AndCmds,Base.CmdRedirect

	macro R_str(s)
	    s
	end

	# Conversion of `external` commands in backticks to shell runable commands
	to_shell(cmd::Cmd) = join(cmd.exec," ")
	to_shell(cmd::OrCmds) = string(to_shell(cmd.a), " | ", to_shell(cmd.b)) 
	to_shell(cmd::AndCmds) = string(to_shell(cmd.a), " & ", to_shell(cmd.b), " & ") 
	to_shell(cmd::CmdRedirect) = string(to_shell(cmd.cmd), " ", cmd.stream_no, "> ", cmd.handle.filename)  

	# Very rudimentary qsub functionality

	function qsub(commands::Array{Union{Cmd,OrCmds,AndCmds,CmdRedirect}}, directory=(), depend="", options=[]) 
		if depend != ""
			depend = "-hold_jid $depend "
		end

		if directory == ()
			directory = pwd()
		end
		
		julia_executable=readlink("/proc/self/exe") # FIXME: Only works on linux

		# Create a script
		script=tempname()
		open(script,"w") do file
			write(file,string(R"#$ ","-S /bin/bash\n"))
			write(file,string(R"#$ -cwd","\n"))
			write(file,map(x -> string(R"#$ ", x), options))
			write(file,map(x -> string(to_shell(x),"\n"),commands))
		end 

		# Run script and get JID
		current_directory=pwd()
		println(directory)
		cd(directory)
		output=readall(`qsub $script`)
		cd(current_directory)

		rx=r"Your job ([0-9]+) .* has been submitted"
		if ismatch(rx, output)
			match(rx,output)[1]
		end
	end

	# Wait for job to terminate
	qwait(jid) = try
		while true
			# This return 1 if process does not exists (e.g. if finished)
			# in which case run throw a ProcessExited(1) exception
			run(`qstat -j $jid`) 
		end
	catch 
	end

	qsub(cmd::Union{Cmd,OrCmds,AndCmds,CmdRedirect}, rest...) = qsub([cmd],rest)
end
