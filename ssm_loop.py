# -*- coding: utf-8 -*-

"""
Created on Wed Aug 15 12:25:32 2022

@author: arianayoum
"""
# import packages
import pandas as pd
import os
import glob
import numpy as np
import pandas as pd
import seaborn as sns
import nibabel as nib
from bids import BIDSLayout, BIDSValidator
from nltools.file_reader import onsets_to_dm
from nltools.stats import regress, zscore
from nltools.data import Brain_Data, Design_Matrix
from nltools.stats import find_spikes 
from nilearn.plotting import view_img, glass_brain, plot_stat_map
from nilearn.image import load_img
from nilearn.image import binarize_img
from nilearn.image import resample_to_img
import scipy.stats as stats
import requests

sub=os.environ['sub']
print(sub)

# Set up directory
data_dir = '/gaia/duncanlab/mematt/MID_Dartbrains/data/bids/'
output_dir = '/gaia/duncanlab/mematt/MID_Dartbrains/output/ssm'
layout = BIDSLayout(data_dir, derivatives=True)

# Function to create design matrix
def load_bids_events(layout, subject):
    '''Create a design_matrix instance from BIDS event file'''
    tr = layout.get_tr(task='MID')
    n_tr = nib.load(layout.get(subject=subject, task='MID', scope='raw', suffix='bold', extension='nii.gz')[0].path).shape[-1]
    onsets = pd.read_csv(layout.get(subject=subject, suffix='events')[0].path, sep='\t')
    onsets.columns = ['Onset', 'Duration', 'Stim']
    return onsets_to_dm(onsets, sampling_freq=1/tr, run_length=n_tr)

# Function to define motion covariates
def make_motion_covariates(mc, tr):
    z_mc = zscore(mc)
    all_mc = pd.concat([z_mc, z_mc**2, z_mc.diff(), z_mc.diff()**2], axis=1)
    all_mc.fillna(value=0, inplace=True)
    return Design_Matrix(all_mc, sampling_freq=1/tr)

# Add events to design matrix
dm = load_bids_events(layout, sub)
dm_conv = dm.convolve()
dm_conv_filt = dm_conv.add_dct_basis(duration=220)
dm_conv_filt_poly = dm_conv_filt.add_poly()

# Read in data
layout = BIDSLayout(data_dir, derivatives=True)
preprocessed_func = load_img(layout.get(subject=sub, task='MID', scope='derivatives', regex_search=True, space='MIITRA', suffix='bold', extension='nii.gz', return_type='file')[1])

# Load in the mask
mask_img = load_img('/gaia/duncanlab/mematt/ANTs/templates/MIITRA_1/MIITRA_1_BrainExtractionBrain.nii.gz')
# Binarize mask
binarized_mask_r = binarize_img(mask_img)
# Save as NIFTI
binarized_mask_r.to_filename(f'{output_dir}/{sub}_binarized_mask.nii.gz')
# Final data
data = Brain_Data(preprocessed_func, mask = f'{output_dir}/{sub}_binarized_mask.nii.gz')

# Motion correction
covariates = pd.read_csv(layout.get(subject=sub, scope='derivatives', task='MID', extension='.tsv')[0].path, sep='\t')
mc = covariates[['trans_x','trans_y','trans_z','rot_x', 'rot_y', 'rot_z']]
tr = layout.get_tr()
mc_cov = make_motion_covariates(mc, tr)

fmriprep_motion_regressors = [i for i in covariates if i.startswith('motion')]
fmriprep_other_regressors = [i for i in covariates if (i=='csf') or (i=='white_matter')]
spikes = covariates[fmriprep_motion_regressors]
others = covariates[fmriprep_other_regressors]
spikes['csf_zscore'] = stats.zscore(others['csf'])
spikes['wm_zscore'] = stats.zscore(others['white_matter'])

spikes = Design_Matrix(spikes.iloc[:,1:], sampling_freq=1/tr)
dm_conv_filt_poly_cov = pd.concat([dm_conv_filt_poly, mc_cov, spikes], axis=1)

# Smooth brain data
fwhm=4
smoothed = data.smooth(fwhm=fwhm)
smoothed.X = dm_conv_filt_poly_cov
stats = smoothed.regress()

# Save data
smoothed.write(f'{output_dir}/{sub}_betas_denoised_smoothed{fwhm}_preprocessed_fMRI_bold.nii.gz')
(stats['t']).write(f'{output_dir}/{sub}_tstats_denoised_smoothed4_preprocessed_fMRI_bold.nii.gz')
(stats['p']).write(f'{output_dir}/{sub}_pvals_denoised_smoothed4_preprocessed_fMRI_bold.nii.gz')
(stats['residual']).write(f'{output_dir}/{sub}_residual_denoised_smoothed4_preprocessed_fMRI_bold.nii.gz')

for i, name in enumerate([x[:-3] for x in dm_conv_filt_poly_cov.columns[:10]]):
        stats['beta'][i].write(f'{output_dir}/betas/{sub}_beta_{name}.nii.gz')
        stats['t'][i].write(f'{output_dir}/tstats/{sub}_tstat_{name}.nii.gz')
        stats['p'][i].write(f'{output_dir}/pvals/{sub}_pval_{name}.nii.gz')