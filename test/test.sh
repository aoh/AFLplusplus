#!/bin/bash

#
# Ensure we have: test, type, diff -q, echo -e, grep -aqE, timeout
#
test -z "" 2> /dev/null || { echo Error: test command not found ; exit 1 ; }
GREP=`type grep > /dev/null 2>&1 && echo OK`
TIMEOUT=`type timeout > /dev/null 2>&1 && echo OK`
test "$GREP" = OK || { echo Error: grep command not found ; exit 1 ; }
echo foobar | grep -aqE 'asd|oob' 2> /dev/null || { echo Error: grep command does not support -q, -a and/or -E option ; exit 1 ; }
echo 1 > test.1
echo 1 > test.2
OK=OK
diff -q test.1 test.2 >/dev/null 2>&1 || OK=
rm -f test.1 test.2
test -z "$OK" && { echo Error: diff -q is not working ; exit 1 ; }

ECHO="echo -e"
$ECHO '\x41' 2>&1 | grep -qE '^A' || {
  ECHO=
  test -e /bin/echo && {
    ECHO="/bin/echo -e"
    $ECHO '\x41' 2>&1 | grep -qE '^A' || ECHO=
  }
}
test -z "$ECHO" && { echo Error: echo command does not support -e option ; exit 1 ; }

export AFL_EXIT_WHEN_DONE=1
export AFL_SKIP_CPUFREQ=1
unset AFL_QUIET
unset AFL_DEBUG
unset AFL_HARDEN
unset AFL_USE_ASAN
unset AFL_USE_MSAN
unset AFL_CC
unset AFL_PRELOAD
unset AFL_LLVM_WHITELIST
unset AFL_LLVM_INSTRIM
unset AFL_LLVM_LAF_SPLIT_SWITCHES
unset AFL_LLVM_LAF_TRANSFORM_COMPARES
unset AFL_LLVM_LAF_SPLIT_COMPARES

GREY="\\x1b[1;90m"
BLUE="\\x1b[1;94m"
GREEN="\\x1b[0;32m"
RED="\\x1b[0;31m"
YELLOW="\\x1b[1;93m"
RESET="\\x1b[0m"

$ECHO "${RESET}${GREY}[*] starting afl++ test framework ..."

$ECHO "$BLUE[*] Testing: afl-gcc, afl-showmap and afl-fuzz"
test -e ../afl-gcc -a -e ../afl-showmap -a -e ../afl-fuzz && {
  ../afl-gcc -o test-instr.plain ../test-instr.c > /dev/null 2>&1
  AFL_HARDEN=1 ../afl-gcc -o test-instr.harden ../test-instr.c > /dev/null 2>&1
  test -e test-instr.plain && {
    $ECHO "$GREEN[+] afl-gcc compilation succeeded"
    echo 0 | ../afl-showmap -o test-instr.plain.0 -r -- ./test-instr.plain > /dev/null 2>&1
    ../afl-showmap -o test-instr.plain.1 -r -- ./test-instr.plain < /dev/null > /dev/null 2>&1
    test -e test-instr.plain.0 -a -e test-instr.plain.1 && {
      diff -q test-instr.plain.0 test-instr.plain.1 > /dev/null 2>&1 && {
        $ECHO "$RED[!] afl-gcc instrumentation should be different on different input but is not"
      } || $ECHO "$GREEN[+] afl-gcc instrumentation present and working correctly"
    } || $ECHO "$RED[!] afl-gcc instrumentation failed"
    rm -f test-instr.plain.0 test-instr.plain.1
  } || $ECHO "$RED[!] afl-gcc failed"
  test -e test-instr.harden && {
    grep -qa fstack-protector-all test-instr.harden > /dev/null 2>&1 && {
      $ECHO "$GREEN[+] afl-gcc hardened mode succeeded and is working"
    } || $ECHO "$RED[!] afl-gcc hardened mode is not hardened"
    rm -f test-instr.harden
  } || $ECHO "$RED[!] afl-gcc hardened mode compilation failed"
  # now we want to be sure that afl-fuzz is working  
  test -n "$TIMEOUT" && {
    mkdir -p in
    echo 0 > in/in
    $ECHO "$GREY[*] running afl-fuzz for afl-gcc, this will take approx 10 seconds"
    {
      timeout -s KILL 10 ../afl-fuzz -i in -o out -- ./test-instr.plain > /dev/null 2>&1
    } > /dev/null 2>&1
    test -n "$( ls out/queue/id:000002* 2> /dev/null )" && {
      $ECHO "$GREEN[+] afl-fuzz is working correctly with afl-gcc"
    } || $ECHO "$RED[!] afl-fuzz is not working correctly with afl-gcc"
    rm -rf in out
  } || $ECHO "$YELLOW[-] we cannot test afl-fuzz because we are missing the timeout command"
  rm -f test-instr.plain
} || $ECHO "$YELLOW[-] afl is not compiled, cannot test"

