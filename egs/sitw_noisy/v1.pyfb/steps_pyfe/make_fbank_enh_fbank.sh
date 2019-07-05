#!/bin/bash
# Copyright    2019       Johns Hopkins University (Author: Jesus Villalba)
#              2012-2016  Karel Vesely  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

# Begin configuration section.
nj=4
cmd=run.pl
fbank_config=conf/fbank.conf
compress=true
py_exec=pytorch-make-fbank-enh-fbank-i.py
use_gpu=false
write_utt2num_frames=false  # if true writes utt2num_frames
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
   echo "Usage: $0 [options] <data-dir> <nnet-model> [<log-dir> [<fbank-dir>] ]";
   echo "e.g.: $0 data/train exp/make_fbank/train mfcc"
   echo "Note: <log-dir> defaults to <data-dir>/log, and <fbank-dir> defaults to <data-dir>/data"
   echo "Options: "
   echo "  --py-exec <python-file>                        # python executable script  "
   echo "  --fbank-config <config-file>                     # config passed to compute-fbank-feats "
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo "  --write-utt2num-frames <true|false>     # If true, write utt2num_frames file."
   echo "  --use-gpu <true|false>     # uses the gpu"
   exit 1;
fi

data=$1
nnet_model=$2

if [ $# -ge 3 ]; then
  logdir=$3
else
  logdir=$data/log
fi
if [ $# -ge 4 ]; then
  fbankdir=$4
else
  fbankdir=$data/data
fi


# make $fbankdir an absolute pathname.
fbankdir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $fbankdir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $fbankdir || exit 1;
mkdir -p $logdir || exit 1;

if [ -f $data/feats.scp ]; then
  mkdir -p $data/.backup
  echo "$0: moving $data/feats.scp to $data/.backup"
  mv $data/feats.scp $data/.backup
fi

scp=$data/wav.scp

required="$scp $fbank_config"

for f in $required; do
  if [ ! -f $f ]; then
    echo "make_fbank.sh: no such file $f"
    exit 1;
  fi
done

utils/validate_data_dir.sh --no-text --no-feats $data || exit 1;

for n in $(seq $nj); do
  # the next command does nothing unless $fbankdir/storage/ exists, see
  # utils/create_data_link.pl for more info.
  utils/create_data_link.pl $fbankdir/raw_fbank_$name.$n.ark
done

opt_args=""

if $write_utt2num_frames; then
  opt_args="${opt_args} --write-num-frames $logdir/utt2num_frames.JOB"
fi

if $compress;then
  opt_args="${opt_args} --compress"
fi

num_gpus=0
if $use_gpu;then
    num_gpus=1
    opt_args="${opt_args} --use-gpu"
fi


if [ -f $data/segments ]; then
  echo "$0 [info]: segments file exists: using that."
  opt_args="${opt_args} --segments $data/segments"
fi

$cmd JOB=1:$nj --gpu $num_gpus $logdir/make_fbank_${name}.JOB.log \
    torch.sh --num-gpus $num_gpus \
    ${py_exec} @$fbank_config $opt_args --output-step logfb \
    --input $scp --output ark,scp:$fbankdir/raw_fbank_$name.JOB.ark,$fbankdir/raw_fbank_$name.JOB.scp \
    --part-idx JOB --num-parts $nj || exit 1


# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $fbankdir/raw_fbank_$name.$n.scp || exit 1;
done > $data/feats.scp

if $write_utt2num_frames; then
  for n in $(seq $nj); do
    cat $logdir/utt2num_frames.$n || exit 1;
  done > $data/utt2num_frames || exit 1
  rm $logdir/utt2num_frames.*
fi

nf=`cat $data/feats.scp | wc -l`
nu=`cat $data/utt2spk | wc -l`
if [ $nf -ne $nu ]; then
  echo "It seems not all of the feature files were successfully ($nf != $nu);"
  echo "consider using utils/fix_data_dir.sh $data"
fi

echo "Succeeded creating filterbank features for $name"
