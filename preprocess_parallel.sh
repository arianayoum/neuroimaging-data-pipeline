#!/bin/bash

# Hello! The purpose of this script is to register brains to template brain using ANTs

# Before you use this script, make sure to:
# 1) Set up a screen session
# 2) Enter docker
    # docker run -it --rm \
    # -v /gaia/duncanlab/mematt/:/mematt \
    # -v /gaia/duncanlab/mematt/freesurfer/license.txt:/opt/freesurfer-6.0.0/license.txt \
    # -e ANTSPATH=/data/bin \
    # aridocker
# 3) Have landmarkmatch.sh in the same directory

preprocess_parallel () {

# 1. Segment brains using FreeSurfer using T1 and T2
    # Freesurfer needs the ECTS_DIR to be specified
    export SUBJECTS_DIR=/mematt/bids/pilot

    # Go into subjects directory
    cd $SUBJECTS_DIR

    # If participant's folder begins with "sub":
    if  [[ $1 == sub* ]] ;
    then
      # Go into each participant's anat folder
      cd $1/anat

    	# Convert NIFTI to mgz
    	mri_convert --out_orientation RAS --in_type nii --out_type mgz ${1}_T1w.nii.gz 001.mgz

      # Create mri subfolder
      cd ../
      mkdir mri/

    	# Put 001.mgz file into mri folder
    	mv ${SUBJECTS_DIR}/${1}/anat/001.mgz ${SUBJECTS_DIR}/${1}/mri

      # If participant has both T1 and T2, segment with both. Else, segment with T1:
      if grep -q T1w "$File" & grep -q T2w "$File";
      then
        recon-all -all -s ${1} -hippocampal-subfields-T1T2 ${SUBJECTS_DIR}/${1}/anat/${1}_T2w.nii.gz T1T2_HPC
      else
        recon-all -s ${1} -i ${SUBJECTS_DIR}/${1}/anat/${1}_T1w.nii.gz -all
      fi

    	# Go into mri subfolder
    	cd mri/

    	# Bring segmentation into native space
    	mri_label2vol --seg aseg.mgz --temp rawavg.mgz --o ${1}aseg-in-rawavg.mgz --regheader aseg.mgz

    	# Convert to NIFTI
    	mri_convert --out_orientation RAS --in_type mgz --out_type nii ${1}aseg-in-rawavg.mgz ${1}aseg_native.nii

  # 2. Create a subcortical mask of ROIs of interest
      # Create subcortical mask
    	3dcalc -a ${1}aseg_native.nii -expr '(amongst(a,11,12,13,17,18,26,50,51,52,53,54,58))*a' -prefix ${1}anchor_mask.nii

  # 3. Smooth the ROIs
    	# Remove rogue voxels
    	3dcalc -prefix ${1}anchor_mask_cleaned.nii -a ${1}anchor_mask.nii \
    	-b 'a[-1,1,0,0]' \
    	-c 'a[0,1,0,0]' \
    	-d 'a[1,1,0,0]' \
    	-e 'a[-1,0,0,0]' \
    	-f 'a[1,0,0,0]' \
    	-g 'a[-1,-1,0,0]' \
    	-h 'a[0,-1,0,0]' \
    	-i 'a[1,-1,0,0]' \
    	-j 'a[0,1,1,0]' \
    	-k 'a[-1,0,1,0]' \
    	-l 'a[1,0,1,0]' \
    	-m 'a[0,-1,1,0]' \
    	-n 'a[0,0,1,0]' \
    	-o 'a[0,1,-1,0]' \
    	-p 'a[-1,0,-1,0]' \
    	-q 'a[1,0,-1,0]' \
    	-r 'a[0,-1,-1,0]' \
    	-s 'a[0,0,-1,0]' \
    	-expr 'hmode(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s)'

  # 4. Skull strip all brains using ANTs Brain Extraction

      # Run ANTs brain extraction script
      export ANTSPATH=/data/bin
      cd /data/scripts/
      ./antsBrainExtraction.sh \
      -d 3 \
      -a $SUBJECTS_DIR/${1}/anat/${1}_T1w.nii.gz \
      -e /data/skullstrip_templates/T_template0.nii.gz \
      -m /data/skullstrip_templates/T_template0_BrainCerebellumProbabilityMask.nii.gz \
      -f /data/skullstrip_templates/T_template0_BrainCerebellumRegistrationMask.nii.gz \
      -o $SUBJECTS_DIR/${1}/anat/${1}_

  # 5. Register brains to template brain using ANTs landmark matching function
      cd /data/scripts/
      ./landmarkmatch.sh \
      /data/braintemplate/anat/colintoOA_BrainExtractionBraindeformed.nii.gz \
      /data/braintemplate/mri/colintoOA_w1_anchormaskcleaned.nii \
      ${SUBJECTS_DIR}/${1}/anat/${1}_BrainExtractionBrain.nii.gz \
      ${SUBJECTS_DIR}/${1}/mri/${1}anchor_mask_cleaned.nii \
      1000 \
      1

  # 6. Update .json files to add in TaskName
      # Rest
      funcpath=func/${1}_task-rest_bold.json
      jq '.TaskName="rest"' <${SUBJECTS_DIR}/${1}/${funcpath} | sponge ${SUBJECTS_DIR}/${1}/${funcpath}
      funcpath=func/${1}_task-rest_bold.nii.gz

      # Task
      funcpath=func/${1}_task-MID_bold.json
      jq '.TaskName="MID"' <${SUBJECTS_DIR}/${1}/${funcpath} | sponge ${SUBJECTS_DIR}/${1}/${funcpath}
      funcpath=func/${1}_task-MID_bold.nii.gz

  # 7. Run fmriprep to implement motion correction and registration to T1
      # set Path
      export PATH="/home/ariana/.local/bin:$PATH"

      #User inputs:
      subj=${1: -3}
      nthreads=4
      mem=20 #gb

      #Begin:
      #Convert virtual memory from gb to mb
      mem=`echo "${mem//[!0-9]/}"` #remove gb at end
      mem_mb=`echo $(((mem*1000)-5000))` #reduce some memory for buffer space during pre-processing

      export TEMPLATEFLOW_HOME=$HOME/.cache/templateflow
      export FS_LICENSE=/gaia/duncanlab/mematt/freesurfer/license.txt

      fmriprep-docker $SUBJECTS_DIR $SUBJECTS_DIR/derivatives \
        participant \
        --participant-label $subj \
        --skip-bids-validation \
        --ignore slicetiming \
        --md-only-boilerplate \
        --fs-license-file /gaia/duncanlab/mematt/freesurfer/license.txt \
        --fs-no-reconall \
        --output-spaces T1w \
        --nthreads $nthreads \
        --stop-on-first-crash \
        --mem_mb $mem_mb \
        -w $HOME

  # 7. Apply transformations to func data - make sure warp is the "first" step b
      # This way the warp will actually be last bc it's applied inversely
      antsApplyTransforms \
      -d 3 \
      -i ${SUBJECTS_DIR}/${1}/mri/${1}anchor_mask_cleaned.nii \
      -r /data/braintemplate/mri/colintoOA_w1_anchormaskcleaned.nii \
      -o ${SUBJECTS_DIR}/${1}/mri/${1}_w1_ROIwarped.nii.gz \
      -n nearestNeighbor \
      -t ${SUBJECTS_DIR}/${1}/anat/${1}_BrainExtractionBrainWarp.nii.gz \
      -t ${SUBJECTS_DIR}/${1}/anat/${1}_BrainExtractionBrainAffine.txt \
      -v 1

      # Remove rogue voxels
      3dcalc -prefix ${SUBJECTS_DIR}/${1}/mri/${1}_w1_anchor_mask_cleaned.nii \
      -a ${SUBJECTS_DIR}/${1}/mri/${1}_w1_ROIwarped.nii.gz \
      -b 'a[-1,1,0,0]' \
      -c 'a[0,1,0,0]' \
      -d 'a[1,1,0,0]' \
      -e 'a[-1,0,0,0]' \
      -f 'a[1,0,0,0]' \
      -g 'a[-1,-1,0,0]' \
      -h 'a[0,-1,0,0]' \
      -i 'a[1,-1,0,0]' \
      -j 'a[0,1,1,0]' \
      -k 'a[-1,0,1,0]' \
      -l 'a[1,0,1,0]' \
      -m 'a[0,-1,1,0]' \
      -n 'a[0,0,1,0]' \
      -o 'a[0,1,-1,0]' \
      -p 'a[-1,0,-1,0]' \
      -q 'a[1,0,-1,0]' \
      -r 'a[0,-1,-1,0]' \
      -s 'a[0,0,-1,0]' \
      -expr 'hmode(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s)'

    fi

}

export -f preprocess_parallel;
# -n 1 means take the arguments one at a time
# -P 1 means use just one processor
# -I starting_i means take the value that has just been fed to xargs and call it ‘starting_i’
date
ls /mematt/bids/pilot | xargs -n 3 -P 4 -I starting_i bash -c 'preprocess_parallel starting_i';
date
