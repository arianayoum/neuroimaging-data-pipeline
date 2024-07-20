
bids_format () {

  # Absolute path of the directory
  bidsdir=/gaia/duncanlab/mematt/bids

  dcm2bids \
      -d $bidsdir/update/${1} \
      -p ${1} \
      -c $bidsdir/scripts/config.json \
      -o $bidsdir
    }

    export -f bids_format;
    # -n 1 means take the arguments one at a time
    # -P 1 means use just one processor
    # -I starting_i means take the value that has just been fed to xargs and call it ‘starting_i’
    date
    ls /gaia/duncanlab/mematt/bids/update | xargs -n 3 -P 4 -I starting_i bash -c 'bids_format starting_i';
    date
