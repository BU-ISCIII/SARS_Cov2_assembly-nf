<img src="docs/images/BU_ISCIII_logo.png" alt="logo" width="300" align="right"/>

# SARS_Cov2_assembly-nf
[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A50.32.0-brightgreen.svg)](https://www.nextflow.io/)
[![install with bioconda](https://img.shields.io/badge/install%20with-bioconda-brightgreen.svg)](http://bioconda.github.io/)

<!--
[![Docker](https://img.shields.io/docker/automated/nfcore/rnaseq.svg)](https://hub.docker.com/r/nfcore/rnaseq/)
-->
### Introduction

**BU-ISCIII/SARS_Cov2_assembly-nf** is a bioinformatics analysis pipeline used to analyze SARS-Cov2 Illumina data. The approach followed by this pipeline is to create a consensus genome through mapping, variant calling and consensus genome generation.

The workflow processes raw data from FastQ inputs ([FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/), [Trimmomatic](http://www.usadellab.org/cms/?page=trimmomatic)), maps the reads ([Bowtie2](http://bowtie-bio.sourceforge.net/bowtie2/index.shtml) and [Samtools](http://www.htslib.org/doc/samtools.html)) against the host. Optionally, if the data has been obtained through amplicon sequencing you can use trimmomatic to trim the primers prior to mapping against host. Then the pipeline performs de novo assembly with three assemblers, [spades](http://cab.spbu.ru/software/spades/), metaspades and [unicycler](https://github.com/rrwick/Unicycler). Following assembly [blast](https://blast.ncbi.nlm.nih.gov/Blast.cgi) step against the virus reference genome is performed and some visualization is done using circos. Finally we generate a stats report with [MultiQC](https://multiqc.info/) See the [output documentation](docs/output.md) for more details of the results.

The pipeline is built using [Nextflow](https://www.nextflow.io), a bioinformatics workflow tool to run tasks across multiple compute infrastructures in a very portable manner. It comes with docker / singularity containers making installation trivial and results highly reproducible.

### Documentation
The BU-ISCIII/SARS_Cov2 pipeline comes with documentation about the pipeline, found in the `docs/` directory:

1. [Installation](docs/installation.md)
2. [Running the pipeline](docs/usage.md)
3. [Output and how to interpret the results](docs/output.md)

## Credit
Thanks to [nf-core](https://nf-co.re/) templates for the docs and resources that inspired this pipelines.