$ECHO "$BLUE[*] Testing: llvm_mode"
test -e ../afl-clang-fast && {
  ../afl-clang-fast -o test-instr.plain ../test-instr.c > /dev/null 2>&1
  AFL_HARDEN=1 ../afl-clang-fast -o test-compcov.harden test-compcov.c > /dev/null 2>&1
  test -e test-instr.plain && {
    $ECHO "$GREEN[+] llvm_mode compilation succeeded"
    echo 0 | ../afl-showmap -o test-instr.plain.0 -r -- ./test-instr.plain > /dev/null 2>&1
    ../afl-showmap -o test-instr.plain.1 -r -- ./test-instr.plain < /dev/null > /dev/null 2>&1
    test -e test-instr.plain.0 -a -e test-instr.plain.1 && {
      diff -q test-instr.plain.0 test-instr.plain.1 > /dev/null 2>&1 && {
        $ECHO "$RED[!] llvm_mode instrumentation should be different on different input but is not"
      } || $ECHO "$GREEN[+] llvm_mode instrumentation present and working correctly"
    } || $ECHO "$RED[!] llvm_mode instrumentation failed"
    rm -f test-instr.plain.0 test-instr.plain.1
  } || $ECHO "$RED[!] llvm_mode failed"
  test -e test-compcov.harden && {
    grep -Eqa 'stack_chk_fail|fstack-protector-all|fortified' test-compcov.harden > /dev/null 2>&1 && {
      $ECHO "$GREEN[+] llvm_mode hardened mode succeeded and is working"
    } || $ECHO "$RED[!] llvm_mode hardened mode is not hardened"
    rm -f test-compcov.harden
  } || $ECHO "$RED[!] llvm_mode hardened mode compilation failed"
  # now we want to be sure that afl-fuzz is working  
  test -n "$TIMEOUT" && {
    mkdir -p in
    echo 0 > in/in
    $ECHO "$GREY[*] running afl-fuzz for llvm_mode, this will take approx 10 seconds"
    {
      timeout -s KILL 10 ../afl-fuzz -i in -o out -- ./test-instr.plain > /dev/null 2>&1
    } > /dev/null 2>&1
    test -n "$( ls out/queue/id:000002* 2> /dev/null )" && {
      $ECHO "$GREEN[+] afl-fuzz is working correctly with llvm_mode"
    } || $ECHO "$RED[!] afl-fuzz is not working correctly with llvm_mode"
    rm -rf in out
  } || $ECHO "$YELLOW[-] we cannot test afl-fuzz because we are missing the timeout command"
  rm -f test-instr.plain

  # now for the special llvm_mode things
  AFL_LLVM_INSTRIM=1 AFL_LLVM_INSTRIM_LOOPHEAD=1 ../afl-clang-fast -o test-compcov.instrim test-compcov.c > /dev/null 2> test.out
  test -e test-compcov.instrim && {
    grep -Eq " [1-3] location" test.out && {
      $ECHO "$GREEN[+] llvm_mode InsTrim feature works correctly"
    } || $ECHO "$RED[!] llvm_mode InsTrim feature failed"
  } || $ECHO "$RED[!] llvm_mode InsTrim feature compilation failed"
  rm -f test-compcov.instrim test.out
  AFL_LLVM_LAF_SPLIT_SWITCHES=1 AFL_LLVM_LAF_TRANSFORM_COMPARES=1 AFL_LLVM_LAF_SPLIT_COMPARES=1 ../afl-clang-fast -o test-compcov.compcov test-compcov.c > /dev/null 2> test.out
  test -e test-compcov.compcov && {
    grep -Eq " [3-9][0-9] location" test.out && {
      $ECHO "$GREEN[+] llvm_mode laf-intel/compcov feature works correctly"
    } || $ECHO "$RED[!] llvm_mode laf-intel/compcov feature failed"
  } || $ECHO "$RED[!] llvm_mode laf-intel/compcov feature compilation failed"
  rm -f test-compcov.compcov test.out
  echo foobar.c > whitelist.txt
  AFL_LLVM_WHITELIST=whitelist.txt ../afl-clang-fast -o test-compcov test-compcov.c > test.out 2>&1
  test -e test-compcov && {
    grep -q "No instrumentation targets found" test.out && {
      $ECHO "$GREEN[+] llvm_mode whitelist feature works correctly"
    } || $ECHO "$RED[!] llvm_mode whitelist feature failed"
  } || $ECHO "$RED[!] llvm_mode whitelist feature compilation failed"
  rm -f test-compcov test.out whitelist.txt
  ../afl-clang-fast -o test-persistent ../experimental/persistent_demo/persistent_demo.c > /dev/null 2>&1
  test -e test-persistent && {
    echo foo | ../afl-showmap -o /dev/null -q -r ./test-persistent && {
      $ECHO "$GREEN[+] lvm_mode persistent mode feature works correctly"
    } || $ECHO "$RED[!] llvm_mode persistent mode feature failed to work"
  } || $ECHO "$RED[!] llvm_mode persistent mode feature compilation failed"
  rm -f test-persistent
} || $ECHO "$YELLOW[-] llvm_mode not compiled, cannot test"

