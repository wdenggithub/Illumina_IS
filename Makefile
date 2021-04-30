SHELL := /bin/bash
export SHELLOPTS:=errexit:pipefail
.DELETE_ON_ERROR:

# pipeline identifying IS from 5'/3' ends

LTR ?= 3
MINMAPLEN ?= 30
BIN := script
INPUT := data
OUTPUT := output_$(LTR)LTR
GFF := human_gff/GRCh38.p2_gene.gff
HGENOME := ~/human_genome_GRCh38.p2/GCF_000001405.28_GRCh38.p2_genomic.fna
LTRFILE := seqs/ltr.fas
ADPTFILE := seqs/adapter.fas
LINKERFILE := seqs/linker.fas

TEXT := $(shell script/parse_seqs.pl $(LTRFILE) $(ADPTFILE) $(LINKERFILE))
LTRSEQ := $(word 1, $(TEXT))
ADPTSEQ := $(word 2, $(TEXT))
LINKERSEQ := $(word 3, $(TEXT))
LTROVLP := $(word 4, $(TEXT))
ADPTOVLP := $(word 5, $(TEXT))
LINKEROVLP := $(word 6, $(TEXT))

all : $(OUTPUT)/$(sample)/$(sample)_consensus_IS_breakpoint.csv
# sickle quality trimming
$(OUTPUT)/$(sample)/$(sample)_R1_sickle.fastq $(OUTPUT)/$(sample)/$(sample)_R2_sickle.fastq : $(INPUT)/$(sample)_R1.fastq.gz $(INPUT)/$(sample)_R2.fastq.gz | mkdir-output-$(sample)
	sickle pe -q 20 -w 10 -l 75 -n -t sanger \
	-f <(gunzip -c $(INPUT)/$(sample)_R1.fastq.gz) \
	-r <(gunzip -c $(INPUT)/$(sample)_R2.fastq.gz) \
	-o $(OUTPUT)/$(sample)/$(sample)_R1_sickle.fastq \
	-p $(OUTPUT)/$(sample)/$(sample)_R2_sickle.fastq \
	-s $(OUTPUT)/$(sample)/$(sample)_sickle_single.fastq \
	> $(OUTPUT)/$(sample)/$(sample)_log.txt
# trim LTR in filtered R1 reads
$(OUTPUT)/$(sample)/$(sample)_R1_sickle_$(LTR)LTR.fastq : $(OUTPUT)/$(sample)/$(sample)_R1_sickle.fastq
	cutadapt --trimmed-only -g $(LTRSEQ) -O $(LTROVLP) -o $@ $^ >> $(OUTPUT)/$(sample)/$(sample)_log.txt
# retrieve paired R2 reads
$(OUTPUT)/$(sample)/$(sample)_R2_sickle_$(LTR)LTR.fastq : $(OUTPUT)/$(sample)/$(sample)_R1_sickle_$(LTR)LTR.fastq
	$(BIN)/retrievePairReadsFromFastq.pl $^ $(OUTPUT)/$(sample)/$(sample)_R2_sickle.fastq $@  >> $(OUTPUT)/$(sample)/$(sample)_log.txt
# trim illumina reverse adapter in paired R2 reads
$(OUTPUT)/$(sample)/$(sample)_R2_sickle_$(LTR)LTR_RA.fastq : $(OUTPUT)/$(sample)/$(sample)_R2_sickle_$(LTR)LTR.fastq
	cutadapt --trimmed-only -g $(ADPTSEQ) -O $(ADPTOVLP) -o $@ $^ >> $(OUTPUT)/$(sample)/$(sample)_log.txt
# trim linker in paired R2 reads
$(OUTPUT)/$(sample)/$(sample)_R2_sickle_$(LTR)LTR_RA_LK.fastq : $(OUTPUT)/$(sample)/$(sample)_R2_sickle_$(LTR)LTR_RA.fastq
	cutadapt --trimmed-only -g $(LINKERSEQ) -O $(LINKEROVLP) -o $@ $^ >> $(OUTPUT)/$(sample)/$(sample)_log.txt
# retrieve paired R1 reads
$(OUTPUT)/$(sample)/$(sample)_R1_sickle_$(LTR)LTR_RA_LK.fastq : $(OUTPUT)/$(sample)/$(sample)_R2_sickle_$(LTR)LTR_RA_LK.fastq
	$(BIN)/retrievePairReadsFromFastq.pl $^ $(OUTPUT)/$(sample)/$(sample)_R1_sickle_$(LTR)LTR.fastq $@  >> $(OUTPUT)/$(sample)/$(sample)_log.txt
# map to human genome
$(OUTPUT)/$(sample)/$(sample)_bwa_human.sam : $(OUTPUT)/$(sample)/$(sample)_R1_sickle_$(LTR)LTR_RA_LK.fastq
	bwa mem -t 10 $(HGENOME) $^ $(OUTPUT)/$(sample)/$(sample)_R2_sickle_$(LTR)LTR_RA_LK.fastq > $@
# parse sam file
$(OUTPUT)/$(sample)/$(sample)_bwa_human_parsed.csv : $(OUTPUT)/$(sample)/$(sample)_bwa_human.sam
	$(BIN)/parseSamISBreakpoint.pl $^ $@ $(LTR) $(MINMAPLEN)
# get consensus IS and breakpoint mapping to human at least 99%
$(OUTPUT)/$(sample)/$(sample)_consensus_IS_breakpoint.csv : $(OUTPUT)/$(sample)/$(sample)_bwa_human_parsed.csv	
	$(BIN)/getConsensusISBPWithIdentity.pl $^ $(GFF) $@ 0.99
# retrieve R1 and R2 reads with IS and breakpoint
#$(OUTPUT)/$(sample)/$(sample)_ISBP_R1.fastq : $(OUTPUT)/$(sample)/$(sample)_template_consensus_IS_breakpoint.csv	
#	$(BIN)/retrieveISBPR1R2Reads.pl $(OUTPUT)/$(sample)/$(sample)_R1_sickle.fastq $(OUTPUT)/$(sample)/$(sample)_R2_sickle.fastq $(OUTPUT)/$(sample)/$(sample)_bwa_human_parsed.csv $@ $(OUTPUT)/$(sample)/$(sample)_ISBP_R2.fastq


mkdir-output-%:
	mkdir -p $(OUTPUT)/$*

clean : 
	rm -rfv $(OUTPUT)/


