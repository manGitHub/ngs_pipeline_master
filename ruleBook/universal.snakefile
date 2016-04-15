############
##	Tiled data file(.tdf)
############
rule BAM2TDF:
	input:
		bam="{base}/{sample}/{sample}.{aligner}.final.bam",
		bam_bai="{base}/{sample}/{sample}.{aligner}.final.bam.bai"
	output:
		"{base}/{sample}/{sample}.{aligner}.final.bam.tdf"
	version: config['igvtools']
	params:
		rulename        = "bamtdf",
		ref             = config["reference"],
		batch           = config[config['host']]['job_igvtools']
	shell:  """
	#######################
	module load igvtools/{version}

	igvtools count {input.bam} {output} {params.ref}
	#######################
	"""