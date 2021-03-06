#!/bin/bash
#Copyright (C) 2014 OpenBet Limited
#
#Permission is hereby granted, free of charge, to any person obtaining a copy 
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

TESTS=$1

pushd $(dirname ${BASH_SOURCE[0]})/.. > /dev/null 2>&1

#set -x

source test/shared_test_utils.sh

# Variables
NEWDIR=/tmp/shutit_testing_$$_$(hostname)_$(whoami)_$(date -I)_$(date +%N)
SHUTIT_DIR="$(pwd)"
readonly NEWDIR SHUTIT_DIR

set_shutit_options

# Check we can use docker
if ! $DOCKER info >/dev/null 2>&1; then
	echo "Failed to run docker! - used command \"$DOCKER info\" to check"
	false
fi

# This is a fallback, any tests runnable on their own should include the below
if [[ $0 != test.sh ]] && [[ $0 != ./test.sh ]]
then
	echo "Must be run from dir of test.sh"
	exit 1
fi

if [[ "$(sed -n '15p' assets/shutit_module_template.py)" != "		# Line number 16 should be the next one (so bash scripts can be inserted properly)" ]]
then
	echo "Line 15 of assets/shutit_module_template.py should be as test.sh specifies"
	exit 1
fi

#PYTHONPATH=$(pwd) python test/test.py 

find ${SHUTIT_DIR} -name '*.cnf' | grep '/configs/[^/]*.cnf' | xargs chmod 600
cleanup hard

DESC="Testing skeleton build with Dockerfile"
echo $DESC
./shutit skeleton -d assets/dockerfile/Dockerfile ${NEWDIR} testing shutit.tk
pushd ${NEWDIR}/bin
./test.sh
if [[ "x$?" != "x0" ]]
then
	echo "FAILED ON $DESC"
	cleanup hard
	exit 1
fi
cleanup hard
rm -rf ${NEWDIR}
popd > /dev/null 2>&1

DESC="Testing skeleton build basic bare"
echo $DESC
./shutit skeleton ${NEWDIR} testing shutit.tk
pushd ${NEWDIR}/bin
./test.sh
if [[ "x$?" != "x0" ]]
then
	echo "FAILED ON $DESC"
	cleanup hard
	exit 1
fi
cleanup hard
rm -rf ${NEWDIR}
popd > /dev/null 2>&1


DESC="Testing skeleton build basic with example script"
echo $DESC
./shutit skeleton ${NEWDIR} testing shutit.tk ${SHUTIT_DIR}/assets/example.sh
pushd ${NEWDIR}/bin
./test.sh
if [[ "x$?" != "x0" ]]
then
	echo "FAILED ON $DESC"
	cleanup hard
	exit 1
fi
cleanup hard
rm -rf ${NEWDIR}
popd > /dev/null 2>&1


# General tests
mkdir -p /tmp/shutit_logs/$$
declare -A PIDS
PIDS=()
DISTROS=${SHUTITTEST_DISTROS:-ubuntu:12.04}
for dist in $DISTROS
do
	for d in $(ls test | grep -v configs)
	do
		[ -d ${SHUTIT_DIR}/test/$d ] || continue
		pushd ${SHUTIT_DIR}/test/$d > /dev/null 2>&1
		if [[ -a STOPTEST ]]
		then
			echo "STOPTEST file found in $(pwd)"
		else 
			if [[ -a /tmp/SHUTITSTOPTEST ]]
			then
				echo "/tmp/SHUTITSTOPTEST file found in /tmp"
			else
				# Must be done on each iteration as we ned a fresh cid per test run
				set_shutit_options "--image_tag $dist --interactive 0"
				echo "================================================================================"
				echo "SHUTIT MODULE TEST $d: In directory: `pwd` BEGIN"
				echo "================================================================================"
				if [ x$SHUTIT_PARALLEL_BUILD = 'x' ]
				then
					cmd="./test.sh 2>&1 | tee /tmp/shutit_logs/$$/shutit_core_test_$(date +%s)"
					echo "================================================================================"
					echo "RUNNING: $cmd"
					echo "================================================================================"
					$cmd
					RES=$?
					if [[ "x$RES" != "x0" ]]
					then
						echo "FAILURE |$RES| in: $(pwd) running $cmd"
						cleanup hard
						exit 1
					fi
					cleanup hard
					echo "================================================================================"
					echo "SHUTIT MODULE TEST $d: In directory: `pwd` END"
					echo "================================================================================"
				else
					# TODO
					#http://stackoverflow.com/questions/356100/how-to-wait-in-bash-for-several-subprocesses-to-finish-and-return-exit-code-0
					./test.sh 2>&1 | tee /tmp/shutit_logs/$$/shutit_core_test_$(date +%s)
					JOB=$!
					PIDS[$JOB]="$JOB: $dist $d"
				fi
				set_shutit_options
			fi
		fi
		report
		popd > /dev/null 2>&1
	done
done

if [ x$SHUTIT_PARALLEL_BUILD != 'x' ]
then
	for P in ${!PIDS[*]}; do
		echo "WAITING FOR $P"
		wait $P 
		if [[ $? != 0 ]]
		then
			cleanup hard
			exit 1
		fi
		report
		cleanup nothard
	done
fi

# Library tests
if [[ $TESTS != 'basic' ]]
then
	pushd  ${SHUTIT_DIR}/library/bin
	./test.sh 
	if [[ $? != 0 ]]
	then
		cleanup hard
		exit 1
	fi
	popd > /dev/null 2>&1
	cleanup nothard
	report
fi

report
cleanup hard

popd > /dev/null 2>&1
# OK
echo "SHUTIT TEST OK"
exit

