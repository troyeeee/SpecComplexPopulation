#!/bin/bash

# construct config file for ScanIndel
# HLAs=(A B C DPA1 DPB1 DQA1 DQB1 DRB1)
# HLAs=( $(awk '{print $4}' $dir/db_complex/freebayes_alts_10_1000_forbedtools.region.csv) ) 

dir=$(cd `dirname $0`; pwd)
HLAs=( $(awk '{print $4}' $dir/db_complex/freebayes_alts_10_ex_1500.region.csv) ) 


# :<<!
for hla in ${HLAs[@]}; do
    config_file=$dir/db_complex/complex/${hla}.config.txt
    echo bwa=$dir/db_complex/complex/${hla}/${hla}.fa >$config_file
    echo freebayes=$dir/db_complex/complex/${hla}/${hla}.fa >>$config_file
    echo blat=$dir/db_complex/complex/${hla}/ >>$config_file
    bwa index $dir/db_complex/complex/${hla}/${hla}.fa
    bwa index $dir/db_complex/ref/${hla}.fa
done
bwa index $dir/db_complex/ref/merged.fa
# index the database for bowtie2
# bowtie2-build $dir/db_complex/ref/hla_gen.format.filter.extend.DRB.no26789.fasta $dir/db_complex/ref/hla_gen.format.filter.extend.DRB.no26789.fasta
# bowtie2-build $dir/db_complex/ref/hla_gen.format.filter.extend.DRB.no26789.v2.fasta $dir/db_complex/ref/hla_gen.format.filter.extend.DRB.no26789.v2.fasta
bowtie2-build $dir/db_complex/ref/merged.fa $dir/db_complex/ref/merged.fa

# index the database for novoalign
license=$dir/bin/novoalign.lic
if [ -f "$license" ];then
    echo "has licience"
    # $dir/bin/novoindex  -k 14 -s 1 $dir/db_complex/ref/hla_gen.format.filter.extend.DRB.no26789.ndx \
    # $dir/db_complex/ref/hla_gen.format.filter.extend.DRB.no26789.fasta

    # $dir/bin/novoindex  -k 14 -s 1 $dir/db_complex/ref/hla_gen.format.filter.extend.DRB.no26789.v2.ndx \
    # $dir/db_complex/ref/hla_gen.format.filter.extend.DRB.no26789.v2.fasta
    $dir/bin/novoindex  -k 14 -s 1 $dir/db_complex/ref/merged.ndx \
    $dir/db_complex/ref/merged.fa
fi

# the lib required by samtools
ln -s $dir/spechla_env/lib/libncurses.so.6 $dir/spechla_env/lib/libncurses.so.5
ln -s $dir/spechla_env/lib/libtinfo.so.6 $dir/spechla_env/lib/libtinfo.so.5
# !

# install spechap
mkdir $dir/bin/SpecHap/build
cd $dir/bin/SpecHap/build

cmake .. -DCMAKE_PREFIX_PATH=$CONDA_PREFIX
make
cd $dir

echo " "
echo " "
echo " "
echo The installation is finished! Please start using SpecHLA.
echo "-------------------------------------"