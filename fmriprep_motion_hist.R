###  MOTION CONFOUND REGRESSORS HISTOGRAM  ###
library(dplyr)
library(data.table)
library(stringr)

#### subject IDs ####
setwd("/Volumes/sambashare/duncanlab/mematt/bids/data/derivatives/fmriprep/")
sublist <- list.dirs(path = ".", full.names = FALSE, recursive = FALSE)

# Delete any extraneous elements
sublist <- sublist[-1]

#### MOTION CONFOUNDS ####
# this makes the motion confound files for each subject using fMRIprep output

# Create empty dataframe for motion outlier data
TRs <- data.frame(matrix(ncol = 2, nrow = 0))
x <- c("subject", "outliers")
colnames(TRs) <- x

for (sub in sublist) {
  
  # set to your fmriprep output folder
  setwd("/Volumes/sambashare/duncanlab/mematt/bids/data/derivatives/fmriprep")
  
  # set to your fmriprep output motion confounds file
  readfile_name <- paste(sub,'/func/',sub,'_task-MID_desc-confounds_regressors.tsv', sep = "")
  print(readfile_name)
  confounds_full <- read.table(file = readfile_name, sep = '\t', header = TRUE, na.strings = 'n/a')
  
  # get any column that starts with motion_outlierXX
  # these are the TRs flagged by fmriprep
  motflags <- confounds_full %>% dplyr:: select(starts_with("motion_outlier"))
  
  # count the TRs flagged by fmriprep
    outliers <- ncol(motflags)
    temp <- data.frame(sub, outliers)
    TRs <- rbind(TRs, temp)
  
}

library(ggplot2)
ggplot(data = TRs, aes(x = outliers)) + 
  geom_histogram(binwidth = 5, color = "black", fill = "white")
