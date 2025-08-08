#!/bin/bash
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

TEST_RUNNING=./TEST.RUNNING.DELME

setup_once() {
	mkdir -p /sys/fs/cgroup/cpu
	mount -t cgroup -o cpu none /sys/fs/cgroup/cpu
}

setup () {
	rm -f $TEST_RUNNING

	mkdir a
	mkdir b
	touch ./a/foreground
	touch ./a/background

	mkdir /sys/fs/cgroup/cpu/medium
	echo "512" > /sys/fs/cgroup/cpu/medium/cpu.shares

	mkdir /sys/fs/cgroup/cpu/low
	echo "4" > /sys/fs/cgroup/cpu/low/cpu.shares

}

cleanup () {
	rm -rf ./a
	rm -rf ./b
	rmdir /sys/fs/cgroup/cpu/medium
	rmdir /sys/fs/cgroup/cpu/low
}

something() {
   VAL=5
}

busy_cpu () {
	while [ -f "$TEST_RUNNING" ];
	do
		for i in {1..10000}
		do
			something
		done
	done
}

busy () {
	for i in `seq 1 $(($(nproc)*2))`;
	do
		busy_cpu &
	done
}

run_test () {
	setup
	touch $TEST_RUNNING

	if [ $BACKGROUND == "true" ]; then
		./rename-test ./a/background ./b/background &
		BACKGROUND_PID=$!
		if [ $THROTTLED == "true" ]; then
			echo $BACKGROUND_PID > /sys/fs/cgroup/cpu/low/cgroup.procs
		fi
	fi
	if [ $BUSY == "true" ]; then
		busy &
		BUSY_PID=$!
		if [ $THROTTLED == "true" ]; then
			echo $BUSY_PID > /sys/fs/cgroup/cpu/medium/cgroup.procs
		fi
	fi


	./rename-test -p ./a/foreground ./b/foreground > $OUT &
	FOREGROUND_PID=$!

	echo "I|$$|Test Begins" > /sys/kernel/tracing/trace_marker

	sleep 30

	echo "I|$$|Test Finished" > /sys/kernel/tracing/trace_marker

	kill -9 $FOREGROUND_PID
	if [ $BACKGROUND == "true" ]; then
		kill -9 $BACKGROUND_PID
	fi
	rm -f $TEST_RUNNING

	sort -n -o $OUT $OUT
	cleanup
}

if [ $EUID != 0 ]; then
	echo "Please run with sudo"
	exit
fi
setup_once

# Capture the results of the test running alone
echo "Running test alone..."
OUT=results-alone.log
BACKGROUND="false"
BUSY="false"
THROTTLED="false"
run_test

# Capture the results of the test running with VFS load (to create lock contention)
echo "Running test with contention..."
OUT=results-contention.log
BACKGROUND="true"
BUSY="false"
THROTTLED="false"
run_test

# Capture the results of the test running with scheduler load
echo "Running test with sched load..."
OUT=results-schedload.log
BACKGROUND="false"
BUSY="true"
THROTTLED="false"
run_test

# Capture the results of the test running with scheduler load & contention
echo "Running test with sched load & contention..."
OUT=results-schedload-contention.log
BACKGROUND="true"
BUSY="true"
THROTTLED="false"
run_test

# Capture the results of the test running w/ contetion throttled
echo "Running test with throttled contention..."
OUT=results-contention-throttled.log
BACKGROUND="true"
BUSY="false"
THROTTLED="true"
run_test

# Capture the results of the test running with scheduler load throttled
echo "Running test with throttled sched load..."
OUT=results-schedload-throttled.log
BACKGROUND="false"
BUSY="true"
THROTTLED="true"
run_test

# Capture the results of the test running with scheduler load & contention throttled
echo "Running test with throttled sched load & contention..."
OUT=results-schedload-contention-throttled.log
BACKGROUND="true"
BUSY="true"
THROTTLED="true"
run_test



