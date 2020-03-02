#!/bin/bash

# Copyright xmuspeech (Author: Snowdar 2020-02-27 2019-12-22)

prefix=mfcc_23_pitch
epochs="7 14 21"
positions="far near"

vectordir=exp/standard_xv_baseline_warmR_voxceleb1_adam

score=plda
train_set=voxceleb1_train_aug
enroll_set=voxceleb1_enroll
test_set=voxceleb1_test

score_norm=false # Use as-norm.
top_n=300
cohort_set= # If not NULL, use provided set
cohort_method="sub" # "sub" | "mean"
cohort_set_from=voxceleb1_train # Should be a subset of $trainset if use cohort_set_method.
sub_option="" # Could be --per-spk
sub_num=2000

prenorm=false
lda_norm=false
lda=true
clda=256
submean=false
default=true
string=
force=false

. subtools/parse_options.sh
. subtools/path.sh

trials=data/$prefix/$test_set/trials

lda_process="submean-trainlda"
plda_process="submean-lda-norm-trainplda"
test_process="submean-lda-norm"

lda_data_config="$train_set[$train_set $enroll_set $test_set]"
submean_data_config="$train_set[$train_set $enroll_set $test_set]"

if [[ "$default" == "true" && "$lda" == "true" ]];then
    [ "$score" == "cosine" ] && prenorm=false && lda_norm=false && clda=128
    [ "$score" == "plda" ] && prenorm=false && lda_norm=false && clda=256
fi

[ "$lda" == "true" ] && lda_string="_lda$clda"
[ "$submean" == "true" ] && submean_string="_submean"
[ "$lda_norm" == "true" ] && lda_process="norm-"$lda_process

if [ "$prenorm" == "true" ];then
    prenorm_string="_norm"
    test_process="norm-"$test_process
    plda_process="norm-"$plda_process
fi

if [[ "$test_set" == "voxceleb1_test" && "$enroll_set" == "voxceleb1_enroll" ]];then
    [ "$force" == "true" ] && rm -rf data/$prefix/voxceleb1_test/enroll.list data/$prefix/voxceleb1_enroll

    [ ! -f data/$prefix/voxceleb1_test/enroll.list ] && awk '{print $1}' $trials | sort -u > data/$prefix/voxceleb1_test/enroll.list
    [[ ! -d data/$prefix/voxceleb1_enroll ]] && subtools/filterDataDir.sh data/$prefix/voxceleb1_test \
              data/$prefix/voxceleb1_test/enroll.list data/$prefix/voxceleb1_enroll
fi

if [ "$score_norm" == "true" ];then
    if [ "$cohort_set" == "" ];then
        [[ "$force" == "true" ]] && rm -rf data/$prefix/$cohort_set
        if [ "$cohort_method" == "sub" ];then
            cohort_set=${cohort_set_from}_cohort_sub_${sub_num}$sub_option
            [ ! -d data/$prefix/$cohort_set ] && subtools/utils/subset_data_dir.sh $sub_option \
            data/$prefix/$cohort_set_from $sub_num data/$prefix/$cohort_set
        elif [ "$cohort_method" == "mean" ];then
            cohort_set=${cohort_set_from}_cohort_mean
            [ ! -d data/$prefix/$cohort_set ] && mkdir -p data/$prefix/$cohort_set && \
            awk '{print $1,$1}' data/$prefix/$cohort_set_from/spk2utt > data/$prefix/$cohort_set/spk2utt && \
            awk '{print $1,$1}' data/$prefix/$cohort_set_from/spk2utt > data/$prefix/$cohort_set/utt2spk
        fi
    fi

    [ ! -f data/$prefix/$cohort_set/utt2spk ] && echo "Expected cohort_set to exist." && exit 1
    [ "$force" == "true" ] && rm -rf data/$prefix/$cohort_set/enroll.list data/$prefix/$cohort_set/test.list \
        data/$prefix/$cohort_set/enroll.cohort.trials data/$prefix/$cohort_set/test.cohort.trials

    [ ! -f data/$prefix/$cohort_set/enroll.list ] && awk '{print $1}' $trials | sort -u > data/$prefix/$cohort_set/enroll.list
    [ ! -f data/$prefix/$cohort_set/test.list ] && awk '{print $2}' $trials | sort -u > data/$prefix/$cohort_set/test.list
    [ ! -f data/$prefix/$cohort_set/enroll.cohort.trials ] && sh subtools/getTrials.sh 3 data/$prefix/$cohort_set/enroll.list data/$prefix/$cohort_set/utt2spk data/$prefix/$cohort_set/enroll.cohort.trials
    [ ! -f data/$prefix/$cohort_set/test.cohort.trials ] && sh subtools/getTrials.sh 3 data/$prefix/$cohort_set/test.list data/$prefix/$cohort_set/utt2spk data/$prefix/$cohort_set/test.cohort.trials
fi

name="$test_set/score/${score}_${enroll_set}_${test_set}${prenorm_string}${submean_string}${lda_string}_norm"

results="\n[ $score ] [ lda=$lda clda=$clda submean=$submean ]"

