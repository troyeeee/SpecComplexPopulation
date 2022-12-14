#!/bin/bash

###
### SpecHLA: Full-resolution HLA typing from paired-end, PacBio, Nanopore,
### Hi-C, and 10X sequencing. Supports WGS, WES, and RNASeq data.
### 
###
### Usage:
###   sh SpecHLA.sh -n <sample> -1 <sample.fq.1.gz> -2 <sample.fq.2.gz> -t <sample.pacbio.fq.gz> -p <Asian>
###
### Options:
###   -n        Sample ID. <required>
###   -1        The first fastq file. <required>
###   -2        The second fastq file. <required>
###   -o        The output folder to store the typing results.
###   -u        Choose full-length or exon typing. 0 indicates full-length, 1 means exon, 
###             default is to perform full-length typing.
###   -p        The population of the sample [Asian, Black, Caucasian, Unknown, nonuse]. 
###             Default is Unknown, meaning use mean frequency. nonuse indicates only adopting 
###             mapping score and considering alleles with frequency as zero. 
###   -t        Pacbio fastq file.
###   -e        Nanopore fastq file.
###   -c        fwd hi-c fastq file.
###   -d        rev hi-c fastq file.
###   -x        Path of folder created by 10x demultiplexing. Prefix of the filenames of FASTQs
###             should be the same as Sample ID. Please install Longranger in the system env.
###   -w        The weight to use linkage info from genotype frequency [0-1], default is 0 that means 
###             not use, 1 means only use imbalance info, other values integrate use both.
###   -j        Number of threads [5]
###   -m        The maximum mismatch number tolerated in assigning gene-specific reads. Deault
###             is 2. It should be set larger to infer novel alleles.
###   -y        The minimum different mapping score between the best- and second-best aligned gene. 
###             Discard the read if the score is lower than this value. Deault is 0.1. 
###   -v        True or False. Consider long InDels if True, else only consider short variants. 
###             Default is False. 
###   -q        Minimum variant quality. Default is 0.01. Set it larger in high quality samples.
###   -s        Minimum variant depth. Default is 5.
###   -a        Use this long InDel file if provided.
###   -r        The minimum Minor Allele Frequency (MAF), default is 0.05 for full length and
###             0.1 for exon typing.
###   -g        Whether use G-translate in annotation [1|0], default is 0.
###   -k        The mean depth in a window lower than this value will be masked by N, default is 5.
###             Set 0 to avoid masking.
###   -z        Whether only mask exon region, True or False, default is False.
###   -f        The trio infromation; child:parent_1:parent_2 [Example: NA12878:NA12891:NA12892]. 
###             Note: this parameter should be used after performing SpecHLA already.
###   -b        Whether use database for unlinked block phasing [1|0], default is 1.
###   -h        Show this message.

help() {
    sed -rn 's/^### ?//;T;p' "$0"
}

if [[ $# == 0 ]] || [[ "$1" == "-h" ]]; then
    help
    exit 1
fi

while getopts ":n:1:2:p:f:m:v:q:t:a:e:x:c:d:r:y:o:j:w:u:s:g:k:z:y:f:b:" opt; do
  case $opt in
    n) sample="$OPTARG"
    ;;
    1) fq1="$OPTARG"
    ;;
    2) fq2="$OPTARG"
    ;;
    p) pop="$OPTARG"
    ;;
    m) nm="$OPTARG"
    ;;
    v) long_indel="$OPTARG"
    ;;
    q) snp_quality="$OPTARG"
    ;;
    t) tgs="$OPTARG"
    ;;
    a) sv="$OPTARG"
    ;;
    e) nanopore_data="$OPTARG"
    ;;
    x) tenx_data="$OPTARG"
    ;;
    c) hic_data_fwd="$OPTARG"
    ;;
    d) hic_data_rev="$OPTARG"
    ;;
    r) maf="$OPTARG"
    ;;
    o) given_outdir="$OPTARG"
    ;;
    j) num_threads="$OPTARG"
    ;;
    w) weight_imb="$OPTARG"
    ;;
    u) focus_exon="$OPTARG"
    ;;
    s) snp_dp="$OPTARG"
    ;;
    g) trans="$OPTARG"
    ;;
    k) mask_depth="$OPTARG"
    ;;
    z) mask_exon="$OPTARG"
    ;;
    y) mini_score="$OPTARG"
    ;;
    f) trio="$OPTARG"
    ;;
    b) use_database="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done