$ECHO "$BLUE[*] Testing: shared library extensions"
gcc -o test-compcov test-compcov.c > /dev/null 2>&1
test -e ../libtokencap.so && {
  AFL_TOKEN_FILE=token.out LD_PRELOAD=../libtokencap.so ./test-compcov foobar > /dev/null 2>&1
  grep -q BUGMENOT token.out > /dev/null 2>&1 && {
    $ECHO "$GREEN[+] libtokencap did successfully capture tokens"
  } || $ECHO "$RED[!] libtokencap did not capture tokens"
  rm -f token.out
} || $ECHO "$YELLOW[-] libtokencap is not compiled, cannot test"
test -e ../libdislocator.so && {
  {
    ulimit -c 1
    LD_PRELOAD=../libdislocator.so ./test-compcov BUFFEROVERFLOW > test.out 2> /dev/null
  } > /dev/null 2>&1
  grep -q BUFFEROVERFLOW test.out > /dev/null 2>&1 && {
    $ECHO "$RED[!] libdislocator did not detect the memory corruption"
  } || $ECHO "$GREEN[+] libdislocator did successfully detect the memory corruption" 
  rm -f test.out core test-compcov.core core.test-compcov
} || $ECHO "$YELLOW[-] libdislocator is not compiled, cannot test"
rm -f test-compcov

$ECHO "$BLUE[*] Testing: qemu_mode"
test -e ../afl-qemu-trace && {
  gcc -o test-instr ../test-instr.c
  gcc -o test-compcov test-compcov.c
  test -e test-instr -a -e test-compcov && {
    test -n "$TIMEOUT" && {
      mkdir -p in
      echo 0 > in/in
      $ECHO "$GREY[*] running afl-fuzz for qemu_mode, this will take approx 10 seconds"
      {
        timeout -s KILL 10 ../afl-fuzz -Q -i in -o out -- ./test-instr > /dev/null 2>&1
      } > /dev/null 2>&1
      test -n "$( ls out/queue/id:000002* 2> /dev/null )" && {
        $ECHO "$GREEN[+] afl-fuzz is working correctly with qemu_mode"
      } || $ECHO "$RED[!] afl-fuzz is not working correctly with qemu_mode"

      test -e ../libcompcov.so && {
        $ECHO "$GREY[*] running afl-fuzz for qemu_mode libcompcov, this will take approx 10 seconds"
        {
          export AFL_PRELOAD=../libcompcov.so 
          export AFL_COMPCOV_LEVEL=2
          timeout -s KILL 10 ../afl-fuzz -Q -i in -o out -- ./test-compcov > /dev/null 2>&1
        } > /dev/null 2>&1
        test -n "$( ls out/queue/id:000002* 2> /dev/null )" && {
          $ECHO "$GREEN[+] afl-fuzz is working correctly with qemu_mode libcompcov"
        } || $ECHO "$RED[!] afl-fuzz is not working correctly with qemu_mode libcompcov"
      } || $ECHO "$YELLOW[-] we cannot test qemu_mode libcompcov because it is not present"
      rm -rf in out
    } || $ECHO "$YELLOW[-] we cannot test afl-fuzz because we are missing the timeout command"
  } || $ECHO "$RED[-] gcc compilation of test targets failed - what is going on??"
  
  $ECHO "$YELLOW[?] we need a test case for qemu_mode persistent mode"

  rm -f test-instr test-compcov
} || $ECHO "$YELLOW[-] qemu_mode is not compiled, cannot test"

$ECHO "$GREY[*] all test cases completed.$RESET"

# unicorn_mode ?