for position in $positions;do

    results="$results\n\n--- ${position} ---\nepoch\teer%"
    [ "$score_norm" == "true" ] && results="${results}\tasnorm($top_n)-eer%"

    for epoch in $epochs;do
        obj_dir=$vectordir/${position}_epoch_${epoch}

        if [[ "$test_set" == "voxceleb1_test" && "$enroll_set" == "voxceleb1_enroll" ]];then
            [ "$force" == "true" ] && rm -rf $obj_dir/voxceleb1_enroll
            [[ ! -d $obj_dir/voxceleb1_enroll ]]  && subtools/filterVectorDir.sh $obj_dir/voxceleb1_test/xvector.scp \
              data/$prefix/voxceleb1_test/enroll.list $obj_dir/voxceleb1_enroll
        fi

        [[ "$force" == "true" || ! -f $obj_dir/$name.eer ]] && \
        subtools/scoreSets.sh  --prefix $prefix --score $score --vectordir $obj_dir --enrollset $enroll_set --testset $test_set \
            --lda $lda --clda $clda --submean $submean --lda-process $lda_process --trials $trials \
            --enroll-process $test_process --test-process $test_process --plda-process $plda_process \
            --lda-data-config "$lda_data_config" --submean-data-config "$submean_data_config" --plda-trainset $train_set

        if [[ "$score_norm" == "true" && -f $obj_dir/$name.score ]];then

            [[ "$force" == "true" ]] && rm -rf $obj_dir/$cohort_set
            if [ "$cohort_method" == "sub" ];then
                [[ "$force" == "true" ]] && rm -rf $obj_dir/$cohort_set
                [[ ! -d $obj_dir/$cohort_set ]] && subtools/filterVectorDir.sh $obj_dir/$train_set/xvector.scp \
                data/$prefix/$cohort_set/utt2spk $obj_dir/$cohort_set
            elif [ "$cohort_method" == "mean" ];then
                [[ ! -d $obj_dir/$cohort_set ]] && mkdir -p $obj_dir/$cohort_set && ivector-mean ark:data/$prefix/$cohort_set_from/spk2utt \
                scp:$obj_dir/$train_set/xvector.scp ark,scp:$obj_dir/$cohort_set/xvector.ark,$obj_dir/$cohort_set/xvector.scp
            fi

            enroll_cohort_name="$cohort_set/score/${score}_${enroll_set}_${cohort_set}${prenorm_string}${submean_string}${lda_string}_norm"
            test_cohort_name="$cohort_set/score/${score}_${test_set}_${cohort_set}${prenorm_string}${submean_string}${lda_string}_norm"
            output_name="${name}_asnorm${top_n}_$cohort_set"

            [[ "$force" == "true" ]] && rm -rf $obj_dir/$enroll_cohort_name.score $obj_dir/$test_cohort_name.score \
                                               $obj_dir/$output_name.score $obj_dir/$output_name.eer

            lda_data_config="$train_set[$train_set $enroll_set $cohort_set]"
            submean_data_config="$train_set[$train_set $enroll_set $cohort_set]"

            [ ! -f "$obj_dir/$enroll_cohort_name.score" ] && \
            subtools/scoreSets.sh  --prefix $prefix --eval true --score $score --vectordir $obj_dir \
                --lda $lda --clda $clda --submean $submean --lda-process $lda_process \
                --enroll-process $test_process --test-process $test_process --plda-process $plda_process \
                --lda-data-config "$lda_data_config" --submean-data-config "$submean_data_config" --plda-trainset $train_set \
                --enrollset $enroll_set --testset $cohort_set \
                --trials data/$prefix/$cohort_set/enroll.cohort.trials $string

            lda_data_config="$train_set[$train_set $test_set $cohort_set]"
            submean_data_config="$train_set[$train_set $test_set $cohort_set]"

            [ ! -f "$obj_dir/$test_cohort_name.score" ] && \
            subtools/scoreSets.sh  --prefix $prefix --eval true --score $score --vectordir $obj_dir \
                --lda $lda --clda $clda --submean $submean --lda-process $lda_process \
                --enroll-process $test_process --test-process $test_process --plda-process $plda_process \
                --lda-data-config "$lda_data_config" --submean-data-config "$submean_data_config" --plda-trainset $train_set \
                --enrollset $test_set --testset $cohort_set \
                --trials data/$prefix/$cohort_set/test.cohort.trials $string

            [ ! -f "$obj_dir/$output_name.score" ] && \
            python3 subtools/score/ScoreNormalization.py --top-n=$top_n --method="asnorm" $obj_dir/$name.score \
                                                        $obj_dir/$enroll_cohort_name.score $obj_dir/$test_cohort_name.score \
                                                        $obj_dir/$output_name.score

            #[ ! -f "$obj_dir/$output_name.eer" ] && \
            subtools/computeEER.sh --write-file $obj_dir/$output_name.eer $obj_dir/$output_name.score 3 $trials 3
            
            eer=""
            [ -f "$obj_dir/$output_name.eer" ] && eer=`cat $obj_dir/$output_name.eer`
            results="$results\n$epoch\t`cat $obj_dir/$name.eer`\t$eer"
        else
            eer=""
            [ -f "$obj_dir/$name.eer" ] && eer=`cat $obj_dir/$name.eer`
            results="$results\n$epoch\t$eer"
        fi
    done
done

echo -e $results > $vectordir/${score}${lda_string}${submean_string}.results

echo -e $results