dir=$(cd `dirname $0`; pwd)
export LD_LIBRARY_PATH=$dir/../../spechla_env/lib
python_bin=$dir/../../spechla_env/bin/python3
bin=$dir/../../bin
db=$dir/../../db_complex
# hlaref=$db/ref/hla.ref.extend.fa
complexref=$db/ref/merged.fa


if [ ${given_outdir:-NA} == NA ]
  then
    outdir=$(pwd)/output/$sample
  else
    outdir=$given_outdir/$sample   
fi
focus_exon_flag=${focus_exon:-0} # default is perform full-length typing

echo Start profiling COMPLEX for $sample. 
mkdir -p $outdir
# exec >$outdir/$sample.log 2>&1 #redirect log info to the outdir
group='@RG\tID:'$sample'\tSM:'$sample
echo use ${num_threads:-5} threads.


# ##############check if the input fastq is empty################
if [[ ! -s $fq1 ]]; then
echo "Input fastq file is empty! Please check the reads extraction!"
echo "Note: use ExtractHLAread.sh to extract HLA-related reads with the raw reads mapped to hg38 or hg19."
exit 1
fi
# ###############################################################

# ##############check if read1 and read2 files are same ################
if [[ $fq1 == $fq2 ]]; then
echo "Error: Input read1 and read2 fastq files are the same! Please check the input files!"
exit 1
fi
# ###############################################################

# # :<<!
# # ################ remove the repeat read name #################
# $python_bin $dir/../uniq_read_name.py $fq1 $outdir/$sample.uniq.name.R1.gz
# $python_bin $dir/../uniq_read_name.py $fq2 $outdir/$sample.uniq.name.R2.gz
# fq1=$outdir/$sample.uniq.name.R1.gz
# fq2=$outdir/$sample.uniq.name.R2.gz
# # ###############################################################



# # ################### assign the reads to original gene######################################################
# echo map the reads to database to assign reads to corresponding genes.
# license=$dir/../../bin/novoalign.lic
# # if [ $focus_exon_flag == 1 ];then
# #   database_prefix=hla_gen.format.filter.extend.DRB.no26789
# # else
# #   database_prefix=hla_gen.format.filter.extend.DRB.no26789.v2
# database_prefix=merged

# # fi
# if [ -f "$license" ];then
#     echo "Detect novoalign license, use novoalign."
#     if [ ! -f "$db/ref/$database_prefix.ndx" ];then
#         echo "Can't find ref index for novoalign, please run *bash index.sh* again."
#         exit 1
#     fi
#     $bin/novoalign -d $db/ref/$database_prefix.ndx -f $fq1 $fq2 -F STDFQ -o SAM \
#     -o FullNW -r All 100000 --mCPU ${num_threads:-5} -c 10  -g 20 -x 3  | $bin/samtools view \
#     -Sb - | $bin/samtools sort -  > $outdir/$sample.map_database.bam
# else
#     echo "Can't detect novoalign license, use bowtie2." 
#     bowtie2 --very-sensitive -p ${num_threads:-5} -k 30 -x $db/ref/$database_prefix.fa -1 $fq1 -2 $fq2|\
#     $bin/samtools view -bS -| $bin/samtools sort - >$outdir/$sample.map_database.bam
# fi
# $bin/samtools index $outdir/$sample.map_database.bam
# # TODO:: change gene name in assign_reads_to_genes.py
# $python_bin $dir/../assign_reads_to_genes.py -1 $fq1 -2 $fq2 -n $bin -o $outdir -d ${mini_score:-0.1} \
# -b ${outdir}/${sample}.map_database.bam -nm ${nm:-50} -r "$db/freebayes_alts_10_ex_1500.region.csv"
# # #############################################################################################################



