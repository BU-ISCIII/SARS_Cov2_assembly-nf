#!/usr/bin/env nextflow

/*
========================================================================================
                  SARS-Cov2 Illumina SISPA Analysis
========================================================================================
 #### Homepage / Documentation
 https://github.com/BU-ISCIII/SARS_Cov2-nf
 @#### Authors
 Sarai Varona <s.varona@isciii.es>
 Sara Monzon <smonzon@isciii.es>
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
Pipeline overview:
 - 1. : Preprocessing
 	- 1.1: FastQC - for raw sequencing reads quality control
 	- 1.2: Trimmomatic - raw sequence trimming
 - 2. : DeNovo assembly:
  - 2.1 : Spades - De Novo assembly (normal mode and metaSpades mode)
  - 2.2 : Unicycler - De novo assembly
  - 2.3 : Quast - Assembly quality assessment.
  - 2.4 : ABACAS - Assembly contig reordering and draft generation
 - 3. : Assembly Alignment
  - 3.1 : BLAST - Assembly alignment to viral reference
 - 4. Stats & Graphs :
  - 4.1 : PlasmidID - Assembly plot generation
 ----------------------------------------------------------------------------------------
*/

def helpMessage() {
    log.info"""
    =========================================
     BU-ISCIII/SARS_Cov2_assembly-nf : SARS_Cov2 Illumina data analysis using assembly v${version}
    =========================================
    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run SARS_Cov2_assembly-nf/main.nf --reads '*_R{1,2}.fastq.gz' --viral_fasta ../../REFERENCES/NC_045512.2.fasta --viral_gff ../../REFERENCES/NC_045512.2.gff --viral_index '../REFERENCES/NC_045512.2.fasta.*' --blast_db '../REFERENCES/NC_045512.2.fasta.*' --host_fasta --host_fasta /processing_Data/bioinformatics/references/eukaria/homo_sapiens/hg38/UCSC/genome/hg38.fullAnalysisSet.fa --host_index '/processing_Data/bioinformatics/references/eukaria/homo_sapiens/hg38/UCSC/genome/hg38.fullAnalysisSet.fa.*' --amplicons_file ../REFERENCES/nCoV-2019.schemeMod.fasta --outdir ./ -profile hpc_isciii

    Mandatory arguments:
      --reads                       Path to input data (must be surrounded with quotes).
      --viral_fasta                 Path to Fasta reference
      --viral_gff					          Path to GFF reference file. (Mandatory if step = assembly)
      --viral_index                 Path to viral fasta index
      --host_fasta                  Path to host Fasta sequence
      --host_index                  Path to host fasta index
      --blast_db                    Path to reference viral genome BLAST database

    Options:
      --singleEnd                   Specifies that the input is single end reads
      --amplicons_file              Path to amplicons FASTA file.

    Trimming options
      --notrim                      Specifying --notrim will skip the adapter trimming step.
      --saveTrimmed                 Save the trimmed Fastq files in the the Results directory.
      --trimmomatic_adapters_file   Adapters index for adapter removal
      --trimmomatic_adapters_parameters Trimming parameters for adapters. <seed mismatches>:<palindrome clip threshold>:<simple clip threshold>. Default 2:30:10
      --trimmomatic_window_length   Window size. Default 4
      --trimmomatic_window_value    Window average quality requiered. Default 20
      --trimmomatic_mininum_length  Minimum length of reads

    Other options:
      --save_unmapped_host          Save the reads that didn't map to host genome
      --outdir                      The output directory where the results will be saved
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */
params.help = false


// Pipeline version
version = '1.0'

// Show help emssage
if (params.help){
    helpMessage()
    exit 0
}

/*
 * Default and custom value for configurable variables
 */

params.viral_fasta = false
if( params.viral_fasta ){
    viral_fasta_file = file(params.viral_fasta)
    if( !viral_fasta_file.exists() ) exit 1, "Fasta file not found: ${params.viral_fasta}."
}

params.amplicons_file = false
if( params.amplicons_file ){
    amplicons_bed_file = file(params.amplicons_file)
    if ( !amplicons_bed_file.exists() ) exit 1, "Amplicons BAM file not found: $params.amplicons_file"
}

params.host_fasta = false
if( params.host_fasta ){
    host_fasta_file = file(params.host_fasta)
    if( !host_fasta_file.exists() ) exit 1, "Fasta file not found: ${params.host_fasta}."
}


// GFF file
viral_gff = false

if( params.viral_gff ){
    gff_file = file(params.viral_gff)
    if( !gff_file.exists() ) exit 1, "GFF file not found: ${params.viral_gff}."
}

blast_header = file("$baseDir/assets/header_blast.txt")

// Output md template location
output_docs = file("$baseDir/docs/output.md")

// Trimming
// Trimming default
params.notrim = false
// Output files options
params.saveTrimmed = false
// Default trimming options
params.trimmomatic_adapters_file = "\$TRIMMOMATIC_PATH/adapters/NexteraPE-PE.fa"
params.trimmomatic_adapters_parameters = "2:30:10"
params.trimmomatic_window_length = "4"
params.trimmomatic_window_value = "20"
params.trimmomatic_mininum_length = "50"

// SingleEnd option
params.singleEnd = false

// Validate  mandatory inputs
params.reads = false
if (! params.reads ) exit 1, "Missing reads: $params.reads. Specify path with --reads"

if ( ! params.viral_gff ){
    exit 1, "GFF file not provided for assembly step, please declare it with --viral_gff /path/to/gff_file"
}

/*
 * Create channel for input files
 */

// Create channel for input reads.
Channel
    .fromFilePairs( params.reads, size: params.singleEnd ? 1 : 2 )
    .ifEmpty { exit 1, "Cannot find any reads matching: ${params.reads}\nIf this is single-end data, please specify --singleEnd on the command line." }
    .into { raw_reads_fastqc; raw_reads_trimming; raw_reads_trimming_primers }

// Create channel for reference index
if( params.host_index ){
    Channel
        .fromPath(params.host_index)
        .ifEmpty { exit 1, "Host fasta index not found: ${params.host_index}" }
        .set { host_index_files }
}

if( params.viral_index ){
    Channel
        .fromPath(params.viral_index)
        .ifEmpty { exit 1, "Viral fasta index not found: ${params.viral_index}" }
        .into { viral_index_files; viral_index_files_variant_calling }
}

if( params.blast_db ){
    Channel
        .fromPath(params.blast_db)
        .ifEmpty { exit 1, "Viral fasta index not found: ${params.blast_db}" }
        .set { blast_db_files }
}


/*
 * Channel.fromPath("$baseDir/assets/header")
        .set{ blast_header }

 */



// Header log info
log.info "========================================="
log.info " BU-ISCIII/bacterial_wgs_training : WGS analysis practice v${version}"
log.info "========================================="
def summary = [:]
summary['Reads']               = params.reads
summary['Data Type']           = params.singleEnd ? 'Single-End' : 'Paired-End'
summary['Fasta Ref']           = params.viral_fasta
summary['GFF File']            = params.viral_gff
summary['Container']           = workflow.container
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Current home']        = "$HOME"
summary['Current user']        = "$USER"
summary['Current path']        = "$PWD"
summary['Working dir']         = workflow.workDir
summary['Output dir']          = params.outdir
summary['Script dir']          = workflow.projectDir
summary['Save Unmapped']        = params.save_unmapped_host
summary['Save Trimmed']        = params.saveTrimmed
if( params.notrim ){
    summary['Trimming Step'] = 'Skipped'
} else {
    summary['Trimmomatic adapters file'] = params.trimmomatic_adapters_file
    summary['Trimmomatic adapters parameters'] = params.trimmomatic_adapters_parameters
    summary["Trimmomatic window length"] = params.trimmomatic_window_length
    summary["Trimmomatic window value"] = params.trimmomatic_window_value
    summary["Trimmomatic minimum length"] = params.trimmomatic_mininum_length
}
summary['Config Profile'] = workflow.profile
log.info summary.collect { k,v -> "${k.padRight(21)}: $v" }.join("\n")
log.info "===================================="

// Check that Nextflow version is up to date enough
// try / throw / catch works for NF versions < 0.25 when this was implemented
nf_required_version = '0.27.6'
try {
    if( ! nextflow.version.matches(">= $nf_required_version") ){
        throw GroovyException('Nextflow version too old')
    }
} catch (all) {
    log.error "====================================================\n" +
              "  Nextflow version $nf_required_version required! You are running v$workflow.nextflow.version.\n" +
              "  Pipeline execution will continue, but things may break.\n" +
              "  Please run `nextflow self-update` to update Nextflow.\n" +
              "============================================================"
}

/*
 * STEP 1.1 - FastQC
 */
process fastqc {
	tag "$prefix"
	label "small"
	publishDir "${params.outdir}/01-fastQC", mode: 'copy',
		saveAs: {filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

	input:
	set val(name), file(reads) from raw_reads_fastqc

	output:
	file '*_fastqc.{zip,html}' into fastqc_results
	file '.command.out' into fastqc_stdout

	script:

	prefix = name - ~/(_S[0-9]{2})?(_L00[1-9])?(.R1)?(_1)?(_R1)?(_trimmed)?(_val_1)?(_00*)?(\.fq)?(\.fastq)?(\.gz)?$/
	"""
	mkdir tmp
	fastqc -t ${task.cpus} -dir tmp $reads
	rm -rf tmp
	"""
}

/*
 * STEPS 1.2 Trimming
 */
if(!params.amplicons_file){
	process trimming {
		label "small"
		tag "$prefix"
		publishDir "${params.outdir}/02-preprocessing", mode: 'copy',
			saveAs: {filename ->
				if (filename.indexOf("_fastqc") > 0) "../03-preprocQC/$filename"
				else if (filename.indexOf(".log") > 0) "logs/$filename"
		else if (params.saveTrimmed && filename.indexOf(".fastq.gz")) "trimmed/$filename"
				else null
		}

		input:
		set val(name), file(reads) from raw_reads_trimming

		output:
		file '*_paired_*.fastq.gz' into trimmed1_paired_reads
		file '*_unpaired_*.fastq.gz' into trimmed1_unpaired_reads
		file '*_fastqc.{zip,html}' into trimmomatic1_fastqc_reports
		file '*.log' into trimmomatic1_results

		script:
		prefix = name - ~/(_S[0-9]{2})?(_L00[1-9])?(.R1)?(_1)?(_R1)?(_trimmed)?(_val_1)?(_00*)?(\.fq)?(\.fastq)?(\.gz)?$/
		"""
		trimmomatic PE -threads ${task.cpus} -phred33 $reads $prefix"_paired_R1.fastq" $prefix"_unpaired_R1.fastq" $prefix"_paired_R2.fastq" $prefix"_unpaired_R2.fastq" ILLUMINACLIP:${params.trimmomatic_adapters_file}:${params.trimmomatic_adapters_parameters} SLIDINGWINDOW:${params.trimmomatic_window_length}:${params.trimmomatic_window_value} MINLEN:${params.trimmomatic_mininum_length} 2> ${name}.log

		gzip *.fastq
		mkdir tmp
		fastqc -t ${task.cpus} -dir tmp -q *_paired_*.fastq.gz
		rm -rf tmp
		"""
	}
}

if(params.amplicons_file){
	process trimming_primers {
		label "small"
		tag "$prefix"
		publishDir "${params.outdir}/02-preprocessing", mode: 'copy',
			saveAs: {filename ->
				if (filename.indexOf("_fastqc") > 0) "../03-preprocQC/$filename"
				else if (filename.indexOf(".log") > 0) "logs/$filename"
		else if (params.saveTrimmed && filename.indexOf(".fastq.gz")) "trimmed/$filename"
				else null
		}

		input:
		set val(name), file(reads) from raw_reads_trimming_primers

		output:
		file '*_paired_*.fastq.gz' into trimmed_paired_reads,trimmed_paired_reads_bwa,trimmed_paired_reads_bwa_virus
		file '*_unpaired_*.fastq.gz' into trimmed_unpaired_reads
		file '*_fastqc.{zip,html}' into trimmomatic_fastqc_reports
		file '*.log' into trimmomatic_results

		script:
		prefix = name - ~/(_S[0-9]{2})?(_L00[1-9])?(.R1)?(_1)?(_R1)?(_trimmed)?(_val_1)?(_00*)?(\.fq)?(\.fastq)?(\.gz)?$/
		"""
		trimmomatic PE -threads ${task.cpus} -phred33 $reads $prefix"_paired_R1.fastq" $prefix"_unpaired_R1.fastq" $prefix"_paired_R2.fastq" $prefix"_unpaired_R2.fastq" ILLUMINACLIP:${params.amplicons_file}:${params.trimmomatic_adapters_parameters} SLIDINGWINDOW:${params.trimmomatic_window_length}:${params.trimmomatic_window_value} MINLEN:${params.trimmomatic_mininum_length} 2> ${name}.log

		gzip *.fastq
		mkdir tmp
		fastqc -t ${task.cpus} -dir tmp -q *_paired_*.fastq.gz
		rm -rf tmp
		"""
	}
}else{
	trimmed1_paired_reads
      .into {trimmed_paired_reads;trimmed_paired_reads_bwa;trimmed_paired_reads_bwa_virus}
    trimmed1_unpaired_reads
      .set {trimmed_unpaired_reads}
    trimmomatic1_fastqc_reports
      .set{trimmomatic_fastqc_reports}
    trimmomatic1_results
      .set{trimmomatic_results}
}
/*
 * STEPS 2.1 Mapping host
 */
process mapping_host {
	tag "$prefix"
	publishDir "${params.outdir}/04-mapping_host", mode: 'copy',
		saveAs: {filename ->
			if (filename.indexOf(".bam") > 0) "mapping/$filename"
			else if (filename.indexOf(".bai") > 0) "mapping/$filename"
      else if (filename.indexOf(".txt") > 0) "stats/$filename"
      else if (filename.indexOf(".stats") > 0) "stats/$filename"
	}

	input:
	set file(readsR1),file(readsR2) from trimmed_paired_reads_bwa
  file refhost from host_fasta_file
  file index from host_index_files.collect()

	output:
	file '*_sorted.bam' into mapping_host_sorted_bam,mapping_host_sorted_bam_assembly
  file '*.bam.bai' into mapping_host_bai,mapping_host_bai_assembly
	file '*_flagstat.txt' into mapping_host_flagstat

	script:
	prefix = readsR1.toString() - '_paired_R1.fastq.gz'
	"""
	bowtie2 -p ${task.cpus} --local --very-sensitive-local -x $refhost -1 $readsR1 -2 $readsR2 -S $prefix".sam"
    samtools view -b $prefix".sam" > $prefix".bam"
    samtools sort -o $prefix"_sorted.bam" -O bam -T $prefix $prefix".bam"
    samtools index $prefix"_sorted.bam"
    samtools flagstat $prefix"_sorted.bam" > $prefix"_flagstat.txt"
	"""
}


/*
 * STEPS 4.1 Select unmapped host reads
 */
process unmapped_host {
  label "small"
  tag "$prefix"
  publishDir "${params.outdir}/09-assembly", mode: 'copy',
    saveAs: {filename ->
      if (params.save_unmapped_host) "unmapped/$filename"
      else null
  }

  input:
  file sorted_bam from mapping_host_sorted_bam_assembly
  file bam_bai from mapping_host_bai_assembly

  output:
  file '*_unmapped.bam' into unmapped_host_bam
  file '*_unmapped_qsorted.bam' into unmapped_host_qsorted_bam
  file '*_unmapped.fastq' into unmapped_host_reads,unmapped_host_reads_spades,unmapped_host_reads_metaspades,unmapped_host_reads_unicycler

  script:
  prefix = sorted_bam.baseName - ~/(_sorted)?(_paired)?(\.bam)?(\.gz)?$/
  """
  samtools view -b -f 4 $sorted_bam > $prefix"_unmapped.bam"
  samtools sort -n $prefix"_unmapped.bam" -o $prefix"_unmapped_qsorted.bam"
  bedtools bamtofastq -i $prefix"_unmapped_qsorted.bam" -fq $prefix"_R1_unmapped.fastq" -fq2 $prefix"_R2_unmapped.fastq"
  """
}

/*
 * STEPS 4.2 De Novo Spades Assembly
 */
process spades_assembly {
  tag "$prefix"
  publishDir path: { "${params.outdir}/09-assembly/spades" }, mode: 'copy'

  input:
  set file(readsR1),file(readsR2) from unmapped_host_reads_spades

  output:
  file '*_scaffolds.fasta' into spades_scaffold,spades_scaffold_quast,spades_scaffold_abacas,spades_scaffold_blast,spades_scaffold_plasmid

  script:
  prefix = readsR1.toString() - '_R1_unmapped.fastq'
  """
  spades.py -t ${task.cpus} -1 $readsR1 -2 $readsR2 -o ./
  mv scaffolds.fasta $prefix"_scaffolds.fasta"
  """
}

/*
 * STEPS 4.2 De Novo MetaSpades Assembly
 */
process metaspades_assembly {
  tag "$prefix"
  publishDir path: { "${params.outdir}/09-assembly/metaspades" }, mode: 'copy'

  input:
  set file(readsR1),file(readsR2) from unmapped_host_reads_metaspades

  output:
  file '*_meta_scaffolds.fasta' into metaspades_scaffold,metas_pades_scaffold_quast,metas_pades_scaffold_plasmid

  script:
  prefix = readsR1.toString() - '_R1_unmapped.fastq'
  """
  spades.py -t ${task.cpus} -1 $readsR1 -2 $readsR2 --meta -o ./
  mv scaffolds.fasta $prefix"_meta_scaffolds.fasta"
  """
}


/*
 * STEPS 4.3 De Novo Unicycler Assembly
 */
process unicycler_assembly {
  tag "$prefix"
  publishDir path: { "${params.outdir}/09-assembly/unicycler" }, mode: 'copy'

  input:
  set file(readsR1),file(readsR2) from unmapped_host_reads_unicycler

  output:
  file '*_assembly.fasta' into unicycler_assembly,unicycler_assembly_quast,unicycler_assembly_plasmid

  script:
  prefix = readsR1.toString() - '_R1_unmapped.fastq'
  """
  unicycler -t ${task.cpus} -o ./ -1 $readsR1 -2 $readsR2
  mv assembly.fasta $prefix"_assembly.fasta"
  """
}

/*
 * STEPS 4.4 Spades Assembly Quast
 */
process spades_quast {
  label "small"
  tag "$prefix"
  publishDir path: { "${params.outdir}/09-assembly/" }, mode: 'copy'

  input:
  file scaffolds from spades_scaffold_quast.collect()
  file meta_scaffolds from metas_pades_scaffold_quast.collect()
  file refvirus from viral_fasta_file
  file viral_gff from gff_file

  output:
  file "spades_quast" into spades_quast_resuts
	file "spades_quast/report.tsv" into spades_quast_resuts_multiqc

  script:
  prefix = 'spades_quast'
  """
  quast.py --output-dir $prefix -R $refvirus -G $viral_gff -t ${task.cpus} \$(find . -name "*_scaffolds.fasta" | tr '\n' ' ')
  """
}

/*
 * STEPS 4.5 Unicycler Assembly Quast
 */
process unicycler_quast {
  label "small"
  tag "$prefix"
  publishDir path: { "${params.outdir}/09-assembly/" }, mode: 'copy'

  input:
  file assemblies from unicycler_assembly_quast.collect()
  file refvirus from viral_fasta_file
  file viral_gff from gff_file

  output:
  file "unicycler_quast" into unicycler_quast_resuts
	file "unicycler_quast/report.tsv" into unicycler_quast_resuts_multiqc

  script:
  prefix = 'unicycler_quast'
  """
  quast.py --output-dir $prefix -R $refvirus -G $viral_gff -t ${task.cpus} \$(find . -name "*_assembly.fasta" | tr '\n' ' ')
  """
}

/*
 * STEPS 4.6 ABACAS
 */
process abacas {
  label "small"
  tag "$prefix"
  publishDir "${params.outdir}/10-abacas", mode: 'copy',
		saveAs: {filename ->
			if (filename.indexOf("_abacas.bin") > 0) "abacas/$filename"
			else if (filename.indexOf("_abacas.crunch") > 0) "abacas/$filename"
      else if (filename.indexOf("_abacas.fasta") > 0) "abacas/$filename"
      else if (filename.indexOf("_abacas.gaps") > 0) "abacas/$filename"
      else if (filename.indexOf(".tab") > 0) "abacas/$filename"
      else if (filename.indexOf("_abacas.MULTIFASTA.fa") > 0) "abacas/$filename"
      else if (filename.indexOf("_abacas.gaps.tab") > 0) "abacas/$filename"
      else if (filename.indexOf(".delta") > 0) "nucmer/$filename"
      else if (filename.indexOf(".tiling") > 0) "nucmer/$filename"
      else if (filename.indexOf(".out") > 0) "nucmer/$filename"
			else filename
	}
  input:
  file scaffolds from spades_scaffold_abacas
  file refvirus from viral_fasta_file

  output:
  file "*_abacas.fasta" into abacas_fasta
  file "*_abacas*" into abacas_results

  script:
  prefix = scaffolds.baseName - ~/(_scaffolds)?(_paired)?(\.fasta)?(\.gz)?$/
  """
  abacas.pl -r $refvirus -q $scaffolds -m -p nucmer -o $prefix"_abacas"
  mv nucmer.delta $prefix"_abacas_nucmer.delta"
  mv nucmer.filtered.delta $prefix"_abacas_nucmer.filtered.delta"
  mv nucmer.tiling $prefix"_abacas_nucmer.tiling"
  mv unused_contigs.out $prefix"_abacas_unused_contigs.out"
  """
}

/*
 * STEPS 5.1 BLAST
 */
process blast {
  label "small"
  tag "$prefix"
  publishDir path: { "${params.outdir}/11-blast" }, mode: 'copy'

  input:
  file scaffolds from spades_scaffold_blast
  file blast_db from blast_db_files.collect()
  file header from blast_header

  output:
  file "*_blast_filt_header.txt" into blast_results

  script:
  prefix = scaffolds.baseName - ~/(_scaffolds)?(_paired)?(\.fasta)?(\.gz)?$/
  database = blast_db[1].toString() - ~/(\.ann)?$/
  """
  blastn -num_threads ${task.cpus} -db $database -query $scaffolds -outfmt \'6 stitle std slen qlen qcovs\' -out $prefix"_blast.txt"
  awk 'BEGIN{OFS=\"\\t\";FS=\"\\t\"}{print \$0,\$5/\$15,\$5/\$14}' $prefix"_blast.txt" | awk 'BEGIN{OFS=\"\\t\";FS=\"\\t\"} \$15 > 200 && \$17 > 0.7 && \$1 !~ /phage/ {print \$0}' > $prefix"_blast_filt.txt"; cat $header $prefix"_blast_filt.txt" > $prefix"_blast_filt_header.txt"
  """
}

/*
 * STEPS 6.1 plasmidID SPADES
 */
process plasmidID_spades {
  label "small"
  tag "$prefix"
  publishDir path: { "${params.outdir}/12-plasmidID/SPADES" }, mode: 'copy'

  input:
  file spades_scaffolds from spades_scaffold_plasmid.filter{ it.size()>0 }
  file refvirus from viral_fasta_file

  output:
  file "$prefix" into plasmid_SPADES

  script:
  prefix = spades_scaffolds.baseName - ~/(_scaffolds)?(_paired)?(\.fasta)?(\.gz)?$/
  """
  bash plasmidID.sh -d $refvirus -s $prefix -c $spades_scaffolds --only-reconstruct -C 47 -S 47 -i 60 --no-trim -o .
  mv NO_GROUP/$prefix ./$prefix
  """
}

/*
 * STEPS 6.1 plasmidID METASPADES
 */
process plasmidID_metaspades {
  label "small"
  tag "$prefix"
  publishDir path: { "${params.outdir}/12-plasmidID/META_SPADES" }, mode: 'copy'

  input:
  file meta_scaffolds from metas_pades_scaffold_plasmid.filter{ it.size()>0 }
  file refvirus from viral_fasta_file

  output:
  file "$prefix" into plasmid_METASPADES

  script:
  prefix = meta_scaffolds.baseName - ~/(_meta_scaffolds)?(\.fasta)?(\.gz)?$/
  """
  bash plasmidID.sh -d $refvirus -s $prefix -c $meta_scaffolds --only-reconstruct -C 47 -S 47 -i 60 --no-trim -o .
  mv NO_GROUP/$prefix ./$prefix
  """
}

/*
 * STEPS 6.1 plasmidID UNICYCLER
 */
process plasmidID_unicycler {
  label "small"
  tag "$prefix"
  publishDir path: { "${params.outdir}/12-plasmidID/UNICYCLER" }, mode: 'copy'

  input:
  file unicycler_assembly from unicycler_assembly_plasmid.filter{ it.size()>0 }
  file refvirus from viral_fasta_file

  output:
  file "$prefix" into plasmid_UNICYCLER

  script:
  prefix = unicycler_assembly.baseName - ~/(_assembly)?(_paired)?(\.fasta)?(\.gz)?$/
  """
  bash plasmidID.sh -d $refvirus -s $prefix -c $unicycler_assembly --only-reconstruct -C 47 -S 47 -i 60 --no-trim -o .
  mv NO_GROUP/$prefix ./$prefix
  """
}

/*
 * STEP 4.1 MultiQC
 */
process multiqc {
	tag "$prefix"
    publishDir path: { "${params.outdir}/99-stats/MultiQC" }, mode: 'copy'

    input:
    file multiqc_config from multiqc_config
    file (fastqc:'fastqc/*') from fastqc_results.collect().ifEmpty([])
    file ('trimommatic/*') from trimmomatic_results.collect()
    file ('trimommatic/*') from trimmomatic_fastqc_reports.collect()
    file ('mappinh_host/*') from mapping_host_flagstat.collect()
    file ('mappinh_host/*') from mapping_host_picardstats.collect()
    file ('quast_unicycler/*') from unicycler_quast_resuts_multiqc.collect()
    file ('quast_spades/*') from spades_quast_resuts_multiqc.collect()

    output:
    file '*multiqc_report.html' into multiqc_report
    file '*_data' into multiqc_data
    val prefix into multiqc_prefix

    script:
    prefix = fastqc[0].toString() - '_fastqc.html' - 'fastqc/'

    """
    multiqc -d . --config $multiqc_config
    """
}

/*
 * STEP 5 - Output Description HTML
 */
process output_documentation {
    publishDir "$doc_output", mode: 'copy'

    input:
    file output_docs from ch_output_docs

    output:
    file "results_description.html"
    file "*.pdf"

    script:
    if (params.service_id) {
      """
      markdown_to_html.r $output_docs results_description.html
      wkhtmltopdf --keep-relative-links results_description.html INFRES_${params.service_id}.pdf
      """
    } else{
      """
      markdown_to_html.r $output_docs results_description.html
      wkhtmltopdf --keep-relative-links results_description.html INFRES.pdf
      """
    }
}
