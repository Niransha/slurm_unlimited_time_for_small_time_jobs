#!/bin/bash
#SBATCH --job-name=cug3dpred
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --gres=gpu:1
#SBATCH --partition=shortq7-gpu
#SBATCH --mail-type=ALL
#SBATCH --time=6:00:00
#SBATCH --mem=70gb
#SBATCH --nodelist=nodenviv100002
date
echo   "SLURM SUBMIT DIRECT. = "$SLURM_SUBMIT_DIR
echo   "NODE NAMES           = "$SLURM_NODELIST
echo   "CUDA_VISIBLE_DEVICES = "$CUDA_VISIBLE_DEVICES
##########################################################
#
# Load the necessary modules, etc...
#
##########################################################
source /mnt/rna/home/programs/amber22/amber.sh
sander="$AMBERHOME/bin/pmemd.cuda"
mdstop=500
# mdstop = Total number of MD production runs
##########################################################
#
# Go to the submission dir, and create the necessary temp files under /tmp/$USER
#
##########################################################
cd     $SLURM_SUBMIT_DIR
sleep 1
mkdir -p /tmp/$USER
sleep 1
mkdir -p /tmp/$USER/$SLURM_JOBID
sleep 1
##########################################################
#
# Copy the files to the recently created temp directory
#
##########################################################
#
cp ./inpcrd ./md_*.rst ./min*.rst ./eq*.rst ./prmtop.new /tmp/$USER/$SLURM_JOBID
sleep 1
cd    /tmp/$USER/$SLURM_JOBID
sleep 1
##########################################################
#
# Create the necessary files, and run the jobs. The first time will be to
# minimize/equilibrate the system. The rest will be just a single MD run.
#
##########################################################
#
# Extract the last .rst file
#
##########################################################
old=`ls -l md_*.rst 2> /dev/null | awk '{split($9,a,"."); split(a[1],b,"_"); print b[2]}' | sort -k1,1n | tail -1`
#
if [ -z "$old" ]; then
#  echo "old is NULL (old = $old)"
  eqcheck=`ls -l eq2.rst 2> /dev/null | awk '{s++}END{print s}'`
  #
  if [ -z "$eqcheck" ]; then
    echo "We need to minimize and equilibrate the system..."
    ##########################################################
    #
    # First Minimization
    #
    ##########################################################
    cat << EOF > min1.in
First Minimize
 &cntrl
  imin   = 1,   maxcyc = 10000,
  ncyc   = 5000,   ntb    = 1,
  ntr    = 1,   restraint_wt = 10.0, restraintmask = " ! @H= & ! :WAT,Na+,Cl-",
  cut    = 10.0,   nmropt=0,
 /
EOF
    ##########################################################
    #
    # Second minimization
    #
    ##########################################################
    cat << EOF > min2.in
Second minimization
 &cntrl
  imin   = 1,   maxcyc = 5000,   ncyc   = 2500,
  ntb    = 1,   ntr    = 0,   cut    = 10.0,
 /
EOF
    ##########################################################
    #
    # Run the minimization
    #
    ##########################################################
    $sander -O -i min1.in -p prmtop.new -c inpcrd -o min1.out -r min1.rst -ref inpcrd
    #
    $sander -O -i min2.in -p prmtop.new -c min1.rst -o min2.out -r min2.rst -ref inpcrd
    ##########################################################
    #
    # First Equilibration
    #
    ##########################################################
    cat << EOF > eq1.in
First Equilibration
 &cntrl
  imin=0, irest=0, ntx=1, ntb=1,
  cut=10.0,
  ntr=1, restraint_wt = 1.0, restraintmask = " ! @H= & ! :WAT,Na+,Cl-",
  ntc=2, ntf=2, tempi=0.0, temp0=310.15, ntt=3,
  gamma_ln=1.0, ig=-1, nstlim=1000000, dt=0.002,
  ntpr=1000, ntwx=1000, ntwr=1000,
 /
EOF
    ##########################################################
    #
    # Second equilibration
    #
    ##########################################################
    cat << EOF > eq2.in
Second equilibration
 &cntrl
  imin=0, irest=1, ntx=5, ntb=2, cut=10.0,
  ntr=1, restraint_wt = 1.0, restraintmask = " ! @H= & ! :WAT,Na+,Cl-",
  pres0=1.0, ntp=1, taup=2.0, ntc=2, ntf=2,
  tempi=310.15, temp0=310.15, ntt=3, gamma_ln=1.0,
  ig=-1, nstlim=1000000, dt=0.002,
  ntpr = 1000, ntwx = 1000, ntwr = 1000,
  pencut=-0.001, nmropt=0,
 /
EOF
    ##########################################################
    #
    # Run the equilibration
    #
    ##########################################################
    $sander -O -i eq1.in -p prmtop.new -c min2.rst -o eq1.out -r eq1.rst -x eq1.mdcrd -ref min2.rst
    #
    $sander -O -i eq2.in -p prmtop.new -c eq1.rst -o eq2.out -r eq2.rst -x eq2.mdcrd -ref min2.rst
    #
    cp min[1-2].* eq[1-2].* $SLURM_SUBMIT_DIR
  else
    echo "We already have the equilibrated file; eqcheck = $eqcheck"
    cat << EOF > md.in
20 ns production run (explicit solvent)
 &cntrl
  imin=0,
  ntx=5,irest=1,
  ntpr=10000,ntwr=10000,ntwx=10000,
  ntc=2,ntf=2,ntb=2,cut=10,
  igb=0,ntr=0,
  nstlim=10000000,nmropt=0,
  dt=0.002,nscm=10000,
  ntt=3,gamma_ln=1,tempi=310.15,temp0=310.15,ig=-1,
  ntp=1,taup=2.0, pres0=1, ioutfm=1,
 /
EOF
    #
    $sander -O -i md.in -p prmtop.new -c eq2.rst -o md_1.out -r md_1.rst -x md_1.mdcrd
    cp md_1.* $SLURM_SUBMIT_DIR
  fi
else
#  echo "old is NOT NULL (old = $old)"
  cat << EOF > md.in
20 ns production run (explicit solvent)
 &cntrl
  imin=0,
  ntx=5,irest=1,
  ntpr=10000,ntwr=10000,ntwx=10000,
  ntc=2,ntf=2,ntb=2,cut=10,
  igb=0,ntr=0,
  nstlim=10000000,nmropt=0,
  dt=0.002,nscm=10000,
  ntt=3,gamma_ln=1,tempi=310.15,temp0=310.15,ig=-1,
  ntp=1,taup=2.0, pres0=1, ioutfm=1,
 /
EOF
  #
  new=$(( $old + 1 ))
  $sander -O -i md.in -p prmtop.new -c md_$old.rst -o md_$new.out -r md_$new.rst -x md_$new.mdcrd
  cp md_$new.* $SLURM_SUBMIT_DIR
fi
cd $SLURM_SUBMIT_DIR
rm -dvfr /tmp/$USER/$SLURM_JOBID
##########################################################
#
# We need to decide if we need to perform another MD run
#
##########################################################

old=`ls -l md_*.rst 2> /dev/null | awk '{split($9,a,"."); split(a[1],b,"_"); print b[2]}' | sort -k1,1n | tail -1`

if [ -z "$old" ] || [ $old -lt $mdstop ]; then
  sbatch atlas.gpu_run_new_min_eq_production.sh
fi
#
date