# # ########### align the gene-specific reads to the corresponding gene reference################################
# # $bin/bwa mem -U 10000 -L 10000,10000 -R $group $hlaref $fq1 $fq2 | $bin/samtools view -H  >$outdir/header.sam
# $bin/bwa mem -U 10000 -L 10000,10000 -R $group $complexref $fq1 $fq2 | $bin/samtools view -H  >$outdir/header.sam

# #hlas=(A B C)
# # TODO:: change gene names
# # hlas=(A B C DPA1 DPB1 DQA1 DQB1 DRB1)
# complexes=( $(awk '{print $4}' $db/freebayes_alts_10_ex_1500.region.csv) ) 
# # for hla in ${hlas[@]}; do
# bam_list_file=$outdir/bam_list.txt
# for complex in ${complexes[@]}; do

#         # hla_ref=$db/HLA/HLA_$hla/HLA_$hla.fa
#         complex_ref=$db/complex/$complex/$complex.fa
#         # $bin/bwa mem -t ${num_threads:-5} -U 10000 -L 10000,10000 -R $group $hla_ref $outdir/$hla.R1.fq.gz $outdir/$hla.R2.fq.gz\
#         #  | $bin/samtools view -bS -F 0x800 -| $bin/samtools sort - >$outdir/$hla.bam
#         # $bin/samtools index $outdir/$hla.bam
#         $bin/bwa mem -t ${num_threads:-5} -U 10000 -L 10000,10000 -R $group $complex_ref $outdir/$complex.R1.fq.gz $outdir/$complex.R2.fq.gz\
#          | $bin/samtools view -bS -F 0x800 -| $bin/samtools sort - >$outdir/$complex.bam
#         $bin/samtools index $outdir/$complex.bam
#         echo $outdir/$complex.bam >> $bam_list_file
# done
# # TODO:: change merge file names
# # $bin/samtools merge -f -h $outdir/header.sam $outdir/$sample.merge.bam $outdir/A.bam $outdir/B.bam $outdir/C.bam\
# #  $outdir/DPA1.bam $outdir/DPB1.bam $outdir/DQA1.bam $outdir/DQB1.bam $outdir/DRB1.bam
# # $bin/samtools index $outdir/$sample.merge.bam
# $bin/samtools merge -f -h $outdir/header.sam $outdir/$sample.merge.bam -b $bam_list_file
# $bin/samtools index $outdir/$sample.merge.bam
# rm $bam_list_file

# # ###############################################################################################################


# # ################################### local assembly and realignment #################################
# echo start realignment...
# # if [ $focus_exon_flag == 1 ];then #exon
# #   assemble_region=$dir/select.region.exon.txt
# # else # full length
# # TODO::give a bed file
# # assemble_region=$dir/select.region.txt
# assemble_region="$db/selected_complex_region_ex_500.txt"

# # fi
# # TODO:: change hla_fa in assembly
# # sh $dir/../run.assembly.realign.sh $sample $outdir/$sample.merge.bam $outdir 70 $assemble_region ${num_threads:-5}
# # rlen set to 200 for different reads length
# sh $dir/../run.assembly.realign.sh $sample $outdir/$sample.merge.bam $outdir 200 $assemble_region ${num_threads:-5}

# # $bin/freebayes -a -f $hlaref -p 3 $outdir/$sample.realign.sort.bam > $outdir/$sample.realign.vcf && \
# $bin/freebayes -a -f $complexref -p 3 $outdir/$sample.realign.sort.bam > $outdir/$sample.realign.vcf && \

# rm -rf $outdir/$sample.realign.vcf.gz 
# bgzip -f $outdir/$sample.realign.vcf
# tabix -f $outdir/$sample.realign.vcf.gz
# zless $outdir/$sample.realign.vcf.gz > $outdir/$sample.realign.filter.vcf
# # changed; no need to filter
# echo BAM and VCF are ready.
# # if [ $focus_exon_flag == 1 ];then #exon
# #     $bin/bcftools filter -R $dir/exon_extent.bed $outdir/$sample.realign.vcf.gz |grep -v "#"  >> $outdir/$sample.realign.filter.vcf  
# # else # full length
# #     $bin/bcftools filter\
# #      -t HLA_A:1000-4503,HLA_B:1000-5081,HLA_C:1000-5304,HLA_DPA1:1000-10775,HLA_DPB1:1000-12468,HLA_DQA1:1000-7492,HLA_DQB1:1000-8480,HLA_DRB1:1000-12229\
# #       $outdir/$sample.realign.vcf.gz |grep -v "#" >> $outdir/$sample.realign.filter.vcf  
# # fi
# # #####################################################################################################


