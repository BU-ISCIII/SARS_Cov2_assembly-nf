# BU-ISCIII/SARS_Cov2-nf: Installation

To start using the BU-ISCIII/SARS_Cov2-nf pipeline, follow the steps below:

<!-- Install Atom plugin markdown-toc-auto for this ToC -->
<!-- TOC START min:2 max:3 link:true asterisk:true -->
* [Install NextFlow](#install-nextflow)
* [Install the pipeline](#install-the-pipeline)
* [Pipeline configuration](#pipeline-configuration)
  * [Conda](#conda)
<!-- TOC END -->

## Install NextFlow
Nextflow runs on most POSIX systems (Linux, Mac OSX etc). It can be installed by running the following commands:

```bash
# Make sure that Java v8+ is installed:
java -version

# Install Nextflow
curl -fsSL get.nextflow.io | bash

# Add Nextflow binary to your PATH:
mv nextflow ~/bin/
# OR system-wide installation:
# sudo mv nextflow /usr/local/bin
```

See [nextflow.io](https://www.nextflow.io/) for further instructions on how to install and configure Nextflow.

## Install the pipeline

You'll need to download the repository from our GitHub:

```bash
wget https://github.com/BU-ISCIII/SARS_Cov2-nf/archive/master.zip
unzip master.zip -d ~/my-pipelines/
```

## Pipeline configuration
By default, the pipeline loads a basic server configuration [`conf/base.config`](../conf/base.config)
This uses a number of sensible defaults for process requirements and is suitable for running
on a simple (if powerful!) local server.

Be warned of two important points about this default configuration:

1. The default profile uses the `local` executor
    * See the [nextflow docs](https://www.nextflow.io/docs/latest/executor.html) for information about running with other hardware backends. Most job scheduler systems are natively supported.
2. Nextflow will expect all software to be installed and available on the `PATH`
    * You can create a conda environment with all the programs needed for this pipeline with our [environment.yml file](../environment.yml). See below.
3. For [plasmidID](https://github.com/BU-ISCIII/plasmidID) you will have to download it from its main page and change in the [base config file](../conf/base.config) the variable that exports the path to plasmidID and plasmidID/bin folders:
    * PATH="$PATH:/path/to/your/plasmidID/:/path/to/your/plasmidID/bin/"

### Conda
You can use conda to manage the software requirements.
To use it first ensure that you have conda installed (we recommend [miniconda](https://conda.io/miniconda.html)).
To create the environment you just have to run:
```
conda env create -f environment.yml
```
And the environment will be created in your machine with all the programs.