# # ################### assign long reads to gene ###################
# echo "assign long reads to gene"
# if [ ${tgs:-NA} != NA ];then
#     $python_bin $dir/../long_read_typing.py -r ${tgs} -n $sample -m 0 -o $outdir -j ${num_threads:-5} -a pacbio
# fi
# if [ ${nanopore_data:-NA} != NA ];then
#     $python_bin $dir/../long_read_typing.py -r ${nanopore_data} -n $sample -m 0 -o $outdir -j ${num_threads:-5} -a nanopore
# fi


bam=$outdir/$sample.realign.sort.bam
vcf=$outdir/$sample.realign.filter.vcf
# # ###################### mask low-depth region #############################################
# echo "mask low depth"
# $bin/samtools depth -aa $bam>$bam.depth  
# if [ $focus_exon_flag == 1 ];then my_mask_exon=True; else my_mask_exon=${mask_exon:-False}; fi
# $python_bin $dir/../mask_low_depth_region.py -c $bam.depth -o $outdir -w 20 -d ${mask_depth:-5} -f $my_mask_exon



# # ###################### call long indel #############################################
# echo "call long indel"
# # if [ ${long_indel:-False} == True ] && [ $focus_exon_flag != 1 ]; #don't call long indel for exon typing
# #     then
# #     port=$(date +%N|cut -c5-9)
# #     bfile=$outdir/$sample.long.InDel.breakpoint.txt

# #     if [ ${tgs:-NA} != NA ] # detect long Indel with pacbio
# #         then
# #         # $bin/pbmm2 align -j ${num_threads:-5} $hlaref ${tgs:-NA} $outdir/$sample.movie1.bam --sort --sample $sample --rg '@RG\tID:movie1'
# #         $bin/pbmm2 align -j ${num_threads:-5} $complexref ${tgs:-NA} $outdir/$sample.movie1.bam --sort --sample $sample --rg '@RG\tID:movie1'
        
# #         $bin/samtools view -H $outdir/$sample.movie1.bam >$outdir/header.sam

# #         # hlas=(A B C DPA1 DPB1 DQA1 DQB1 DRB1)
# #         # for hla in ${hlas[@]}; do
# #         #         # hla_ref=$db/HLA/HLA_$hla/HLA_$hla.fa
# #         #         complex_ref=$db/HLA/HLA_$hla/HLA_$hla.fa
# #         #         $bin/pbmm2 align -j ${num_threads:-5} $complex_ref $outdir/$sample/$hla.pacbio.fq.gz $outdir/$hla.gene.bam --sort --sample $sample --rg '@RG\tID:movie1'
# #         #         $bin/samtools index $outdir/$hla.gene.bam
# #         # done
# #         # hlas=(A B C DPA1 DPB1 DQA1 DQB1 DRB1)
# #         bam_list_file=$outdir/bam_list.txt
# #         for complex in ${complexes[@]}; do
# #                 # hla_ref=$db/HLA/HLA_$hla/HLA_$hla.fa
# #                 complex_ref=$db/complex/$complex/$complex.fa
# #                 $bin/pbmm2 align -j ${num_threads:-5} $complex_ref $outdir/$sample/$complex.pacbio.fq.gz $outdir/$complex.complex.bam --sort --sample $sample --rg '@RG\tID:movie1'
# #                 $bin/samtools index $outdir/$complex.complex.bam
# #                 echo $outdir/$complex.complex.bam > $bam_list_file
# #         done
# #         # TODO:: change merge way
# #         # $bin/samtools merge -f -h $outdir/header.sam $outdir/$sample.pacbio.bam $outdir/A.gene.bam $outdir/B.gene.bam $outdir/C.gene.bam\
# #         # $outdir/DPA1.gene.bam $outdir/DPB1.gene.bam $outdir/DQA1.gene.bam $outdir/DQB1.gene.bam $outdir/DRB1.gene.bam
# #         # $bin/samtools index $outdir/$sample.pacbio.bam
# #         $bin/samtools merge -f -h $outdir/header.sam $outdir/$sample.pacbio.bam -b $bam_list_file
# #         $bin/samtools index $outdir/$sample.pacbio.bam
# #         rm $bam_list_file


# #         $bin/pbsv discover -l 100 $outdir/$sample.pacbio.bam $outdir/$sample.svsig.gz
# #         # $bin/pbsv call -t DEL,INS -m 150 -j ${num_threads:-5} $hlaref $outdir/$sample.svsig.gz $outdir/$sample.var.vcf
# #         $bin/pbsv call -t DEL,INS -m 150 -j ${num_threads:-5} $complexref $outdir/$sample.svsig.gz $outdir/$sample.var.vcf

# #         $python_bin $dir/vcf2bp.py $outdir/$sample.var.vcf $outdir/$sample.tgs.breakpoint.txt
# #         cat $outdir/$sample.tgs.breakpoint.txt >$bfile
# #     else # detect long Indel with pair end data.
# #         echo "scan long indel using pe data"
# #         bash $dir/../ScanIndel/run_scanindel_sample.sh $sample $bam $outdir $port
# #         cat $outdir/Scanindel/$sample.breakpoint.txt >$bfile
# #     fi
# # else
# #     bfile=nothing
# # fi
# if [ ${sv:-NA} != NA ]
#     then
#     bfile=$sv
# fi
# #############################################################################################


# ########### phase, link blocks, calculate haplotype ratio, give typing results ##############
echo "start phasing"
if [ "$maf" == "" ];then
    if [ $focus_exon_flag != 1 ]; then
        my_maf=0.05
    else
        my_maf=0.1
    fi
else
    my_maf=$maf
fi

echo Minimum Minor Allele Frequency is $my_maf.
# hlas=(A B C DPA1 DPB1 DQA1 DQB1 DRB1)
# hlas=(A)
for complex in ${complexes[@]}; do
# hla_ref=$db/ref/HLA_$hla.fa
complex_ref=$db/ref/$complex.fa
#   --fq1 $outdir/$hla.R1.fq.gz \
#   --fq2 $outdir/$hla.R2.fq.gz \
#   --gene HLA_$hla \
#   --ref $hla_ref \

$python_bin $dir/../phase_complex_variants.py \
  -o $outdir \
  -b $bam \
  -s NA \
  -v $vcf \
  --fq1 $outdir/$complex.R1.fq.gz \
  --fq2 $outdir/$complex.R2.fq.gz \
  --gene $complex \
  --freq_bias $my_maf \
  --snp_qual ${snp_quality:-0.01} \
  --snp_dp ${snp_dp:-5} \
  --ref $complex_ref \
  --tgs ${tgs:-NA} \
  --nanopore ${nanopore_data:-NA} \
  --hic_fwd ${hic_data_fwd:-NA} \
  --hic_rev ${hic_data_rev:-NA} \
  --tenx ${tenx_data:-NA} \
  --sa $sample \
  --weight_imb ${weight_imb:-0} \
  --exon $focus_exon_flag \
  --thread_num ${num_threads:-5} \
  --use_database ${use_database:-1} \
  --trio ${trio:-None}
done
# ##################################################################################################


# ############################ annotation ####################################
# echo start annotation...
# # perl $dir/annoHLApop.pl $sample $outdir $outdir 2 $pop
# if [ $focus_exon_flag == 1 ];then #exon
#     perl $dir/annoHLA.pl -s $sample -i $outdir -p ${pop:-Unknown} -g ${trans:-0} -r exon 
# else
#     perl $dir/annoHLA.pl -s $sample -i $outdir -p ${pop:-Unknown} -g ${trans:-0} -r whole 
# fi
# #############################################################################



# bash $dir/../clear_output.sh $outdir/
cat $outdir/hla.result.txt
echo $sample is done.
